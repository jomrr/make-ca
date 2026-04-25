# repo: jomrr/make-ca
# file: Makefile

# =============================================================================
# Makefile for operating an openssl certificate authority
# =============================================================================

MAKEFLAGS	+= --no-builtin-rules
MAKEFLAGS	+= --warn-undefined-variables

# parallel execution is too risky for openssl CA operations
.NOTPARALLEL:

# shell to use
SHELL		:= /bin/bash
.SHELLFLAGS	:= -euo pipefail -c

.DEFAULT_GOAL	:= help

# openssl binary
OPENSSL		:= /usr/bin/openssl

# destroy directories
DESTROY		:= archive/ ca/ dist/ pub/

# ca default settings
include		settings.mk
# variables for dynamic targets
include 	targets.mk

# dist per ca and cert type for easier management of artifacts
DIST_BASE	:= dist/$(CA)/$(CERT_TYPE)

# do not treat as intermediate targets, to prevent deletion
.NOTINTERMEDIATE: dist/%/ $(DIST_BASE)/%/

# keep these files
.PRECIOUS: \
	ca/certs/%.pem \
	ca/db/%.crlnumber \
	ca/db/%.serial \
	ca/db/%.txt \
	ca/db/%.txt.attr \
	ca/private/%.key \
	ca/private/%.pwd \
	ca/reqs/%.csr \
	$(DIST_BASE)/%/bundle.p12 \
	$(DIST_BASE)/%/certificate.der \
	$(DIST_BASE)/%/certificate.pem \
	$(DIST_BASE)/%/certificate.txt \
	$(DIST_BASE)/%/fullchain.pem \
	$(DIST_BASE)/%/private.key \
	$(DIST_BASE)/%/private.pwd \
	$(DIST_BASE)/%/request.csr \
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
	@printf '%s\n' "Usage: make [target] [CPK_ALG=algorithm]"
	@printf '%s\n' "       make certs/*  Create certs from static conf"
	@printf '%s\n' "       make renew/*  Renew certs from static conf"
	@printf '%s\n\n' "       make revoke/* [REASON=<default=superseded>]"
	@printf '%s\n' "Static conf provided by etc/<CA>/<CERT_TYPE>/<ID>.cnf"
	@printf '%s\n' "Default values are defined in settings.mk"

.PHONY: all
all: init

# delete CSRs in dist/
.PHONY: clean
clean:
	@test ! -d dist || find dist -type f -name request.csr -delete

# delete dist/
.PHONY: distclean
distclean:
	@rm -rf dist/

# delete everything but make and the config dir
.PHONY: destroy
destroy:
	@rm -Ir $(DESTROY)

# destroy everything without asking
.PHONY: force-destroy mrproper
force-destroy mrproper:
	@rm -rf $(DESTROY)

# init all CAs and generate initial CRLs
.PHONY: init crls
init crls: $(foreach ca,$(ALL_CA),pub/$(ca).crl)

# print CA db files with CA name for grepping serials, revoked, etc.
.PHONY: print
print:
	@bin/print ca/db

.PHONY: print-full
print-full:
	@bin/print --full ca/db

# create Private KEY
$(DIST_BASE)/%/private.key: | $(DIST_BASE)/%/
	@umask 077; $(OPENSSL) genpkey -out $@ -algorithm $(CPK_ALG)
	@chmod 600 $@

# create CSR, config is selected by calling target
$(DIST_BASE)/%/request.csr: $(DIST_BASE)/%/private.key etc/$(CA)/$(CERT_TYPE)/%.cnf | $(DIST_BASE)/%/
	@$(OPENSSL) req -batch -new -config etc/$(CA)/$(CERT_TYPE)/$*.cnf -key $(DIST_BASE)/$*/private.key -out $@ -outform PEM

# issue PEM certificate from CSR
$(DIST_BASE)/%/certificate.pem: $(DIST_BASE)/%/request.csr etc/$(CA).cnf ca/certs/$(CA).pem ca/private/$(CA).key ca/private/$(CA).pwd | $(DIST_BASE)/%/
	@$(OPENSSL) ca -batch -notext -create_serial -config etc/$(CA).cnf -in $< -out $@ -extensions $(CERT_TYPE)_ext -passin file:ca/private/$(CA).pwd

# create pkcs12 bundle with key, crt and ca-chain
$(DIST_BASE)/%/bundle.p12: $(DIST_BASE)/%/private.key $(DIST_BASE)/%/certificate.pem pub/$(CA)-chain.pem | $(DIST_BASE)/%/
	@umask 077; $(OPENSSL) pkcs12 -export -name "$*" -inkey $< -in $(DIST_BASE)/$*/certificate.pem -certfile pub/$(CA)-chain.pem -out $@
	@chmod 600 $@

