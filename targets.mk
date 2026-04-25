# file: targets.mk
#
# ******************************************************************************
# Description: This file contains variables for dynamic targets used to manage
#              dynamic certificate generation, renewal and revocation.
# ******************************************************************************

# Guard against calling multiple operational targets at once.
OP_TARGETS := $(filter certs/% p12/% renew/% revoke/%,$(MAKECMDGOALS))

ifneq ($(words $(OP_TARGETS)),0)
ifneq ($(words $(OP_TARGETS)),1)
$(error Only one operational target is supported per invocation)
endif
endif

# operational settings
DATETIME	:= $(shell date +%Y-%m-%dT%H:%M:%S%z)
# static configuration files
CONFIGS		:= $(sort $(wildcard etc/*/*/*.cnf))
# dynamic targets for p12 bundles
P12S		:= $(foreach cfg,$(CONFIGS),$(subst .cnf,,$(subst etc/,p12/,$(cfg))))
# dynamic targets for certificates
CERTS		:= $(foreach cfg,$(CONFIGS),$(subst .cnf,,$(subst etc/,certs/,$(cfg))))
# dynamic targets for renewals
RENEWS		:= $(foreach cfg,$(CONFIGS),$(subst .cnf,,$(subst etc/,renew/,$(cfg))))
# dynamic targets for revocations
REVOKES		:= $(foreach cfg,$(CONFIGS),$(subst .cnf,,$(subst etc/,revoke/,$(cfg))))
# 
TARGET 		:= $(firstword $(MAKECMDGOALS))

# Define a helper variable to check each pattern.
HAS_CERTS	:= $(filter certs/%,$(TARGET))
HAS_P12		:= $(filter p12/%,$(TARGET))
HAS_RENEW	:= $(filter renew/%,$(TARGET))
HAS_REVOKE	:= $(filter revoke/%,$(TARGET))

# Check if the first MAKECMDGOALS entry starts with one of:
# certs/, p12/, renew/, revoke/
ifneq (,$(or $(HAS_CERTS),$(HAS_P12),$(HAS_RENEW),$(HAS_REVOKE)))

# Convert slashes to spaces to make it easier to extract individual parts
SPACE_TARGET	:= $(subst /, ,$(TARGET))

# Count the number of components in the TARGET
NUM_COMPONENTS	:= $(words $(SPACE_TARGET))

# only static configuration
ifneq ($(NUM_COMPONENTS),4)
$(error Invalid operational target: $(TARGET). Expected <cmd>/<CA>/<CERT_TYPE>/<ID>)
endif

# Extract specific parts based on their position and the number of components
CA		:= $(word 2, $(SPACE_TARGET))
CERT_TYPE	:= $(word 3,$(SPACE_TARGET))

else

# Dummy configuration for non-operational targets.
CA		:= component-ca
CERT_TYPE	:= server

endif
