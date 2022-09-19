# Makefile for operating a certificate authority

# ******************************************************************************
# configuration variables
# ******************************************************************************
SHELL			:= /usr/bin/env bash
OPENSSL			:= /usr/bin/openssl

# CA Keys: param for openssl genpkey -algorithm $(CAK_ALG)
#CAK_ALG			?= ED25519
CAK_ALG			?= RSA -pkeyopt rsa_keygen_bits:8192

# CRT Keys: param for openssl req -newkey $(KEY_ALG)
# NOTE: ED25519 p12 client certificates fail to import with Firefox 97.0
KEY_ALG			?= ED25519
#KEY_ALG			?= RSA:4096

# ca base directory
CA_DIR			:= ca
# certificate distribution directory for CRTs
CRTDIR			:= dist
# directory for openssl configuration files
CNFDIR			:= etc
# webroot, where CRLs, chains, etc. are placed
WEBDIR			:= www

# list of signing CAs, signed by intermediate
SIGNING_CA		:= component identity
ALL_CA			:= root intermediate $(SIGNING_CA)

ALL_CA_CONFIGS	:= $(wildcard $(CNFDIR)/*-ca.cnf)
PREDEF_CONFIGS	:= $(CNFDIR)/client.cnf $(CNFDIR)/email.cnf
PREDEF_CONFIGS	+= $(CNFDIR)/fritzbox.cnf $(CNFDIR)/identity.cnf
PREDEF_CONFIGS	+= $(CNFDIR)/server.cnf $(CNFDIR)/smartcard.cnf
FILTER_CONFIGS	:= $(ALL_CA_CONFIGS) #$(PREDEF_CONFIGS)
CONFIG_TARGETS	:= $(filter-out $(FILTER_CONFIGS),$(wildcard $(CNFDIR)/*.cnf))

# base URL of pki, where WEBDIR is found, also used as AIA and CDP base
export PKIURL	:= http://pki.mauer.in
# list of CRL Distribution Points in SSH syntax for deploy-crls target (TODO)
CDP				:= cdp1:/var/www/pki

# ******************************************************************************
# functions
# ******************************************************************************

# function to create root, intermediate and signing ca(s)
define gen_ca
	if [ $(1) == root ]; then \
		$(OPENSSL) ca -batch -notext -create_serial \
			-config $(CNFDIR)/$(1)-ca.cnf \
			-in $(2) -out $(3) \
			-extensions $(1)_ca_ext \
			-passin file:$(CA_DIR)/private/$(1)-ca.pwd \
			-selfsign; \
	elif [ $(1) == intermediate ]; then \
		$(OPENSSL) ca -batch -notext -create_serial \
			-config $(CNFDIR)/root-ca.cnf \
			-in $(2) -out $(3) \
			-extensions $(1)_ca_ext \
			-passin file:$(CA_DIR)/private/root-ca.pwd \
			-keyfile $(CA_DIR)/private/root-ca.key; \
	else \
		$(OPENSSL) ca -batch -notext -create_serial \
			-config $(CNFDIR)/intermediate-ca.cnf \
			-in $(2) -out $(3) -extensions signing_ca_ext \
			-passin file:$(CA_DIR)/private/intermediate-ca.pwd \
			-keyfile $(CA_DIR)/private/intermediate-ca.key; \
	fi
endef

# generate pem certificate chain
define gen_ca_chain
	if [ $(1) == root ]; then \
		echo "Nothing to chain for root-ca ;)"; \
	elif [ $(1) == intermediate ]; then \
		cat $(WEBDIR)/$(1)-ca.pem $(WEBDIR)/root-ca.pem \
			> $(WEBDIR)/$(1)-ca-chain.pem; \
	else \
		cat $(WEBDIR)/$(1)-ca.pem \
		$(WEBDIR)/intermediate-ca.pem $(WEBDIR)/root-ca.pem \
			> $(WEBDIR)/$(1)-ca-chain.pem; \
	fi
endef

# ******************************************************************************
# make settings
# ******************************************************************************

# keep these files
.PRECIOUS: \
	$(CA_DIR)/certs/%-ca.crt \
	$(CA_DIR)/db/%.db \
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

# ==============================================================================
# help and usage
# ==============================================================================

.PHONY: help
help:
	@echo "Help!"

# ==============================================================================
# targets for operating the CAs
# ==============================================================================

# --- create CRT from existing static configuration file without prompting -----
.PHONY: $(CONFIG_TARGETS)
$(CONFIG_TARGETS):
# TODO

# --- create CSR and KEY, config is selected by calling target -----------------
$(CRTDIR)/%.csr:
	@$(OPENSSL) req -new -newkey $(KEY_ALG) \
		-config $(CNFDIR)/$(MAKECMDGOALS).cnf \
		-keyout $(CRTDIR)/$*.key -out $@ -outform PEM

# --- issue CRT by CA ----------------------------------------------------------
$(CRTDIR)/%.crt: $(CRTDIR)/%.csr
	@$(OPENSSL) ca -batch -notext -create_serial \
		-config $(CNFDIR)/$(CA)-ca.cnf \
		-in $< \
		-out $@ \
		-extensions $(MAKECMDGOALS)_ext \
		-passin file:$(CA_DIR)/private/$(CA)-ca.pwd

# --- create pkcs12 bundle with key, crt and ca-chain --------------------------
$(CRTDIR)/%.p12: $(CRTDIR)/%.crt
	@$(OPENSSL) pkcs12 -export \
		-name "$*" \
		-inkey $(CRTDIR)/$*.key \
		-in $< \
    	-certfile $(WEBDIR)/$(CA)-ca-chain.pem \
		-out $@

# --- create pem bundle with key, crt and ca-chain -----------------------------
$(CRTDIR)/%.pem: $(CRTDIR)/%.crt
	@cat $(CRTDIR)/$*.key $(CRTDIR)/$*.crt $(WEBDIR)/$(CA)-ca-chain.pem > $@

# --- create tls client certificate --------------------------------------------
.PHONY: client
client: $(eval CA=component KEY_ALG=RSA:4096) $(CRTDIR)/$(CN).p12

# --- create tls certificate for fritzbox --------------------------------------
.PHONY: fritzbox
fritzbox: $(eval CA=component) $(CRTDIR)/fritz.box.pem

# --- generate CRLs for all CAs ------------------------------------------------
.PHONY: gencrls
gencrls: $(foreach ca,$(ALL_CA),$(WEBDIR)/$(ca)-ca.crl)

# --- factory-reset, configure nitrokey and upload s/mime certificate ----------
.PHONY: nitrokey
nitrokey:
# TODO

# --- create tls server certificate --------------------------------------------
.PHONY: server
server: $(eval CA=component) $(CRTDIR)/$(CN).pem

# --- create s/mime certificate for smartcard ----------------------------------
.PHONY: smartcard
smartcard:
# TODO

# --- print CA db files with CA name for grepping serials, revoked, etc. -------
.PHONY: print
print:
	@find $(CA_DIR)/db/ -type f -name "*.db" -exec grep -H ^ {} + | \
		sed 's/.*\/\(.*\)\.db:\(.*\)\/C=.*CN=\(.*\)/\2CN="\3" \1/' | \
		tr '\t' ' ' | sort

# --- invisible target to revoke a certificate by CN= --------------------------
.PHONY: --revoke
--revoke:
	@$(OPENSSL) ca -batch \
		-config $(CNFDIR)/$(CA)-ca.cnf \
		-revoke $(CRTDIR)/$(CN).crt \
		-passin file:$(CA_DIR)/private/$(CA)-ca.pwd \
		-crl_reason $(if $(REASON),$(REASON),superseded)
	@rm -f $(CRTDIR)/$(CN).{crt,p12,pem}

# --- revoke CRT by Component CA and rebuild its CRL ---------------------------
.PHONY: revoke-component
revoke-component: $(eval CA=component) --revoke $(WEBDIR)/$(CA)-ca.crl

# --- revoke CRT by Identity CA and rebuild its CRL ----------------------------
.PHONY: revoke-identity
revoke-identity: $(eval CA=identity) --revoke $(WEBDIR)/$(CA)-ca.crl

# ==============================================================================
# targets for initializing or destroying the CAs
# ==============================================================================

# delete everything but make and the config dir
.PHONY: destroy
destroy:
	@rm -Ir $(CA_DIR)/ $(CRTDIR)/ $(WEBDIR)/

# init all CAs and generate initial CRLs
.PHONY: init
init: $(SIGNING_CA)

# init root ca
.PHONY: root
root: %: $(CA_DIR)/db/%-ca.db $(WEBDIR)/%-ca.cer

# init intermediate ca, depends on root ca, so root will run if necessary
.PHONY: intermediate $(WEBDIR)/root-ca.crl
intermediate: %: root \
	$(CA_DIR)/db/%-ca.db $(WEBDIR)/%-ca.cer $(WEBDIR)/%-ca-chain.p7c

# init signing CAs, depends on intermediate and implicitly on root
.PHONY: $(SIGNING_CA)
$(SIGNING_CA): %: intermediate \
	$(CA_DIR)/db/%-ca.db $(WEBDIR)/%-ca.cer $(WEBDIR)/%-ca-chain.p7c \
	$(WEBDIR)/intermediate-ca.crl

# issue ca certificate
$(CA_DIR)/certs/%-ca.crt: $(CA_DIR)/reqs/%-ca.csr
	@$(call gen_ca,$*,$<,$@)

# create ca filesystem structure
$(CA_DIR)/db/%.db:
	@mkdir -m 755 -p $(CA_DIR)/{certs,reqs} dist www
	@mkdir -m 750 -p $(CA_DIR)/{db,new,private}
	@install -m 640 /dev/null $(CA_DIR)/db/$*.db
	@install -m 640 /dev/null $(CA_DIR)/db/$*.db.attr
	@install -m 640 /dev/null $(CA_DIR)/db/$*.crl.srl
	@echo 01 > $(CA_DIR)/db/$*.crl.srl

# create ca certificate signing request
$(CA_DIR)/reqs/%-ca.csr: $(CA_DIR)/private/%-ca.key
	@$(OPENSSL) req -batch -new \
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

# create crl for ca and force it to run
.PHONY: $(WEBDIR)/%-ca.crl
$(WEBDIR)/%-ca.crl:
	@$(OPENSSL) ca -gencrl \
		-config $(CNFDIR)/$*-ca.cnf \
		-passin file:$(CA_DIR)/private/$*-ca.pwd \
		-out $@.pem
	@$(OPENSSL) crl -noout \
		-in $@.pem \
		-out $@ -outform DER

# export ca certificate in PEM format. it already should be.
$(WEBDIR)/%-ca.pem: $(CA_DIR)/certs/%-ca.crt
	@$(OPENSSL) x509 \
		-in $(CA_DIR)/certs/$*-ca.crt \
		-out $(WEBDIR)/$*-ca.pem -outform PEM

# create PKCS7 certificate chain for ca
$(WEBDIR)/%-ca-chain.p7c: $(WEBDIR)/%-ca-chain.pem
	@$(OPENSSL) crl2pkcs7 -nocrl \
		-certfile $(WEBDIR)/$*-ca-chain.pem \
		-out $(WEBDIR)/$*-ca-chain.p7c -outform DER

# create PEM certificate chain for ca
$(WEBDIR)/%-ca-chain.pem: $(WEBDIR)/%-ca.pem
	@$(call gen_ca_chain,$*)

# ==============================================================================
# general purpose targets
# ==============================================================================

# catch all unkown targets and inform
%:
	@printf "INFO: omitting unknown target:\t%s\n" $@ 1>&2
	@:
