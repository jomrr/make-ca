################################################################################
# CA and certificate settings
################################################################################

# distiguished name defaults
export DN_C				?= DE
export DN_ST			?= Bayern
export DN_L				?= Strunzenoed
export DN_O				?= Example
export DN_OU			?= $(DN_O) PKI

# fritzbox.cnf public myfritz name
export FRITZBOX_PUBLIC	?= wsroikgniugb7373e4t4

# fritzbox.cnf internal name
export FRITZBOX_INTERN  ?= MosEisley

# fritzbox.cnf: IPv4 address
export FRITZBOX_IP4		?= 10.0.0.1

################################################################################
# CA URL settings
################################################################################

# base URL of pki, where WEBDIR is found, also used as AIA and CDP base
export BASE_URL			:= http://pki.example.com

# OCSP URL for Online Certificate Status Protocol
export OCSP_URL			:= http://ocsp.example.com

################################################################################
# Key and hash algorithm settings
################################################################################

# default RSA bit length in cnf files
export DEFAULT_BITS		?= 4096

# default settings for hash in cnf files
export DEFAULT_MD		?= sha3-256

# CA Keys: param for openssl genpkey -algorithm $(CAK_ALG)
#CAK_ALG					?= ED448
CAK_ALG					?= RSA -pkeyopt rsa_keygen_bits:8192

# CRT Private Keys: param for openssl req -newkey $(KEY_ALG)
# NOTE: ED25519 p12 client certificates still fail to import in Browsers
#CPK_ALG					?= ED448
CPK_ALG					?= RSA:$(DEFAULT_BITS)
