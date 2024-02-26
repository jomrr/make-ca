# Makefile for operating a certificate authority

# ******************************************************************************
# configuration variables
# ******************************************************************************
SHELL			:= bash
OPENSSL			:= /usr/bin/openssl
OPENSSL_GEN_CA	:= $(OPENSSL) ca -batch -notext -create_serial

# ca default settings
include			settings.mk

# ca base directory
CA_DIR			:= ca
# archive directory
ARCDIR			:= $(CA_DIR)/archive
# certificate distribution directory for CRTs
CRTDIR			:= dist
# directory for openssl configuration files
CNFDIR			:= etc
# static configuration directory
STCDIR			:= $(CNFDIR)/static
# webroot, where CRLs, chains, etc. are placed
WEBDIR			:= www

# list of signing CAs, signed by intermediate
SIGNING_CA		:= component identity
ALL_CA			:= root intermediate $(SIGNING_CA)

# certificate settings
FILENAME		?= $(if $(EMAIL),$(EMAIL),$(CN))

# ******************************************************************************
# ca functions
# ******************************************************************************

# create root ca
define gen_root_ca
	$(OPENSSL_GEN_CA) \
		-config $(CNFDIR)/$(1)-ca.cnf \
		-in $(2) -out $(3) \
		-extensions $(1)_ca_ext \
		-passin file:$(CA_DIR)/private/$(1)-ca.pwd \
		-selfsign;
endef

# create intermediate ca
define gen_intermediate_ca
	$(OPENSSL_GEN_CA) \
		-config $(CNFDIR)/root-ca.cnf \
		-in $(2) -out $(3) \
		-extensions $(1)_ca_ext \
		-passin file:$(CA_DIR)/private/root-ca.pwd \
		-keyfile $(CA_DIR)/private/root-ca.key;
endef

# create signing ca
define gen_signing_ca
	$(OPENSSL_GEN_CA) \
		-config $(CNFDIR)/intermediate-ca.cnf \
		-in $(2) -out $(3) \
		-extensions signing_ca_ext \
		-passin file:$(CA_DIR)/private/intermediate-ca.pwd \
		-keyfile $(CA_DIR)/private/intermediate-ca.key;
endef

# function to create root, intermediate and signing ca(s)
define gen_ca
	if [ $(1) = root ]; then \
		$(call gen_root_ca,$(1),$(2),$(3)) \
	elif [ $(1) = intermediate ]; then \
		$(call gen_intermediate_ca,$(1),$(2),$(3)) \
	else \
		$(call gen_signing_ca,$(1),$(2),$(3)) \
	fi
endef

# archive files by CN
define archive
	$(eval APATH := $(ARCDIR)/$(1)-$(shell date +%Y-%m-%dT%H:%M:%S%z).tar.gz) \
	tar -czvf $(APATH) \
		$(shell find $(CRTDIR) -type f -regextype posix-extended \
		-regex ".*/$(1)\.[^\.]+$$") 2>&1 1>/dev/null && \
	echo "$(APATH) created for CN=$(1)."
endef

# delete files by CN
define delete
	find $(CRTDIR) -type f -regextype posix-extended \
		-regex ".*/$(1)\.[^\.]+" -exec rm -f {} +
endef

# revoke a certificate by CN, CA and REASON
define revoke
	$(OPENSSL) ca -batch \
		-config $(CNFDIR)/$(2)-ca.cnf \
		-revoke $(CRTDIR)/$(1).crt \
		-passin file:$(CA_DIR)/private/$(2)-ca.pwd \
		-crl_reason $(3);
endef

# ******************************************************************************
# make settings
# ******************************************************************************

# keep these files
.PRECIOUS: \
	$(CA_DIR)/certs/%-ca.crt \
	$(CA_DIR)/db/%-ca.txt \
	$(CA_DIR)/db/%-ca.txt.attr \
	$(CA_DIR)/private/%-ca.key \
	$(CA_DIR)/private/%.pwd \
	$(CA_DIR)/reqs/%-ca.csr \
	$(CNFDIR)/%.cnf \
	$(CRTDIR)/%.csr \
	$(CRTDIR)/%.crt \
	$(CRTDIR)/%.key \
	$(CRTDIR)/%.p12 \
	$(CRTDIR)/%.pem \
	$(WEBDIR)/%-ca.cer \
	$(WEBDIR)/%-ca.pem \
	$(WEBDIR)/%-ca-chain.p7c \
	$(WEBDIR)/%-ca-chain.pem

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
$(CRTDIR)/%.csr:
	@$(OPENSSL) req \
		-new \
		-newkey $(KEY_ALG) \
		-config $(CNFDIR)/$(MAKECMDGOALS).cnf \
		-keyout $(CRTDIR)/$*.key -out $@ -outform PEM

# --- issue CRT by CA ----------------------------------------------------------
$(CRTDIR)/%.crt: $(CRTDIR)/%.csr
	@echo CA=$(CA)
	@$(OPENSSL) ca \
		-batch \
		-notext \
		-create_serial \
		-config $(CNFDIR)/$(CA)-ca.cnf \
		-in $< \
		-out $@ \
		-extensions $(MAKECMDGOALS)_ext \
		-passin file:$(CA_DIR)/private/$(CA)-ca.pwd

# --- create pkcs12 bundle with key, crt and ca-chain --------------------------
$(CRTDIR)/%.p12: $(CRTDIR)/%.crt
	@$(OPENSSL) pkcs12 \
		-export \
		-name "$*" \
		-inkey $(CRTDIR)/$*.key \
		-in $< \
    	-certfile $(WEBDIR)/$(CA)-ca-chain.pem \
		-out $@

# --- create pem bundle with crt and ca-chain -----------------------------
$(CRTDIR)/%.pem: $(CRTDIR)/%.crt
	@cat $(CRTDIR)/$*.crt $(WEBDIR)/$(CA)-ca-chain.pem > $@

# --- create tls client certificate --------------------------------------------
.PHONY: client
client: CA=component
client: KEY_ALG=RSA:4096
client: $(CRTDIR)/$(FILENAME).p12

# --- create tls certificate for fritzbox --------------------------------------
.PHONY: fritzbox
fritzbox: CA=component
fritzbox: $(CRTDIR)/$(FRITZBOX_PUBLIC).myfritz.net.pem

# --- generate CRLs for all CAs ------------------------------------------------
.PHONY: gencrls
gencrls: $(foreach ca,$(ALL_CA),$(WEBDIR)/$(ca)-ca.crl)

# --- print CA db files with CA name for grepping serials, revoked, etc. -------
.PHONY: print
print:
	@find $(CA_DIR)/db/ -type f -name "*.txt" -exec grep -H ^ {} + | \
		sed 's/.*\/\(.*\)\.txt:\(.*\)\/C=.*CN=\(.*\)/\2CN="\3" \1/' | \
		tr '\t' ' ' | sort

# --- revoke CRT by Component CA and rebuild its CRL ---------------------------
.PHONY: rev-component
rev-component: CA=component
rev-component:
	@$(call archive,$(FILENAME))
	@$(call revoke,$(FILENAME),$(CA),$(if $(REASON),$(REASON),superseded))
	@$(call delete,$(FILENAME))
	@$(MAKE) $(WEBDIR)/$(CA)-ca.crl

# --- revoke CRT by Identity CA and rebuild its CRL ----------------------------
.PHONY: rev-identity
rev-identity: CA=identity
rev-identity:
	@$(call archive,$(FILENAME))
	@$(call revoke,$(FILENAME),$(CA),$(if $(REASON),$(REASON),superseded))
	@$(call delete,$(FILENAME))
	@$(MAKE) $(WEBDIR)/$(CA)-ca.crl

# --- create tls server certificate --------------------------------------------
.PHONY: server
server: CA=component
server: $(CRTDIR)/$(FILENAME).pem

# --- create certificate with smime extensions ---------------------------------
smime: CA=identity
.PHONY: smime
smime: CA=identity
smime: $(CRTDIR)/$(FILENAME).pem

# --- create certificates for static configurations ----------------------------
.PHONY: static
static:
	@echo $(SERVERS)

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
	@rm -Ir ./$(CA_DIR)/ ./$(CRTDIR)/ ./$(WEBDIR)/

# init all CAs and generate initial CRLs
.PHONY: init
init: $(SIGNING_CA)
	@$(MAKE) gencrls

# init root ca
.PHONY: root
root: %: $(CA_DIR)/db/%-ca.txt.attr $(WEBDIR)/%-ca.cer

# init intermediate ca, depends on root ca, so root will run if necessary
.PHONY: intermediate
intermediate: %: root \
	$(CA_DIR)/db/%-ca.txt.attr \
	$(WEBDIR)/%-ca.cer \
	$(WEBDIR)/%-ca-chain.p7c

# init signing CAs, depends on intermediate and implicitly on root
.PHONY: $(SIGNING_CA)
$(SIGNING_CA): %: intermediate \
	$(CA_DIR)/db/%-ca.txt.attr \
	$(WEBDIR)/%-ca.cer \
	$(WEBDIR)/%-ca-chain.p7c

# issue ca certificate
$(CA_DIR)/certs/%-ca.crt: $(CA_DIR)/reqs/%-ca.csr
	@$(call gen_ca,$*,$<,$@)

# when ca db is newer than crl, we create it
$(CA_DIR)/db/%-ca.txt:

# create ca filesystem structure
$(CA_DIR)/db/%-ca.txt.attr:
	@bin/prepare --ca $* --dir $(CA_DIR)

# create ca certificate signing request
$(CA_DIR)/reqs/%-ca.csr: $(CA_DIR)/private/%-ca.key
	@$(OPENSSL) req \
		-batch  \
		-new \
		-config $(CNFDIR)/$*-ca.cnf \
		-out $@ -outform PEM \
		-key $< -passin file:$(patsubst %.key,%.pwd,$<)

# create ca private key
$(CA_DIR)/private/%-ca.key: $(CA_DIR)/private/%-ca.pwd
	@$(OPENSSL) genpkey \
		-out $@ \
		-algorithm $(CAK_ALG) \
		-aes256 -pass file:$<

# create password for encrypted private keys
$(CA_DIR)/private/%.pwd:
	@$(OPENSSL) rand -base64 32 > $@

# create DER export of ca certificate
$(WEBDIR)/%-ca.cer: $(WEBDIR)/%-ca.pem
	@$(OPENSSL) x509 \
		-in $(WEBDIR)/$*-ca.pem \
		-out $(WEBDIR)/$*-ca.cer \
		-outform DER

# create crl for ca and run when ca db is newer than crl
$(WEBDIR)/%-ca.crl: $(CA_DIR)/db/%-ca.txt
	@bin/crl \
		--config $(CNFDIR)/$*-ca.cnf \
		--passin file:$(CA_DIR)/private/$*-ca.pwd \
		--out $@

# export ca certificate in PEM format. it already should be.
$(WEBDIR)/%-ca.pem: $(CA_DIR)/certs/%-ca.crt
	@$(OPENSSL) x509 \
		-in $(CA_DIR)/certs/$*-ca.crt \
		-out $(WEBDIR)/$*-ca.pem \
		-outform PEM

# create PKCS7 certificate chain for ca
$(WEBDIR)/%-ca-chain.p7c: $(WEBDIR)/%-ca-chain.pem
	@bin/chain --ca $* --dir $(WEBDIR) --format p7c

# create PEM certificate chain for ca
$(WEBDIR)/%-ca-chain.pem: $(WEBDIR)/%-ca.pem
	@bin/chain --ca $* --dir $(WEBDIR) --format pem

# ==============================================================================
# general purpose targets
# ==============================================================================

force-destroy:
	@rm -rf ./$(CA_DIR)/ ./$(CRTDIR)/ ./$(WEBDIR)/

.PHONY: test
test:
	$(MAKE) force-destroy
	CAK_ALG=ED25519 $(MAKE) init
	KEY_ALG=ED25519 $(MAKE) server CN=test.example.com SAN=DNS:test.example.com,DNS:www.example.com
	KEY_ALG=ED25519 $(MAKE) fritzbox
	KEY_ALG=ED25519 $(MAKE) rev-component CN=test.example.com
	KEY_ALG=ED25519 $(MAKE) smime CN="test user" EMAIL="test@example.com"

# catch all unkown targets and inform
# %:
# 	@echo "INFO: omitting unknown target:\t%s\n" $@ 1>&2
# 	@:
