# Makefile for operating a certificate authority

# ******************************************************************************
# configuration variables
# ******************************************************************************
SHELL			:= bash
OPENSSL			:= /usr/bin/openssl

# ca default settings
include			settings.mk

# list of signing CAs, signed by intermediate
SIGNING_CA		:= component identity
ALL_CA			:= root intermediate $(SIGNING_CA)

# certificate settings
FILENAME		?= $(if $(EMAIL),$(EMAIL),$(CN))

# ******************************************************************************
# ca functions
# ******************************************************************************

# archive files by CN
define archive
	$(eval APATH := ca/archive/$(1)-$(shell date +%Y-%m-%dT%H:%M:%S%z).tar.gz) \
	tar -czvf $(APATH) \
		$(shell find dist -type f -regextype posix-extended \
		-regex ".*/$(1)\.[^\.]+$$") 2>&1 1>/dev/null && \
	echo "$(APATH) created for CN=$(1)."
endef

# delete files by CN
define delete
	find dist -type f -regextype posix-extended \
		-regex ".*/$(1)\.[^\.]+" -exec rm -f {} +
endef

# revoke a certificate by CN, CA and REASON
define revoke
	/usr/bin/openssl ca -batch \
		-config etc/$(2)-ca.cnf \
		-revoke dist/$(1).crt \
		-passin file:ca/private/$(2)-ca.pwd \
		-crl_reason $(3);
endef

# ******************************************************************************
# make settings
# ******************************************************************************

# keep these files
.PRECIOUS: \
	ca/certs/%-ca.crt \
	ca/db/%-ca.txt \
	ca/db/%-ca.txt.attr \
	ca/private/%-ca.key \
	ca/private/%-ca.pwd \
	ca/reqs/%-ca.csr \
	etc/%.cnf \
	dist/%.csr \
	dist/%.crt \
	dist/%.key \
	dist/%.p12 \
	dist/%.pem \
	pub/%-ca.cer \
	pub/%-ca.pem \
	pub/%-ca-chain.p7c \
	pub/%-ca-chain.pem

# ******************************************************************************
# make targets start here
# ******************************************************************************
#
# help and usage
# ==============================================================================

.PHONY: help
help:
	@bin/$@

# ==============================================================================
# targets for operating the CAs
# ==============================================================================

# --- create CSR and KEY, config is selected by calling target -----------------
dist/%.csr:
	@/usr/bin/openssl req \
		-new \
		-newkey $(CPK_ALG) \
		-config etc/$(MAKECMDGOALS).cnf \
		-keyout dist/$*.key -out $@ -outform PEM

# --- issue CRT by CA ----------------------------------------------------------
dist/%.crt: dist/%.csr
	@echo CA=$(CA)
	@/usr/bin/openssl ca \
		-batch \
		-notext \
		-create_serial \
		-config etc/$(CA)-ca.cnf \
		-in $< \
		-out $@ \
		-extensions $(MAKECMDGOALS)_ext \
		-passin file:ca/private/$(CA)-ca.pwd

# --- create pkcs12 bundle with key, crt and ca-chain --------------------------
dist/%.p12: dist/%.crt
	@/usr/bin/openssl pkcs12 \
		-export \
		-name "$*" \
		-inkey dist/$*.key \
		-in $< \
    	-certfile pub/$(CA)-ca-chain.pem \
		-out $@

# --- create pem bundle with crt and ca-chain -----------------------------
dist/%.pem: dist/%.crt
	@cat dist/$*.crt pub/$(CA)-ca-chain.pem > $@

# --- create tls client certificate --------------------------------------------
.PHONY: client
client: CA=component
client: CPK_ALG=RSA:4096
client: dist/$(FILENAME).p12

# --- create tls certificate for fritzbox --------------------------------------
.PHONY: fritzbox
fritzbox: CA=component
fritzbox: dist/$(FRITZBOX_PUBLIC).myfritz.net.pem

# --- generate CRLs for all CAs ------------------------------------------------
.PHONY: gencrls
gencrls: $(foreach ca,$(ALL_CA),pub/$(ca)-ca.crl)

# --- print CA db files with CA name for grepping serials, revoked, etc. -------
.PHONY: print
print:
	@find ca/db/ -type f -name "*.txt" -exec grep -H ^ {} + | \
		sed 's/.*\/\(.*\)\.txt:\(.*\)\/C=.*CN=\(.*\)/\2CN="\3" \1/' | \
		tr '\t' ' ' | sort

# --- revoke CRT by Component CA and rebuild its CRL ---------------------------
.PHONY: rev-component
rev-component: CA=component
rev-component:
	@$(call archive,$(FILENAME))
	@$(call revoke,$(FILENAME),$(CA),$(if $(REASON),$(REASON),superseded))
	@$(call delete,$(FILENAME))
	@$(MAKE) pub/$(CA)-ca.crl

