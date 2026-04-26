# repo: jomrr/make-ca
# file: Makefile

# =============================================================================
# Makefile for operating an OpenSSL certificate authority
# =============================================================================

MAKEFLAGS += --no-builtin-rules
MAKEFLAGS += --warn-undefined-variables

# Parallel execution is unsafe for OpenSSL CA database operations.
.NOTPARALLEL:

SHELL := /bin/bash
.SHELLFLAGS := -euo pipefail -c

.DEFAULT_GOAL := help

OPENSSL := /usr/bin/openssl

# Runtime state directories removed by destructive cleanup targets.
DESTROY := archive/ ca/ dist/ pub/

# -----------------------------------------------------------------------------
# Project settings and generated target lists
# -----------------------------------------------------------------------------

include settings.mk

# Timestamp used for archive file names.
DATETIME := $(shell date +%Y-%m-%dT%H:%M:%S%z)

# Static certificate request configuration files.
CONFIGS := $(sort $(wildcard etc/*/*/*.cnf))
CERT_SPECS := $(patsubst etc/%.cnf,%,$(CONFIGS))

# Explicit targets are kept for shell and make completion.
CERTS := $(addprefix certs/,$(CERT_SPECS))
P12S := $(addprefix p12/,$(CERT_SPECS))
RENEWS := $(addprefix renew/,$(CERT_SPECS))
REVOKES := $(addprefix revoke/,$(CERT_SPECS))

# -----------------------------------------------------------------------------
# Internal helper functions
# -----------------------------------------------------------------------------

emp :=
spc := $(emp) $(emp)

# stem part
prt = $(word $(1),$(subst /,$(spc),$*))
# stem ca
sca = $(call prt,1)
# stem cert type
sct = $(call prt,2)
# stem id
sid = $(call prt,3)
# stem archive
arc = $(subst /,-,$*)

# -----------------------------------------------------------------------------
# Special make behavior
# -----------------------------------------------------------------------------

# Generated dist artifacts are persistent build outputs, not intermediates.
.NOTINTERMEDIATE: \
	dist/%/ \
	dist/%/bundle.p12 \
	dist/%/certificate.der \
	dist/%/certificate.pem \
	dist/%/certificate.txt \
	dist/%/fullchain.pem \
	dist/%/private.key \
	dist/%/private.pwd \
	dist/%/request.csr

# CA state and public CA artifacts must not be deleted by make.
.PRECIOUS: \
	ca/certs/%.pem \
	ca/db/%.crlnumber \
	ca/db/%.serial \
	ca/db/%.txt \
	ca/db/%.txt.attr \
	ca/private/%.key \
	ca/private/%.pwd \
	ca/reqs/%.csr \
	etc/%.cnf \
	pub/%.der \
	pub/%.pem \
	pub/%.txt \
	pub/%-chain.der \
	pub/%-chain.pem

# =============================================================================
# User-facing targets
# =============================================================================

.PHONY: help
help:
	@printf '%s\n' "Usage: make [target] [CPK_ALG=algorithm]"
	@printf '%s\n' "       make certs/*   Create certs from static config"
	@printf '%s\n' "       make p12/*     Create PKCS#12 bundles"
	@printf '%s\n' "       make renew/*   Renew certs from static config"
	@printf '%s\n\n' "       make revoke/*  Revoke certs"
	@printf '%s\n' "Static config path: etc/<CA>/<CERT_TYPE>/<ID>.cnf"
	@printf '%s\n' "Default values are defined in settings.mk"

.PHONY: all
all: init

# Delete derived export artifacts while keeping keys, CSRs, and certificates.
.PHONY: clean
clean:
	@test ! -d dist || find dist -type f \
		\( -name bundle.p12 \
		-o -name certificate.der \
		-o -name certificate.txt \
		-o -name fullchain.pem \) -delete

# Delete generated end-entity certificate artifacts.
.PHONY: distclean
distclean:
	@rm -rf dist/

# Delete runtime state directories with interactive confirmation.
.PHONY: destroy
destroy:
	@rm -Ir $(DESTROY)

# Delete runtime state directories without confirmation.
.PHONY: force-destroy mrproper
force-destroy mrproper:
	@rm -rf $(DESTROY)

# Initialize all configured CAs and generate CRLs when required.
.PHONY: init crls
init crls: $(foreach ca,$(ALL_CA),pub/$(ca).crl)

# Print CA database records in compact format.
.PHONY: print
print:
	@bin/print ca/db

# Print CA database records with full serials and subjects.
.PHONY: print-full
print-full:
	@bin/print --full ca/db

# =============================================================================
# Public CA artifacts and revocation lists
# =============================================================================

# Generate a DER encoded CRL for a CA.
pub/%.crl: pub/%-chain.der ca/db/%.txt | ca/db/%.crlnumber pub/
	@$(OPENSSL) ca -gencrl -config etc/$*.cnf \
		-passin file:ca/private/$*.pwd \
		-out pub/$*.crl.pem
	@$(OPENSSL) crl -in pub/$*.crl.pem -out $@ -outform DER

# Export a PEM chain as DER for systems that require DER CA artifacts.
pub/%-chain.der: pub/%-chain.pem | pub/
	@$(OPENSSL) x509 -in $< -out $@ -outform DER

# Create the root CA chain.
pub/root-ca-chain.pem: pub/%-chain.pem: pub/%.txt | pub/
	@cat pub/root-ca.pem > $@

# Create the intermediate CA chain.
pub/intermediate-ca-chain.pem: pub/%-chain.pem: pub/%.pem pub/%.txt | pub/
	@cat $< pub/root-ca.pem > $@

# Create the issuing CA chain.
pub/%-chain.pem: pub/%.pem pub/%.txt | pub/
	@cat $< pub/intermediate-ca.pem pub/root-ca.pem > $@

# Export a CA certificate in text format.
pub/%.txt: pub/%.der | pub/
	@$(OPENSSL) x509 -in $< -text -noout > $@

# Export a CA certificate in DER format.
pub/%.der: pub/%.pem | pub/
	@$(OPENSSL) x509 -in $< -out $@ -outform DER

# Export a CA certificate in PEM format.
pub/%.pem: ca/certs/%.pem | pub/
	@$(OPENSSL) x509 -in $< -out $@ -outform PEM

# =============================================================================
# CA certificate hierarchy
# =============================================================================

# Generate the self-signed root CA certificate.
ca/certs/root-ca.pem: ca/certs/%.pem: ca/reqs/%.csr \
	| ca/db/%.txt ca/certs/ ca/new/
	@$(OPENSSL) ca -batch -notext -create_serial \
		-config etc/$*.cnf \
		-passin file:ca/private/$*.pwd \
		-selfsign \
		-in $< \
		-out $@

# Generate the intermediate CA certificate signed by the root CA.
ca/certs/intermediate-ca.pem: ca/certs/%.pem: ca/reqs/%.csr \
	ca/certs/root-ca.pem \
	| ca/db/%.txt ca/certs/ ca/new/
	@$(OPENSSL) ca -batch -notext -create_serial \
		-config etc/root-ca.cnf \
		-keyfile ca/private/root-ca.key \
		-passin file:ca/private/root-ca.pwd \
		-in $< \
		-out $@

# Generate issuing CA certificates signed by the intermediate CA.
ca/certs/%.pem: ca/reqs/%.csr ca/certs/intermediate-ca.pem \
	| ca/db/%.txt ca/certs/ ca/new/
	@$(OPENSSL) ca -batch -notext -create_serial \
		-config etc/intermediate-ca.cnf \
		-keyfile ca/private/intermediate-ca.key \
		-passin file:ca/private/intermediate-ca.pwd \
		-in $< \
		-out $@

# Create a CA certificate signing request.
ca/reqs/%.csr: ca/private/%.key ca/private/%.pwd etc/%.cnf | ca/reqs/
	@$(OPENSSL) req -batch -new \
		-config etc/$*.cnf \
		-key $< \
		-passin file:ca/private/$*.pwd \
		-out $@ \
		-outform PEM

# Create an encrypted CA private key.
ca/private/%.key: | ca/private/%.pwd
	@umask 077; $(OPENSSL) genpkey \
		-out $@ \
		-algorithm $(CAK_ALG) \
		-aes256 \
		-pass file:ca/private/$*.pwd
	@chmod 600 $@

# Create a CRL number file.
ca/db/%.crlnumber: | ca/db/
	@install -m 600 /dev/null $@
	@echo 01 > $@

# Create an OpenSSL CA database file.
ca/db/%.txt: | ca/db/%.txt.attr
	@install -m 600 /dev/null $@

# Create OpenSSL CA database attributes.
ca/db/%.txt.attr: | ca/db/
	@install -m 600 /dev/null $@
	@echo "unique_subject = no" > $@

# Create a password file for encrypted CA private keys.
ca/private/%.pwd: | ca/private/
	@umask 077; $(OPENSSL) rand -hex 64 > $@
	@chmod 600 $@

# =============================================================================
# Directory targets
# =============================================================================

ca/ ca/certs/ pub/:
	@install -d -m 755 $@

ca/db/ ca/new/ ca/private/ ca/reqs/: | ca/
	@install -d -m 700 $@

archive/ dist/:
	@install -d -m 700 $@

dist/%/: | dist/
	@install -d -m 700 $@

