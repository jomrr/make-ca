# Makefile for operating a certificate authority

# ******************************************************************************
# configuration variables
# ******************************************************************************
SHELL			:= bash
OPENSSL			:= /usr/bin/openssl

# ca default settings
include			settings.mk

# list of CA slugs
ROOT_CA			:= root
SIGNING_CA		:= intermediate
ISSUING_CA		:= component identity
ALL_CA			:= $(ROOT_CA) $(SIGNING_CA) $(ISSUING_CA)

# operational settings
FILENAME		?= $(if $(EMAIL),$(EMAIL),$(CN))
DATETIME		:= $(shell date +%Y-%m-%dT%H:%M:%S%z)
ARCHPATH		:= ca/archive/$(FILENAME)-$(DATETIME).tar.gz
ARCHFILES		:= $(shell find dist -type f -regextype posix-extended \
		-regex ".*/$(FILENAME)\.[^\.]+$$")

# delete files by CN
define delete
	find dist -type f -regextype posix-extended \
		-regex ".*/$(1)\.[^\.]+" -exec rm -f {} +
endef

# revoke a certificate by CN, CA and REASON
define revoke
	/usr/bin/openssl ca -batch \
		-config etc/$(2)-ca.cnf \
		-revoke dist/$(1).pem \
		-passin file:ca/private/$(2)-ca.pwd \
		-crl_reason $(3)
endef

# ******************************************************************************
# make settings
# ******************************************************************************

# keep these files
.PRECIOUS: \
	ca/certs/%-ca.pem \
	ca/db/%-ca.dat \
	ca/db/%-ca.txt \
	ca/db/%-ca.txt.attr \
	ca/private/%-ca.key.pem \
	ca/private/%-ca.pwd \
	ca/reqs/%-ca.csr.pem \
	etc/%.cnf \
	dist/%.csr.pem \
	dist/%.der \
	dist/%.pem \
	dist/%.key.pem \
	dist/%.p12 \
	dist/%.pem \
	dist/%.txt \
	pub/%-ca.der \
	pub/%-ca.pem \
	pub/%-ca-chain.der \
	pub/%-ca-chain.p7c \
	pub/%-ca-chain.pem

# ******************************************************************************
# make targets start here
# ******************************************************************************

.PHONY: help
help:
	@bin/$@

#create CSR and KEY, config is selected by calling target
dist/%.csr.pem:
	@/usr/bin/openssl req \
		-new \
		-newkey $(CPK_ALG) \
		-config etc/$(MAKECMDGOALS).cnf \
		-keyout dist/$*.key.pem -out $@ -outform PEM

#issue CRT by CA
dist/%.pem: dist/%.csr.pem
	@/usr/bin/openssl ca \
		-batch \
		-notext \
		-create_serial \
		-config etc/$(CA)-ca.cnf \
		-in $< \
		-out $@ \
		-extensions $(MAKECMDGOALS)_ext \
		-passin file:ca/private/$(CA)-ca.pwd

#create pkcs12 bundle with key, crt and ca-chain
dist/%.p12: dist/%.pem
	@/usr/bin/openssl pkcs12 \
		-export \
		-name "$*" \
		-inkey dist/$*.key.pem \
		-in $< \
    	-certfile pub/$(CA)-ca-chain.pem \
		-out $@

#create pem bundle with crt and ca-chain
dist/%-fullchain.pem: dist/%.pem
	@cat dist/$*.pem pub/$(CA)-ca-chain.pem > $@

#create tls client certificate
.PHONY: client
client: CA=component
client: CPK_ALG=RSA:4096
client: dist/$(FILENAME).p12

# create tls certificate for fritzbox
.PHONY: fritzbox
fritzbox: CA=component
fritzbox: dist/$(FRITZBOX_PUBLIC).myfritz.net.pem

# print CA db files with CA name for grepping serials, revoked, etc.
.PHONY: print
print:
	@for DB in ca/db/*-ca.txt; do \
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
	@$(call revoke,$(FILENAME),$*,$(if $(REASON),$(REASON),superseded))
	@$(call delete,$(FILENAME))
	@$(MAKE) pub/$*-ca.crl

ca/archive/%.tar.gz:
	@mkdir -m 700 -p ca/archive
	@tar -czvf $(ARCHPATH) $(ARCHFILES)

# create tls server certificate
.PHONY: server
server: CA=component
server: dist/$(FILENAME).pem

# create certificate with smime extensions
.PHONY: smime
smime: CA=identity
smime: dist/$(FILENAME).pem

# delete CSRs
.PHONY: clean
clean:
	@rm dist/$(FILENAME).csr.pem

# delete KEYs and CERTs and also CSRs through clean
.PHONY: distclean
distclean: clean
	@rm dist/$(FILENAME).{crt,key,pem,p12}

# delete everything but make and the config dir
.PHONY: destroy
destroy:
	@rm -Ir ./ca/ ./dist/ ./pub/

# destroy everything without asking
force-destroy:
	@rm -rf ./ca/ ./dist/ ./pub/

# init all CAs and generate initial CRLs
.PHONY: init crls
init crls: $(foreach ca,$(ALL_CA),pub/$(ca)-ca.crl)

# generate CRL for CAs and initialize if needed
pub/%-ca.crl: pub/%-ca-chain.p7c ca/db/%-ca.txt
	@bin/crl --ca $*

# create PKCS7 certificate chain for ca
pub/%-ca-chain.p7c: pub/%-ca-chain.pem
	@bin/chain --ca $* --format p7c

# create PEM certificate chain for ca
pub/%-ca-chain.pem: pub/%-ca.der
	@bin/chain --ca $* --format pem

# create DER export of ca certificate
pub/%-ca.der: pub/%-ca.pem
	@/usr/bin/openssl x509 \
		-in pub/$*-ca.pem \
		-out pub/$*-ca.der \
		-outform DER

# export ca certificate in PEM format. it already should be.
pub/%-ca.pem: ca/certs/%-ca.pem
	@/usr/bin/openssl x509 \
		-in ca/certs/$*-ca.pem \
		-out pub/$*-ca.pem \
		-outform PEM

# issue ca certificate
ca/certs/%-ca.pem: ca/reqs/%-ca.csr.pem
	@bin/ca-crt --ca $*

# additional dependency for Intermediate CA
ca/certs/intermediate-ca.pem: ca/certs/root-ca.pem

# additional dependency for Issuing CAs
$(foreach ca,$(ISSUING_CA),ca/certs/$(ca)-ca.pem): ca/certs/intermediate-ca.pem

# create ca certificate signing request
ca/reqs/%-ca.csr.pem: ca/private/%-ca.key.pem
	@/usr/bin/openssl req \
		-batch  \
		-new \
		-config etc/$*-ca.cnf \
		-out $@ -outform PEM \
		-key $< -passin file:$(patsubst %.key.pem,%.pwd,$<)

# create ca private key
ca/private/%-ca.key.pem: ca/private/%-ca.pwd
	@/usr/bin/openssl genpkey \
		-out $@ \
		-algorithm $(CAK_ALG) \
		-aes256 -pass file:$<

# create password for encrypted private keys
ca/private/%-ca.pwd: ca/db/%-ca.dat
	@/usr/bin/openssl rand -base64 64 > $@

# create ca db file and structure
ca/db/%-ca.dat ca/db/%-ca.txt:
	@test -f $@ || bin/prepare --ca $*

# test all targets
.PHONY: test
test:
	$(MAKE) force-destroy 1>/dev/null
	CAK_ALG=ED25519 $(MAKE) init 1>/dev/null
	CPK_ALG=ED25519 $(MAKE) server CN=test.example.com SAN=DNS:www.example.com 1>/dev/null
	CPK_ALG=ED25519 $(MAKE) fritzbox 1>/dev/null
	CPK_ALG=ED25519 $(MAKE) revoke-component CN=test.example.com 1>/dev/null
	CPK_ALG=ED25519 $(MAKE) smime CN="test user" EMAIL="test@example.com" 1>/dev/null

# catch all unkown targets and inform
# %:
# 	@echo "INFO: omitting unknown target:\t%s\n" $@ 1>&2
# 	@:
