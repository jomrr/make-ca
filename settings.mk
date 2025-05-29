################################################################################
# CA and certificate settings
################################################################################

# list of CA slugs
ROOT_CA			:= root-ca
SIGNING_CA		:= intermediate-ca
ISSUING_CA		:= component-ca identity-ca
ALL_CA			:= $(ROOT_CA) $(SIGNING_CA) $(ISSUING_CA)

# distiguished name defaults
export DN_C		?= DE
export DN_ST		?= Bayern
export DN_L		?= Strunzenoed
export DN_O		?= Example
export DN_OU		?= $(DN_O) PKI

# default reason for certificate revocation
# ref: https://datatracker.ietf.org/doc/html/rfc5280#section-4.2.1.13
# unspecified: 		revoke a certificate without providing a specific reason code
# keyCompromise: 	the private key associated with the certificate has been compromised
# cACompromise: 	the CA's private key has been compromised
# affiliationChanged: 	user has terminated his or her relationship with the organization
# superseded:		replacement certificate has been issued to a user
# cessationOfOperation:	CA is decommissioned, no longer to be used
# certificateHold:	temporary revocation that indicates that a CA will not vouch for a certificate
# removeFromCRL:	certificate is revoked with CertificateHold reason, it is possible to "unrevoke"
# privilegeWithdrawn:	privileges granted to the subject of the certificate have been withdrawn
# aACompromise:		attribute authority has been compromised
REASON			?= superseded

################################################################################
# CA URL settings
################################################################################

# base URL of pki, where WEBDIR is found, also used as AIA and CDP base
export BASE_URL		:= http://pki.example.com

################################################################################
# Key and hash algorithm settings
################################################################################

# default RSA bit length in cnf files
export DEFAULT_BITS	?= 4096

# default settings for hash in cnf files
# Ok, I am shocked again. 2025 and sha3-256 is not a valid signature algorithm.
export DEFAULT_MD	?= sha384

# The Ed25519 digital signature algorithm is supported by the Web Crypto API,
# and can be used in the SubtleCrypto methods: sign(), verify(), generateKey(),
# importKey() and exportKey() (Firefox bug 1804788).
https://bugzilla.mozilla.org/show_bug.cgi?id=1804788
# But Firefox still does not support Ed25519 keys as
# client certificates (PKCS12) via NSS in 2025!!!
https://bugzilla.mozilla.org/show_bug.cgi?id=1598515

# Defaulting to secp384r1 (P-384) for CA and certificate private keys for now.
# secp521r1 (P-521) support was removed by Mozilla and Google in 2024.

# CA private Keys:
# param for openssl genpkey -algorithm $(CAK_ALG)

#CAK_ALG			?= ED25519
CAK_ALG			?= RSA -pkeyopt rsa_keygen_bits:$(DEFAULT_BITS)
#CAK_ALG			?= EC -pkeyopt ec_paramgen_curve:P-384

# Certificate Private Keys:
# param for openssl genpkey -algorithm $(CPK_ALG)

#CPK_ALG			?= ED25519
CPK_ALG			?= RSA -pkeyopt rsa_keygen_bits:$(DEFAULT_BITS)
#CPK_ALG			?= EC -pkeyopt ec_paramgen_curve:P-384