# --- revoke CRT by Identity CA and rebuild its CRL ----------------------------
.PHONY: rev-identity
rev-identity: CA=identity
rev-identity:
	@$(call archive,$(FILENAME))
	@$(call revoke,$(FILENAME),$(CA),$(if $(REASON),$(REASON),superseded))
	@$(call delete,$(FILENAME))
	@$(MAKE) pub/$(CA)-ca.crl

# --- create tls server certificate --------------------------------------------
.PHONY: server
server: CA=component
server: dist/$(FILENAME).pem

# --- create certificate with smime extensions ---------------------------------
.PHONY: smime
smime: CA=identity
smime: dist/$(FILENAME).pem

# ==============================================================================
# targets for initializing or destroying the CAs
# ==============================================================================

# delete CSRs
.PHONY: clean
clean:
	@rm dist/$(FILENAME).csr

# delete KEYs and CERTs
.PHONY: distclean
distclean: clean
	@rm dist/$(FILENAME).{crt,key,pem,p12}

# delete everything but make and the config dir
.PHONY: destroy
destroy:
	@rm -Ir ./ca/ ./dist/ ./pub/

# init all CAs and generate initial CRLs
.PHONY: init
init: $(SIGNING_CA)
	@$(MAKE) gencrls

# init root ca
.PHONY: root
root: %: ca/db/%-ca.txt.attr pub/%-ca.cer

# init intermediate ca, depends on root ca, so root will run if necessary
.PHONY: intermediate
intermediate: %: root \
	ca/db/%-ca.txt.attr \
	pub/%-ca.cer \
	pub/%-ca-chain.p7c

# init signing CAs, depends on intermediate and implicitly on root
.PHONY: $(SIGNING_CA)
$(SIGNING_CA): %: intermediate \
	ca/db/%-ca.txt.attr \
	pub/%-ca.cer \
	pub/%-ca-chain.p7c

# issue ca certificate
ca/certs/%-ca.crt: ca/reqs/%-ca.csr
	@bin/ca-crt --ca $*

# when ca db is newer than crl, we create it
ca/db/%-ca.txt:

# create ca filesystem structure
ca/db/%-ca.txt.attr:
	@bin/prepare --ca $*

# create ca certificate signing request
ca/reqs/%-ca.csr: ca/private/%-ca.key
	@/usr/bin/openssl req \
		-batch  \
		-new \
		-config etc/$*-ca.cnf \
		-out $@ -outform PEM \
		-key $< -passin file:$(patsubst %.key,%.pwd,$<)

# create ca private key
ca/private/%-ca.key: ca/private/%-ca.pwd
	@/usr/bin/openssl genpkey \
		-out $@ \
		-algorithm $(CAK_ALG) \
		-aes256 -pass file:$<

# create password for encrypted private keys
ca/private/%-ca.pwd:
	@/usr/bin/openssl rand -base64 64 > $@

# create DER export of ca certificate
pub/%-ca.cer: pub/%-ca.pem
	@/usr/bin/openssl x509 \
		-in pub/$*-ca.pem \
		-out pub/$*-ca.cer \
		-outform DER

# create crl for ca and run when ca db is newer than crl
pub/%-ca.crl: ca/db/%-ca.txt
	@bin/crl --ca $*

# export ca certificate in PEM format. it already should be.
pub/%-ca.pem: ca/certs/%-ca.crt
	@/usr/bin/openssl x509 \
		-in ca/certs/$*-ca.crt \
		-out pub/$*-ca.pem \
		-outform PEM

# create PKCS7 certificate chain for ca
pub/%-ca-chain.p7c: pub/%-ca-chain.pem
	@bin/chain --ca $* --format p7c

# create PEM certificate chain for ca
pub/%-ca-chain.pem: pub/%-ca.pem
	@bin/chain --ca $* --format pem

# ==============================================================================
# general purpose targets
# ==============================================================================

force-destroy:
	@rm -rf ./ca/ ./dist/ ./pub/

.PHONY: test
test:
	$(MAKE) force-destroy
	CAK_ALG=ED25519 $(MAKE) init
	CPK_ALG=ED25519 $(MAKE) server CN=test.example.com SAN=DNS:www.example.com
	CPK_ALG=ED25519 $(MAKE) fritzbox
	CPK_ALG=ED25519 $(MAKE) rev-component CN=test.example.com
	CPK_ALG=ED25519 $(MAKE) smime CN="test user" EMAIL="test@example.com"

# catch all unkown targets and inform
# %:
# 	@echo "INFO: omitting unknown target:\t%s\n" $@ 1>&2
# 	@:
