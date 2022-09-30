# distiguished name defaults
export DN_C				?= DE
export DN_ST			?= Bayern
export DN_L				?= Strunzenoed
export DN_O				?= Example
export DN_OU			?= $(DN_O) PKI
# default RSA bit length in cnf files
export DEFAULT_BITS		?= 4096
# default settings for hash in cnf files
export DEFAULT_MD		?= sha512
# base URL of pki, where WEBDIR is found, also used as AIA and CDP base
export PKIURL			:= http://pki.example.com
# list of CRL Distribution Points in SSH syntax for deploy-crls target (TODO)
export CDP				:= cdp1:/var/www/pki
# CA Keys: param for openssl genpkey -algorithm $(CAK_ALG)
#CAK_ALG					?= ED25519
CAK_ALG					?= RSA -pkeyopt rsa_keygen_bits:8192
# CRT Keys: param for openssl req -newkey $(KEY_ALG)
# NOTE: ED25519 p12 client certificates fail to import with Firefox 97.0
#KEY_ALG					?= ED25519
KEY_ALG					?= RSA:$(DEFAULT_BITS)
