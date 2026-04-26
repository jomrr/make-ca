# make-ca

![GitHub License](https://img.shields.io/github/license/jomrr/make-ca?style=for-the-badge&color=blue&link=https%3A%2F%2Fgithub.com%2Fjomrr%2Fmake-ca%2Fblob%2Fmain%2FLICENSE) ![GitHub Issues or Pull Requests](https://img.shields.io/github/issues/jomrr/make-ca?style=for-the-badge&color=blue&link=https%3A%2F%2Fgithub.com%2Fjomrr%2Fmake-ca%2Fissues)

`make-ca` is a Makefile-based OpenSSL CA helper for creating and operating a small 3-tier certificate authority.

> This is not meant for production use, but because I can.
>
> CA private key passphrases are stored on disk.

## Overview

The project manages a simple CA hierarchy and end-entity certificates through GNU Make targets.

The default hierarchy is:

```text
root-ca
└── intermediate-ca
    ├── component-ca
    └── identity-ca
```

The repository is optimized for a centralized use case where one operator manages the CA state, OpenSSL configuration files, public CA artifacts, and generated certificate distribution artifacts.

## CA hierarchy

### Root CA

The Root CA is configured in:

```text
etc/root-ca.cnf
```

It issues:

- Intermediate CA certificates
- Root CA CRL

### Intermediate CA

The Intermediate CA is configured in:

```text
etc/intermediate-ca.cnf
```

It issues:

- Signing / issuing CA certificates
- Intermediate CA CRL

### Component CA

The Component CA is configured in:

```text
etc/component-ca.cnf
```

It issues certificates for technical components and services.

Configured certificate classes include:

| Class | Purpose |
|---|---|
| `client` | TLS client certificates |
| `server` | TLS server certificates |
| `ocsp` | OCSP signing certificates |
| `timestamp` | Timestamp signing certificates |

### Identity CA

The Identity CA is configured in:

```text
etc/identity-ca.cnf
```

It issues identity-related certificates.

Configured certificate classes include:

| Class | Purpose |
|---|---|
| `smime` | S/MIME certificates for mail signing and encryption |

## State model

The project separates authoritative CA state from generated distribution artifacts.

| Directory | Purpose | Authoritative |
|---|---|---:|
| `ca/` | CA state, CA private keys, CA database, CA certificates | Yes |
| `ca/db/` | OpenSSL CA index, serial, CRL number, and attributes | Yes |
| `ca/new/` | OpenSSL-issued certificates named by serial number | Yes |
| `ca/private/` | CA private keys and passphrase files | Yes |
| `ca/certs/` | CA certificates | Yes |
| `ca/reqs/` | CA certificate signing requests | Yes |
| `pub/` | Public CA certificates, chains, and CRLs | No |
| `dist/` | Generated end-entity certificate artifacts | No |
| `archive/` | Optional timestamped snapshots before renewal/revocation | No |
| `etc/` | OpenSSL configuration files | Yes |

`dist/` is an operational export area, not authoritative CA state.

Current renewal and revocation targets use the exported certificate in `dist/<CA>/<CERT_TYPE>/<ID>/certificate.pem` as revocation input. This is a known implementation limitation. The canonical issued certificate copies are stored by OpenSSL in `ca/new/` using serial-number-based filenames.

## Directory structure

```text
.
├── archive/
├── ca/
│   ├── certs/
│   ├── db/
│   ├── new/
│   ├── private/
│   └── reqs/
├── dist/
│   └── <CA>/
│       └── <CERT_TYPE>/
│           └── <ID>/
│               ├── bundle.p12
│               ├── certificate.der
│               ├── certificate.pem
│               ├── certificate.txt
│               ├── fullchain.pem
│               ├── key.pem
│               └── request.csr
├── etc/
│   ├── root-ca.cnf
│   ├── intermediate-ca.cnf
│   ├── component-ca.cnf
│   ├── identity-ca.cnf
│   ├── component-ca/
│   │   ├── client/
│   │   ├── server/
│   │   ├── ocsp/
│   │   └── timestamp/
│   └── identity-ca/
│       └── smime/
└── pub/
```

## Generated certificate artifacts

For an end-entity certificate target such as:

```text
certs/component-ca/server/test.example.com
```

the generated artifacts are stored in:

```text
dist/component-ca/server/test.example.com/
```

| File | Purpose |
|---|---|
| `key.pem` | End-entity private key |
| `request.csr` | Certificate signing request |
| `certificate.pem` | Issued certificate in PEM format |
| `certificate.der` | Issued certificate in DER format |
| `certificate.txt` | Text representation of the issued certificate |
| `fullchain.pem` | Issued certificate plus CA chain |
| `bundle.p12` | PKCS#12 bundle with private key, certificate, and CA chain |

## Configuration

General defaults are configured in:

```text
settings.mk
```

Important settings include:

| Variable | Purpose |
|---|---|
| `ROOT_CA` | Root CA slug |
| `SIGNING_CA` | Intermediate CA slug |
| `ISSUING_CA` | Issuing CA slugs |
| `ALL_CA` | Complete CA list |
| `BASE_URL` | Base URL for AIA and CDP references |
| `DN_C` | Default subject country |
| `DN_ST` | Default subject state |
| `DN_L` | Default subject locality |
| `DN_O` | Default subject organization |
| `DN_OU` | Default subject organizational unit |
| `DEFAULT_BITS` | Default RSA key length |
| `DEFAULT_MD` | Default message digest |
| `CAK_ALG` | CA private key algorithm |
| `CPK_ALG` | End-entity private key algorithm |
| `REASON` | Default revocation reason |

## Installation

Clone the repository into the desired CA working directory:

```bash
git clone https://github.com/jomrr/make-ca.git /etc/pki/tls/ca/<name>
cd /etc/pki/tls/ca/<name>
```

Adjust the project settings:

```bash
nvim settings.mk
```

Initialize the CA hierarchy:

```bash
make init
```

## Targets

### General targets

| Target | Purpose |
|---|---|
| `make help` | Show usage information |
| `make init` | Initialize configured CAs and generate CRLs when required |
| `make crls` | Generate CRLs when required |
| `make print` | Print compact CA database records |
| `make print-full` | Print CA database records with full serials and subjects |

### Cleanup targets

| Target | Purpose |
|---|---|
| `make clean` | Delete derived export artifacts while keeping keys, CSRs, and certificates |
| `make distclean` | Delete all generated end-entity distribution artifacts |
| `make destroy` | Delete runtime state directories with interactive confirmation |
| `make mrproper` | Delete runtime state directories without confirmation |

`clean` does not remove private keys, CSRs, or issued certificate exports.

### Certificate targets

| Target | Purpose |
|---|---|
| `make certs/<CA>/<CERT_TYPE>/<ID>` | Create standard certificate artifacts |
| `make p12/<CA>/<CERT_TYPE>/<ID>` | Create a PKCS#12 bundle |
| `make renew/<CA>/<CERT_TYPE>/<ID>` | Renew a certificate using the existing private key |
| `make revoke/<CA>/<CERT_TYPE>/<ID>` | Revoke a certificate |

The certificate configuration file must exist at:

```text
etc/<CA>/<CERT_TYPE>/<ID>.cnf
```

## Usage examples

### Create a TLS server certificate

Copy or create a certificate configuration:

```bash
cp etc/component-ca/server/example.cnf \
  etc/component-ca/server/test.example.com.cnf
```

Edit the request configuration:

```bash
nvim etc/component-ca/server/test.example.com.cnf
```

Issue the certificate:

```bash
make certs/component-ca/server/test.example.com
```

Generated artifacts are written to:

```text
dist/component-ca/server/test.example.com/
```

### Create a PKCS#12 bundle

```bash
make p12/component-ca/server/test.example.com
```

The bundle is written to:

```text
dist/component-ca/server/test.example.com/bundle.p12
```

### Renew a TLS server certificate

```bash
make renew/component-ca/server/test.example.com
```

Renewal revokes the current certificate with reason `superseded`, removes generated certificate artifacts, and rebuilds the certificate using the existing private key.

### Revoke a TLS server certificate

```bash
make revoke/component-ca/server/test.example.com REASON=superseded
```

If `REASON` is omitted, `superseded` is used as the default revocation reason.

Supported revocation reasons depend on OpenSSL and RFC 5280 semantics. Common values include:

| Reason | Meaning |
|---|---|
| `unspecified` | No specific reason |
| `keyCompromise` | End-entity private key was compromised |
| `cACompromise` | CA private key was compromised |
| `affiliationChanged` | Subject affiliation changed |
| `superseded` | Replacement certificate was issued |
| `cessationOfOperation` | Certificate is no longer needed |
| `certificateHold` | Temporary hold |
| `removeFromCRL` | Remove a held certificate from the CRL |
| `privilegeWithdrawn` | Privileges were withdrawn |
| `aACompromise` | Attribute authority was compromised |

### Create an Ed25519 TLS server certificate

```bash
CPK_ALG=ED25519 make certs/component-ca/server/test.example.com
```

## Operational notes

### CA private keys

CA private keys are encrypted with passphrases generated by OpenSSL. The passphrases are stored in:

```text
ca/private/*.pwd
```

This is convenient for lab and local automation use, but it is not appropriate for a production CA without additional controls.

### Offline Root CA

The default workflow does not implement a strict offline Root CA model yet.

For an offline Root CA workflow, Root CA private key material should not be present on the online issuing host. The online host should only contain the public Root CA certificate, public chains, CRLs, and the CA material required for online issuing CAs.

This requires additional operational separation and is not fully enforced by the current Makefile.

### Current limitations

The current implementation has the following known limitations:

- The CA hierarchy is still modeled as a fixed 3-tier setup.
- Renewal and revocation currently require the exported certificate in `dist/`.
- CA parent relationships are not yet modeled generically in `settings.mk`.
- Offline Root CA operation is documented conceptually but not enforced.
- CRL generation is Make-target based and not a forced refresh unless dependencies require it.

## License

This project is licensed under the [MIT License](https://github.com/jomrr/make-ca/blob/main/LICENSE).

## Copyright

Copyright © 2022-2026 Jonas Mauer

## Maintainer

- @jomrr
