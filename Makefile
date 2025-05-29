# Makefile for operating a certificate authority

# shell to use
SHELL			:= bash
# openssl binary
OPENSSL			:= /usr/bin/openssl
OPENSSL_CA		:= $(OPENSSL) ca -batch -new -create_serial
# destroy directories
DESTROY			:= archive/ ca/ dist/ pub/

# ca default settings
include			settings.mk
# variables for dynamic targets
include 		targets.mk

# keep these files
.PRECIOUS: \
	archive/%.tar.gz \
	ca/certs/%.pem \
	ca/db/%.crlnumber \
	ca/db/%.serial \
	ca/db/%.txt \
	ca/db/%.txt.attr \
	ca/private/%.key \
	ca/private/%.pwd \
	ca/reqs/%.csr \
	dist/%.csr \
	dist/%.der \
	dist/%.key \
	dist/%.p12 \
	dist/%.pem \
	dist/%-fullchain.pem \
	dist/%.pwd \
	dist/%.txt \
	etc/%.cnf \
	pub/%.der \
	pub/%.pem \
	pub/%.txt \
	pub/%-chain.der \
	pub/%-chain.pem

# ******************************************************************************
# make targets start here
# ******************************************************************************

.PHONY: help
help:
	echo "Usage: make [target] [CPK_ALG=algorithm]"
	echo "       make certs/*  Create certificates from static conf"
	echo "       make renew/*  Renew certificates from static conf"
	echo "       make revoke/* [REASON=reason,default=superseded]\n"
	echo "Static conf is provided by etc/<CA>/<CERT_TYPE>/<IDENTIFIER>.cnf"
	echo "Default values are defined in settings.mk"

.PHONY: all
all: init

# delete CSRs in dist/
.PHONY: clean
clean:
	@rm -f dist/*.csr

# delete dist/
.PHONY: distclean
distclean:
	@rm -rf dist/

# delete everything but make and the config dir
.PHONY: destroy
destroy:
	@rm -Ir $(DESTROY)

# destroy everything without asking
force-destroy:
	@rm -rf $(DESTROY)

# init all CAs and generate initial CRLs
.PHONY: init crls
init crls: $(foreach ca,$(ALL_CA),pub/$(ca).crl)

# print CA db files with CA name for grepping serials, revoked, etc.
.PHONY: print
print:
	@for DB in ca/db/*.txt; do \
		BASENAME=$$(basename "$$DB" .txt); \
		CA_SLUG=$$(echo "$$BASENAME"); \
		awk -v filename="$$CA_SLUG" '{ \
			gsub(/[ \t]+/, " "); \
			printf "%s %s\n", filename, $$0; \
		}' "$$DB"; \
	done

# create Private KEY
dist/%.key: | dist/
	@$(OPENSSL) genpkey -out $@ -algorithm $(CPK_ALG)

# create CSR, config is selected by calling target
dist/%.csr: | dist/%.key dist/
	@$(OPENSSL) req -batch -new -config etc/$(CA)/$(CERT_TYPE)/$*.cnf -key dist/$*.key -out $@ -outform PEM

# issue PEM certificate from CSR
dist/%.pem: dist/%.csr | dist/
	@$(OPENSSL) ca -batch -notext -create_serial -config etc/$(CA).cnf -in $< -out $@ -extensions $(CERT_TYPE)_ext -passin file:ca/private/$(CA).pwd

# create pkcs12 bundle with key, crt and ca-chain
dist/%.p12: dist/%.key dist/%.txt pub/$(CA)-chain.pem | dist/
	@$(OPENSSL) pkcs12 -export -name "$*" -inkey $< -in dist/$*.pem -certfile pub/$(CA)-chain.pem -out $@

# create pem bundle with crt and ca-chain
dist/%-fullchain.pem: dist/%.pem dist/%.csr
	@cat $< pub/$(CA)-chain.pem > $@

# export certificate in DER format
dist/%.der: dist/%-fullchain.pem dist/%.pem dist/%.csr
	@$(OPENSSL) x509 -in dist/$*.pem -out $@ -outform DER

# export certificate in txt format
dist/%.txt: dist/%.der dist/%-fullchain.pem dist/%.pem dist/%.csr
	@$(OPENSSL) x509 -in dist/$*.pem -text -noout > $@

# dynamic target for certificate generation
.PHONY: $(CERTS)
$(CERTS): certs/$(CA)/$(CERT_TYPE)/%: dist/%.txt dist/%.pem dist/%.csr
	@echo "CERT: $@"
	@ls -la dist/$*.*

# dynamic target for p12 bundle generation
.PHONY: $(P12S)
$(P12S): p12/$(CA)/$(CERT_TYPE)/%: dist/%.p12
	@echo "P12: $@"
	@ls -la dist/$*.p12

# dynamic target for certificate renewal
.PHONY: $(RENEWS)
$(RENEWS): renew/$(CA)/$(CERT_TYPE)/%: renew-% dist/%.txt pub/$(CA).crl
	@echo "RENEW: $@"
	@ls -la dist/$*.*

# dynamic target for certificate revocation
.PHONY: $(REVOKES)
$(REVOKES): revoke/$(CA)/$(CERT_TYPE)/%: revoke-% pub/$(CA).crl
	@echo "REVOKE: $@"
	@ls -la archive/$*.*

# renew a certificate with existing key
.PHONY: renew-%
renew-%: archive/%.tar.gz
	@$(OPENSSL) ca -batch -config etc/$(CA).cnf -revoke dist/$*.pem -passin file:ca/private/$(CA).pwd -crl_reason superseded
	@rm -f dist/$**.{csr,der,pem,p12,txt}

# revoke a certificate
.PHONY: revoke-%
revoke-%: archive/%.tar.gz
	@$(OPENSSL) ca -batch -config etc/$(CA).cnf -revoke dist/$*.pem -passin file:ca/private/$(CA).pwd -crl_reason $(REASON)
	@rm -f dist/$**.*

# create archive of certificate artifacts
archive/%.tar.gz: | archive/
	@tar -czvf "archive/$*.$(DATETIME).tar.gz" dist/$*.*

# generate CRL for CAs and initialize if needed
pub/%.crl: pub/%-chain.der ca/db/%.txt | ca/db/%.crlnumber pub/
	@$(OPENSSL) ca -gencrl -config etc/$*.cnf -passin file:ca/private/$*.pwd -out pub/$*.crl.pem
	@$(OPENSSL) crl -in "pub/$*.crl.pem" -out $@ -outform DER

pub/%-chain.der: pub/%-chain.pem | pub/
	@$(OPENSSL) x509 -in $< -out $@ -outform DER

pub/root-ca-chain.pem: pub/%-chain.pem: pub/%.txt | pub/
	@cat pub/root-ca.pem > $@

pub/intermediate-ca-chain.pem: pub/%-chain.pem: pub/%.pem pub/%.txt | pub/
	@cat $< pub/root-ca.pem > $@

# create PEM certificate chain for issuing ca
pub/%-chain.pem: pub/%.pem pub/%.txt | pub/
	@cat $< pub/intermediate-ca.pem pub/root-ca.pem > $@

pub/%.txt: pub/%.der | pub/
	@$(OPENSSL) x509 -in $< -text -noout > $@

# create DER export of ca certificate
pub/%.der: pub/%.pem | pub/
	@$(OPENSSL) x509 -in $< -out $@ -outform DER

# export ca certificate in PEM format. it already should be.
pub/%.pem: ca/certs/%.pem | pub/
	@$(OPENSSL) x509 -in $< -out $@ -outform PEM

# generate root ca certificate
ca/certs/root-ca.pem: ca/certs/%.pem: ca/reqs/%.csr | ca/db/%.txt ca/certs/ ca/new/
	@$(OPENSSL) ca -batch -notext -create_serial -config etc/$*.cnf -passin file:ca/private/$*.pwd -selfsign -in $< -out $@

# generate intermediate ca certificate
ca/certs/intermediate-ca.pem: ca/certs/%.pem: ca/reqs/%.csr ca/certs/root-ca.pem | ca/db/%.txt ca/certs/ ca/new/
	@$(OPENSSL) ca -batch -notext -create_serial -config etc/root-ca.cnf -keyfile ca/private/root-ca.key -passin file:ca/private/root-ca.pwd -in $< -out $@

# generate issuing ca certificates
ca/certs/%.pem: ca/reqs/%.csr ca/certs/intermediate-ca.pem | ca/db/%.txt ca/certs/ ca/new/
	@$(OPENSSL) ca -batch -notext -create_serial -config etc/intermediate-ca.cnf -keyfile ca/private/intermediate-ca.key -passin file:ca/private/intermediate-ca.pwd -in $< -out $@

# create ca certificate signing request
ca/reqs/%.csr: ca/private/%.key | ca/reqs/
	@$(OPENSSL) req -batch -new -config etc/$*.cnf -key $< -passin file:ca/private/$*.pwd -out $@ -outform PEM

# create ca private key
ca/private/%.key: | ca/private/%.pwd
	@$(OPENSSL) genpkey -out $@ -algorithm $(CAK_ALG) -aes256 -pass file:ca/private/$*.pwd

ca/db/%.crlnumber: | ca/db/
	@install -m 600 /dev/null $@
	@echo 01 > $@

ca/db/%.txt: | ca/db/%.txt.attr
	@install -m 600 /dev/null $@

ca/db/%.txt.attr: | ca/db/
	@install -m 600 /dev/null $@
	@echo "unique_subject = no" > $@

# create password for encrypted private keys
ca/private/%.pwd: | ca/private/
	@$(OPENSSL) rand -hex 64 > $@

archive/ ca/db/ ca/new/ ca/private/ ca/reqs/: | ca/
	@mkdir -m 700 -p $@

ca/ ca/certs/ dist/ pub/ dist/$(CA)/$(CERT_TYPE)/:
	@mkdir -m 755 -p $@

# basic tests
.PHONY: test
test-vars:
	echo "CAK_ALG: $(CAK_ALG)"
	echo "CPK_ALG: $(CPK_ALG)"
test:
	$(MAKE) force-destroy 1>/dev/null
	$(MAKE) init 1>/dev/null
	$(MAKE) crls 1>/dev/null
	$(MAKE) certs/component-ca/server/fritzbox 1>/dev/null
	$(MAKE) revoke/component-ca/server/fritzbox REASON=superseded 1>/dev/null
	$(MAKE) crls 1>/dev/null
	$(MAKE) force-destroy 1>/dev/null