# =============================================================================
# Test targets
# =============================================================================

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
	$(MAKE) revoke/component-ca/server/fritzbox 1>/dev/null
	$(MAKE) crls 1>/dev/null
	$(MAKE) mrproper 1>/dev/null

# =============================================================================
# Dynamic end-entity certificate targets
# =============================================================================

# These rules derive prerequisites from the target stem:
# <CA>/<CERT_TYPE>/<ID>. Second expansion is intentionally limited to this
# final block.
.SECONDEXPANSION:

# Create an end-entity private key.
dist/%/private.key: | dist/%/
	@umask 077; $(OPENSSL) genpkey -out $@ -algorithm $(CPK_ALG)
	@chmod 600 $@

# Create a certificate signing request from key and request config.
dist/%/request.csr: \
	dist/%/private.key \
	etc/$$(sca)/$$(sct)/$$(sid).cnf \
	| dist/%/
	@$(OPENSSL) req -batch -new \
		-config etc/$(sca)/$(sct)/$(sid).cnf \
		-key dist/$*/private.key \
		-out $@ \
		-outform PEM

# Issue an end-entity certificate from the certificate signing request.
dist/%/certificate.pem: \
	dist/%/request.csr \
	etc/$$(sca).cnf \
	ca/certs/$$(sca).pem \
	ca/private/$$(sca).key \
	ca/private/$$(sca).pwd \
	| dist/%/
	@$(OPENSSL) ca -batch -notext -create_serial \
		-config etc/$(sca).cnf \
		-in $< \
		-out $@ \
		-extensions $(sct)_ext \
		-passin file:ca/private/$(sca).pwd

# Create a PKCS#12 bundle with key, certificate, and CA chain.
dist/%/bundle.p12: \
	dist/%/private.key \
	dist/%/certificate.pem \
	pub/$$(sca)-chain.pem \
	| dist/%/
	@umask 077; $(OPENSSL) pkcs12 -export \
		-name "$(sid)" \
		-inkey $< \
		-in dist/$*/certificate.pem \
		-certfile pub/$(sca)-chain.pem \
		-out $@
	@chmod 600 $@

# Create a PEM fullchain with certificate and CA chain.
dist/%/fullchain.pem: \
	dist/%/certificate.pem \
	pub/$$(sca)-chain.pem
	@cat $< pub/$(sca)-chain.pem > $@

# Export the end-entity certificate in DER format.
dist/%/certificate.der: dist/%/certificate.pem
	@$(OPENSSL) x509 -in $< -out $@ -outform DER

# Export the end-entity certificate in text format.
dist/%/certificate.txt: dist/%/certificate.pem
	@$(OPENSSL) x509 -in $< -text -noout > $@

# Build all standard certificate artifacts for a certificate spec.
.PHONY: $(CERTS)
$(CERTS): certs/%: \
	dist/%/request.csr \
	dist/%/certificate.pem \
	dist/%/fullchain.pem \
	dist/%/certificate.der \
	dist/%/certificate.txt
	@echo "CERT: $@"
	@ls -la dist/$*/

# Build the PKCS#12 bundle for a certificate spec.
.PHONY: $(P12S)
$(P12S): p12/%: dist/%/bundle.p12
	@echo "P12: $@"
	@ls -la dist/$*/bundle.p12

# Renew a certificate while keeping the existing private key.
.PHONY: $(RENEWS)
$(RENEWS): renew/%: \
	renew-action/% \
	dist/%/certificate.txt \
	pub/$$(sca).crl
	@echo "RENEW: $@"
	@ls -la dist/$*/

# Revoke a certificate and remove its distribution artifact directory.
.PHONY: $(REVOKES)
$(REVOKES): revoke/%: revoke-action/% pub/$$(sca).crl
	@echo "REVOKE: $@"
	@ls -la archive/$(arc).* 2>/dev/null

# Revoke the old certificate and remove generated artifacts before renewal.
renew-action/%: archive/%
	@$(OPENSSL) ca -batch \
		-config etc/$(sca).cnf \
		-revoke dist/$*/certificate.pem \
		-passin file:ca/private/$(sca).pwd \
		-crl_reason superseded
	@rm -f dist/$*/*.{csr,der,pem,p12,txt}

# Revoke the current certificate and remove generated artifacts.
revoke-action/%: archive/%
	@$(OPENSSL) ca -batch \
		-config etc/$(sca).cnf \
		-revoke dist/$*/certificate.pem \
		-passin file:ca/private/$(sca).pwd \
		-crl_reason $(REASON)
	@rm -rf dist/$*/

# Archive distribution artifacts if they are available.
archive/%: | archive/
	@test ! -d dist/$*/ || \
	tar -czvf "archive/$(arc).$(DATETIME).tar.gz" dist/$*/