# create pem bundle with crt and ca-chain
$(DIST_BASE)/%/fullchain.pem: $(DIST_BASE)/%/certificate.pem pub/$(CA)-chain.pem
	@cat $< pub/$(CA)-chain.pem > $@

# export certificate in DER format
$(DIST_BASE)/%/certificate.der: $(DIST_BASE)/%/certificate.pem
	@$(OPENSSL) x509 -in $< -out $@ -outform DER

# export certificate in txt format
$(DIST_BASE)/%/certificate.txt: $(DIST_BASE)/%/certificate.pem
	@$(OPENSSL) x509 -in $< -text -noout > $@

# dynamic target for certificate generation
.PHONY: $(CERTS)
$(CERTS): certs/$(CA)/$(CERT_TYPE)/%: $(DIST_BASE)/%/request.csr $(DIST_BASE)/%/certificate.pem $(DIST_BASE)/%/fullchain.pem $(DIST_BASE)/%/certificate.der $(DIST_BASE)/%/certificate.txt
	@echo "CERT: $@"
	@ls -la $(DIST_BASE)/$*/

# dynamic target for p12 bundle generation
.PHONY: $(P12S)
$(P12S): p12/$(CA)/$(CERT_TYPE)/%: $(DIST_BASE)/%/bundle.p12
	@echo "P12: $@"
	@ls -la $(DIST_BASE)/$*/bundle.p12

# dynamic target for certificate renewal
.PHONY: $(RENEWS)
$(RENEWS): renew/$(CA)/$(CERT_TYPE)/%: renew-% $(DIST_BASE)/%/certificate.txt pub/$(CA).crl
	@echo "RENEW: $@"
	@ls -la $(DIST_BASE)/$*/

# dynamic target for certificate revocation
.PHONY: $(REVOKES)
$(REVOKES): revoke/$(CA)/$(CERT_TYPE)/%: revoke-% pub/$(CA).crl
	@echo "REVOKE: $@"
	@ls -la archive/$(CA)-$(CERT_TYPE)-$*.*

# renew a certificate with existing key
.PHONY: renew-%
renew-%: archive-%
	@$(OPENSSL) ca -batch -config etc/$(CA).cnf -revoke $(DIST_BASE)/$*/certificate.pem -passin file:ca/private/$(CA).pwd -crl_reason superseded
	@rm -f $(DIST_BASE)/$*/*.{csr,der,pem,p12,txt}

# revoke a certificate
.PHONY: revoke-%
revoke-%: archive-%
	@$(OPENSSL) ca -batch -config etc/$(CA).cnf -revoke $(DIST_BASE)/$*/certificate.pem -passin file:ca/private/$(CA).pwd -crl_reason $(REASON)
	@rm -rf $(DIST_BASE)/$*/

# create archive of certificate artifacts
.PHONY: archive-%
archive-%: | archive/
	@test -f $(DIST_BASE)/$*/certificate.pem || { echo "error: missing $(DIST_BASE)/$*/certificate.pem" >&2; exit 2; }
	@tar -czvf "archive/$(CA)-$(CERT_TYPE)-$*.$(DATETIME).tar.gz" $(DIST_BASE)/$*/

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
ca/reqs/%.csr: ca/private/%.key ca/private/%.pwd etc/%.cnf | ca/reqs/
	@$(OPENSSL) req -batch -new -config etc/$*.cnf -key $< -passin file:ca/private/$*.pwd -out $@ -outform PEM

# create ca private key
ca/private/%.key: | ca/private/%.pwd
	@umask 077; $(OPENSSL) genpkey -out $@ -algorithm $(CAK_ALG) -aes256 -pass file:ca/private/$*.pwd
	@chmod 600 $@

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
	@umask 077; $(OPENSSL) rand -hex 64 > $@
	@chmod 600 $@

ca/ ca/certs/ pub/:
	@install -d -m 755 $@

ca/db/ ca/new/ ca/private/ ca/reqs/: | ca/
	@install -d -m 700 $@

archive/ dist/:
	@install -d -m 700 $@

dist/%/: | dist/
	@install -d -m 700 $@

# basic tests
.PHONY: test-vars
test-vars:
	@echo "CAK_ALG: $(CAK_ALG)"
	@echo "CPK_ALG: $(CPK_ALG)"

.PHONY: test
test:
	$(MAKE) mrproper 1>/dev/null
	$(MAKE) init 1>/dev/null
	$(MAKE) crls 1>/dev/null
	$(MAKE) certs/component-ca/server/fritzbox 1>/dev/null
	$(MAKE) revoke/component-ca/server/fritzbox REASON=superseded 1>/dev/null
	$(MAKE) crls 1>/dev/null
	$(MAKE) mrproper 1>/dev/null
