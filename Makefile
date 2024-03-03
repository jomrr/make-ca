# Makefile for operating a certificate authority

# ******************************************************************************
# configuration variables
# ******************************************************************************
SHELL			:= bash
OPENSSL			:= /usr/bin/openssl

# ca default settings
include			settings.mk

# list of CA slugs
ROOT_CA			:= root-ca
SIGNING_CA		:= intermediate-ca
ISSUING_CA		:= component-ca identity-ca
ALL_CA			:= $(ROOT_CA) $(SIGNING_CA) $(ISSUING_CA)

# operational settings
FILENAME		?= $(if $(EMAIL),$(EMAIL),$(CN))
DATETIME		:= $(shell date +%Y-%m-%dT%H:%M:%S%z)

# delete files by CN
define delete
	find dist -type f -regextype posix-extended \
		-regex ".*/$(1)\.[^\.]+" -exec rm -f {} +
endef

# revoke a certificate by CN, CA and REASON
define revoke
	$(OPENSSL) ca -batch \
		-config etc/$(2).cnf \
		-revoke dist/$(1).pem \
		-passin file:ca/private/$(2).pwd \
		-crl_reason $(3)
endef

# ******************************************************************************
# make settings
# ******************************************************************************

# keep these files
.PRECIOUS: \
	ca/certs/%.der \
	ca/certs/%.pem \
	ca/certs/%.txt \
	ca/db/%.dat \
	ca/db/%.txt \
	ca/db/%.txt.attr \
	ca/private/%.key \
	ca/private/%.pwd \
	ca/reqs/%.csr \
	etc/%.cnf \
	dist/%.csr \
	dist/%.der \
	dist/%.pem \
	dist/%.key \
	dist/%.p12 \
	dist/%.pem \
	dist/%.txt \
	pub/%.der \
	pub/%.pem \
	pub/%-chain.der \
	pub/%-chain.p7c \
	pub/%-chain.pem

# ******************************************************************************
# make targets start here
# ******************************************************************************

.PHONY: help
help:
	echo "Usage: make [target] [KEY_ALG=algorithm]"
	echo "       make client   [CN=name]"
	echo "       make server   [CN=name] [SAN=DNS:othername[,..]]"
	echo "       make smime    [CN=name] [EMAIL=address] [SAN=email:mail[,..]]"
	echo "       make revoke   [CA=slug] [CN=name] [REASON=reason]\n"
	echo "Default values are defined in settings.mk"

#create CSR and KEY, config is selected by calling target
dist/%.csr: | dist/
	$(OPENSSL) req \
		-new \
		-newkey $(CPK_ALG) \
		-config etc/$(MAKECMDGOALS).cnf \
		-keyout dist/$*.key -out $@ -outform PEM

#issue CRT by CA
dist/%.pem: dist/%.csr
	$(OPENSSL) ca \
		-batch \
		-notext \
		-create_serial \
		-config etc/$(CA).cnf \
		-in $< \
		-out $@ \
		-extensions $(MAKECMDGOALS)_ext \
		-passin file:ca/private/$(CA).pwd

#create pkcs12 bundle with key, crt and ca-chain
dist/%.p12: dist/%.pem
	$(OPENSSL) pkcs12 \
		-export \
		-name "$*" \
		-inkey dist/$*.key \
		-in $< \
    	-certfile pub/$(CA)-chain.pem \
		-out $@

#create pem bundle with crt and ca-chain
dist/%-fullchain.pem: dist/%.pem
	cat dist/$*.pem pub/$(CA)-chain.pem > $

#create tls client certificate
.PHONY: client
client: CA=component-ca
client: CPK_ALG=RSA:4096
client: dist/$(FILENAME).p12

# create tls certificate for fritzbox
.PHONY: fritzbox
fritzbox: CA=component-ca
fritzbox: dist/$(FRITZBOX_PUBLIC).myfritz.net.pem

# print CA db files with CA name for grepping serials, revoked, etc.
.PHONY: print
print:
	for DB in ca/db/*.txt; do \
		BASENAME=$$(basename "$$DB" .txt); \
		CA_SLUG=$$(echo "$$BASENAME" | cut -d '-' -f1); \
		awk -v filename="$$CA_SLUG" '{ \
			gsub(/[ \t]+/, " "); \
			printf "%-12s: %s\n", filename, $$0; \
		}' "$$DB"; \
	done

# revoke CRT by CA and rebuild its CRL
REVOKE_TARGETS := $(foreach ca,$(ISSUING_CA),revoke-$(ca))

.PHONY: $(REVOKE_TARGETS)
$(REVOKE_TARGETS): revoke-%: $(ARCHPATH)
	$(call revoke,$(FILENAME),$*,$(if $(REASON),$(REASON),superseded))
	$(call delete,$(FILENAME))
	$(MAKE) pub/$*.crl

ca/archive/%.tar.gz:
	mkdir -m 700 -p ca/archive
	tar -czvf $(ARCHPATH) $(ARCHFILES)

# create tls server certificate
.PHONY: server
server: CA=component-ca
server: dist/$(FILENAME).pem

# create certificate with smime extensions
.PHONY: smime
smime: CA=identity-ca
smime: dist/$(FILENAME).pem

# delete CSRs
.PHONY: clean
clean:
	rm dist/$(FILENAME).csr

# delete KEYs and CERTs and also CSRs through clean
.PHONY: distclean
distclean: clean
	rm dist/$(FILENAME).{crt,der,key,pem,p12,txt}

# delete everything but make and the config dir
.PHONY: destroy
destroy:
	rm -Ir ./ca/ ./dist/ ./pub/

# destroy everything without asking
force-destroy:
	rm -rf ./ca/ ./dist/ ./pub/

# init all CAs and generate initial CRLs
.PHONY: init crls
init crls: $(foreach ca,$(ALL_CA),pub/$(ca).crl)

# generate CRL for CAs and initialize if needed
pub/%.crl: pub/%-chain.pem ca/db/%.txt | ca/db/%.crlnumber pub/
	openssl ca -gencrl -config etc/$*.cnf -passin file:ca/private/$*.pwd -out pub/$*.crl.pem
	openssl crl -in "pub/$*.crl.pem" -out $@ -outform DER
	rm -f pub/$*.crl.pem

pub/root-ca-chain.pem: pub/%-chain.pem: pub/%.pem | pub/
	cat pub/root-ca.pem > $@

pub/intermediate-ca-chain.pem: pub/%-chain.pem: pub/%.pem | pub/
	cat $< pub/root-ca.pem > $@

# create PEM certificate chain for issuing ca
pub/%-chain.pem: pub/%.pem | pub/
	cat $< pub/intermediate-ca.pem pub/root-ca.pem > $@

# create DER export of ca certificate
pub/%.der: pub/%.pem | pub/
	$(OPENSSL) x509 -in $< -out $@ -outform DER

# export ca certificate in PEM format. it already should be.
pub/%.pem: ca/certs/%.pem | pub/
	$(OPENSSL) x509 -in $< -out $@ -outform PEM

# issue root ca certificate
ca/certs/root-ca.pem: ca/certs/%.pem: ca/reqs/%.csr | ca/db/%.txt ca/certs/ ca/new/
	$(OPENSSL) ca -batch -notext -create_serial -config etc/$*.cnf -passin file:ca/private/$*.pwd -selfsign -in $< -out $@

# issue intermediate ca certificate
ca/certs/intermediate-ca.pem: ca/certs/%.pem: ca/reqs/%.csr ca/certs/root-ca.pem | ca/db/%.txt ca/certs/ ca/new/
	$(OPENSSL) ca -batch -notext -create_serial -config etc/root-ca.cnf -keyfile ca/private/root-ca.key -passin file:ca/private/root-ca.pwd -in $< -out $@

# issue ca certificate
ca/certs/%.pem: ca/reqs/%.csr ca/certs/intermediate-ca.pem | ca/db/%.txt ca/certs/ ca/new/
	$(OPENSSL) ca -batch -notext -create_serial -config etc/intermediate-ca.cnf -keyfile ca/private/intermediate-ca.key -passin file:ca/private/intermediate-ca.pwd -in $< -out $@

# create ca certificate signing request
ca/reqs/%.csr: ca/private/%.key | ca/reqs/
	$(OPENSSL) req -batch -new -config etc/$*.cnf -key $< -passin file:ca/private/$*.pwd -out $@ -outform PEM

# create ca private key
ca/private/%.key: | ca/private/%.pwd
	$(OPENSSL) genpkey -out $@ -algorithm $(CAK_ALG) -aes256 -pass file:ca/private/$*.pwd

ca/db/%.crlnumber: | ca/db/
	install -m 600 /dev/null $@
	echo 01 > $@

ca/db/%.txt: | ca/db/%.txt.attr
	install -m 600 /dev/null $@

ca/db/%.txt.attr: | ca/db/
	install -m 600 /dev/null $@
	echo "unique_subject = no" > $@

# create password for encrypted private keys
ca/private/%.pwd: | ca/private/
	$(OPENSSL) rand -hex 64 > $@

ca/archive/ ca/db/ ca/new/ ca/private/ ca/reqs/: | ca/
	mkdir -m 700 -p $@

ca/ ca/certs/ dist/ pub/:
	mkdir -m 755 -p $@

# test all targets
.PHONY: test
test:
	$(MAKE) force-destroy 1>/dev/null
	CAK_ALG=ED25519 $(MAKE) init
	CPK_ALG=ED25519 $(MAKE) server CN=test.example.com SAN=DNS:www.example.com 1>/dev/null
	CPK_ALG=ED25519 $(MAKE) fritzbox 1>/dev/null
	CPK_ALG=ED25519 $(MAKE) revoke-component-ca CN=test.example.com 1>/dev/null
	CPK_ALG=ED25519 $(MAKE) smime CN="test user" EMAIL="testexample.com" 1>/dev/null

# catch all unkown targets and inform
# %:
# 	echo "INFO: omitting unknown target:\t%s\n" $ 1>&2
# 	:
