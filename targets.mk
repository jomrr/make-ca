# file: targets.mk
#
# ******************************************************************************
# Description: This file contains variables for dynamic targets used to manage
#              dynamic certificate generation, renewal and revocation.
# ******************************************************************************

# operational settings
DATETIME	:= $(shell date +%Y-%m-%dT%H:%M:%S%z)
# static configuration files
CONFIGS		:= $(shell find etc -mindepth 3 -maxdepth 3 -type f -name "*.cnf")
# dynamic targets for p12 bundles
P12S		:= $(foreach cfg,$(CONFIGS),$(subst .cnf,,$(subst etc/,p12/,$(cfg))))
# dynamic targets for certificates
CERTS		:= $(foreach cfg,$(CONFIGS),$(subst .cnf,,$(subst etc/,certs/,$(cfg))))
# dynamic targets for renewals
RENEWS		:= $(foreach cfg,$(CONFIGS),$(subst .cnf,,$(subst etc/,renew/,$(cfg))))
# dynamic targets for revocations
REVOKES		:= $(foreach cfg,$(CONFIGS),$(subst .cnf,,$(subst etc/,revoke/,$(cfg))))

# ******************************************************************************

TARGET 		:= $(firstword $(MAKECMDGOALS))

# Define a helper variable to check each pattern.
HAS_CERTS	:= $(findstring certs/,$(TARGET))
HAS_P12		:= $(findstring p12/,$(TARGET))
HAS_RENEW	:= $(findstring renew/,$(TARGET))
HAS_REVOKE	:= $(findstring revoke/,$(TARGET))

# Check if first MAKECMDGOALS start with "{certs,p12,renew,revoke}/"
ifneq (,$(or $(HAS_CERTS),$(HAS_P12),$(HAS_RENEW),$(HAS_REVOKE)))

# Convert slashes to spaces to make it easier to extract individual parts
SPACE_TARGET	:= $(subst /, ,$(TARGET))

# Count the number of components in the TARGET
NUM_COMPONENTS	:= $(words $(SPACE_TARGET))

# Extract specific parts based on their position and the number of components
CA		:= $(word 2, $(SPACE_TARGET))

# static configuration
ifeq ($(NUM_COMPONENTS),4)  # Implies format: etc/CA/CERT_TYPE/IDENTIFIER.cnf
	CERT_TYPE	:= $(word 3, $(SPACE_TARGET))
	ID_RAW		:= $(word 4, $(SPACE_TARGET))
	ID		:= $(basename $(SPACE_TARGET))  # Remove the .cnf extension
# template configuration per extension
else ifeq ($(NUM_COMPONENTS),3)  # Implies format: etc/CA/CERT_TYPE.cnf
	CERT_TYPE	:= $(basename $(word 3, $(SPACE_TARGET)))
	ID_RAW		:= $(word 3, $(SPACE_TARGET))
	ID		:= $(CERT_TYPE)  # CERT_TYPE and IDENTIFIER are the same
endif

# dummy configurtion, to prevent errors, when other targets are called
else
	CA		:= component-ca
	CERT_TYPE	:= server
	ID_RAW		:= dummy.cnf
	ID		:= dummy
endif
