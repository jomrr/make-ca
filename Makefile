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
DATETIME		:= $(shell date +%Y-%m-%dT%H:%M:%S%z)
CONFIG			:= $(shell find etc -mindepth 3 -maxdepth 3 -type f -name "*.cnf")
CERTS			:= $(foreach cfg,$(CONFIG),$(subst .cnf,,$(subst etc/,certs/,$(cfg))))
TARGET 			:= $(firstword $(MAKECMDGOALS))

# Define a helper variable to check each pattern.
HAS_CERTS 		:= $(findstring certs/,$(TARGET))
HAS_RENEW 		:= $(findstring renew/,$(TARGET))
HAS_REVOKE 		:= $(findstring revoke/,$(TARGET))

# Check if first MAKECMDGOALS start with "{certs,renew,revoke}/"
ifneq (,$(or $(HAS_CERTS),$(HAS_REVOKE),$(HAS_RENEW)))

# Convert slashes to spaces to make it easier to extract individual parts
SPACE_REPLACED_TARGET := $(subst /, ,$(TARGET))

# Count the number of components in the TARGET
NUM_COMPONENTS := $(words $(SPACE_REPLACED_TARGET))

# Extract specific parts based on their position and the number of components
CA := $(word 2, $(SPACE_REPLACED_TARGET))

# static configuration
ifeq ($(NUM_COMPONENTS),4)  # Implies format: etc/CA/CERT_TYPE/IDENTIFIER.cnf
    CERT_TYPE := $(word 3, $(SPACE_REPLACED_TARGET))
    IDENTIFIER_RAW := $(word 4, $(SPACE_REPLACED_TARGET))
    IDENTIFIER := $(basename $(IDENTIFIER_RAW))  # Remove the .cnf extension
# template configuration per extension
else ifeq ($(NUM_COMPONENTS),3)  # Implies format: etc/CA/CERT_TYPE.cnf
    CERT_TYPE := $(basename $(word 3, $(SPACE_REPLACED_TARGET)))
    IDENTIFIER_RAW := $(word 3, $(SPACE_REPLACED_TARGET))
    IDENTIFIER := $(CERT_TYPE)  # CERT_TYPE and IDENTIFIER are the same
endif

endif

# delete files by CN
define delete
	find dist -type f -regextype posix-extended \
		-regex ".*/$(1).*\.[^\.]+" -exec rm -f {} +
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
	echo "       make revoke/* [REASON=reason]\n"
	echo "Static conf is provided by etc/<CA>/<CERT_TYPE>/<IDENTIFIER>.cnf"
	echo "Default values are defined in settings.mk"

#create CSR and KEY, config is selected by calling target
dist/%.csr: | dist/
	$(OPENSSL) req -new -newkey $(CPK_ALG) -config etc/$(CA)/$(CERT_TYPE)/$*.cnf -keyout dist/$*.key -out $@ -outform PEM

#issue CRT by CA
dist/%.pem: dist/%.csr
	$(OPENSSL) ca -batch -notext -create_serial -config etc/$(CA).cnf -in $< -out $@ -extensions $(CERT_TYPE)_ext -passin file:ca/private/$(CA).pwd

#create pkcs12 bundle with key, crt and ca-chain
dist/%.p12: dist/%.pem
	$(OPENSSL) pkcs12 -export -name "$*" -inkey dist/$*.key -in $< -certfile pub/$(CA)-chain.pem -out $@

#create pem bundle with crt and ca-chain
dist/%-fullchain.pem: dist/%.pem dist/%.csr
	cat $< pub/$(CA)-chain.pem > $@

dist/%.der: dist/%-fullchain.pem dist/%.pem dist/%.csr
	@$(OPENSSL) x509 -in dist/$*.pem -out $@ -outform DER

dist/%.txt: dist/%.der dist/%-fullchain.pem dist/%.pem dist/%.csr
	@$(OPENSSL) x509 -in dist/$*.pem -text -noout > $@

.PHONY: $(CERTS)
$(CERTS): certs/$(CA)/$(CERT_TYPE)/%: dist/%.txt dist/%.pem dist/%.csr
	@echo "INFO: $@"
	@ls -la dist/$*.*

#create tls client certificate
.PHONY: client
client: CA=component-ca
client: CPK_ALG=RSA:4096
client: dist/$(FILENAME).p12

# print CA db files with CA name for grepping serials, revoked, etc.
.PHONY: print
print:
	for DB in ca/db/*.txt; do \
		BASENAME=$$(basename "$$DB" .txt); \
		CA_SLUG=$$(echo "$$BASENAME"); \
		awk -v filename="$$CA_SLUG" '{ \
			gsub(/[ \t]+/, " "); \
			printf "%s %s\n", filename, $$0; \
		}' "$$DB"; \
	done

# revoke CRT by CA and rebuild its CRL
REVOKE_TARGETS := $(foreach ca,$(ISSUING_CA),revoke-$(ca))

.PHONY: $(REVOKE_TARGETS)
$(REVOKE_TARGETS): revoke-%: $(ARCHPATH)
	$(call revoke,$(FILENAME),$*,$(if $(REASON),$(REASON),superseded))
	$(call delete,$(FILENAME))
	$(MAKE) pub/$*.crl

ca/archive/%.tar.gz: | ca/archive/
	@tar -czvf $@ $(ARCHFILES)

# create tls server certificate
.PHONY: server
server: CA=component-ca
server: dist/$(FILENAME)-fullchain.pem

# create certificate with smime extensions
.PHONY: smime
smime: CA=identity-ca
smime: dist/$(FILENAME).pem

# delete CSRs
.PHONY: clean
clean:
	@rm dist/$(FILENAME).csr

# delete KEYs and CERTs and also CSRs through clean
.PHONY: distclean
distclean: clean
	@rm dist/$(FILENAME).{crt,der,key,pem,p12,txt}

# delete everything but make and the config dir
.PHONY: destroy
destroy:
	@rm -Ir ./ca/ ./dist/ ./pub/

# destroy everything without asking
force-destroy:
	@rm -rf ./ca/ ./dist/ ./pub/

# init all CAs and generate initial CRLs
.PHONY: init crls
init crls: $(foreach ca,$(ALL_CA),pub/$(ca).crl)

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

ca/archive/ ca/db/ ca/new/ ca/private/ ca/reqs/: | ca/
	@mkdir -m 700 -p $@

ca/ ca/certs/ dist/ pub/ dist/$(CA)/$(CERT_TYPE)/:
	@mkdir -m 755 -p $@

# test all targets
.PHONY: test
test:
	$(MAKE) force-destroy 1>/dev/null
	CAK_ALG=ED25519 $(MAKE) init 1>/dev/null
	CPK_ALG=ED25519 $(MAKE) server CN=test.example.com SAN=DNS:www.example.com 1>/dev/null
	CPK_ALG=ED25519 $(MAKE) fritzbox 1>/dev/null
	CPK_ALG=ED25519 $(MAKE) revoke-component-ca CN=test.example.com 1>/dev/null
	CPK_ALG=ED25519 $(MAKE) smime CN="test user" EMAIL="test@example.com" 1>/dev/null

# catch all unkown targets and inform
# %:
# 	echo "INFO: omitting unknown target:\t%s\n" $ 1>&2
# 	:
