# make-ca

![GitHub License](https://img.shields.io/github/license/jam82/make-ca?style=for-the-badge&color=blue&link=https%3A%2F%2Fgithub.com%2Fjam82%2Fmake-ca%2Fblob%2Fmain%2FLICENSE) ![GitHub Issues or Pull Requests](https://img.shields.io/github/issues/jam82/make-ca?style=for-the-badge&color=blue&link=https%3A%2F%2Fgithub.com%2Fjam82%2Fmake-ca%2Fissues)

Makefile for creating and managing a 3-tier certificate authority.

> This is not meant for production use, but because I can.
>
> The passwords for the CA keys are stored on disk.

## Getting started

The `make-ca` project is a Makefile-based tool for creating and managing a 3-tier certificate authority. It provides a simple and automated way to generate and manage certificates for various purposes.

### Directory Structure

| level 0 | level 1 | level 2 | description |
| ------- | ------- | ------- | ----------- |
| **name** | | | base dir of the ca, e.g. example for Example CA |
| | ca | | CA specific data |
| | | archive | revoked certificates are archived here |
| | | certs | CA certificates go here |
| | | db | CA database and serial files are located here |
| | | new | new issued certificates named by serial no. |
| | | private | private keys of CAs |
| | | reqs | CSRs of the CA certificates |
| | dist  | | issued certificates and keys from signing CAs |
| | etc | | openssl configuration files |
| | www | | web distribution folder with CA certs, CRLs |

The following headlines describe the CA structure.

### Root CA

The Root CA of the 3-tier setup, configured in `etc/root-ca.cnf`.

Issues:

- Intermediate CA certificates
- Root CA CRL

#### Intermediate CA

The Intermedite CA of the 3-tier setup, configured in `etc/intermediate-ca.cnf`.

Issues:

- Signing CA certificates
- Intermediate CA CRL

##### Identity CA

The Identity CA (a Signing CA), configured in `etc/identity-ca.cnf`.

Issues:

- `smime`: S/MIME Certificates for mail signature end encryption
- Identity CA CRL

##### Component CA

The Component CA (a Signing CA), configured in `etc/component-ca.cnf`.

Issues:

- `client`: TLS Client certificates
- `fritzbox`: TLS Server certificates for AVM Router with all default SANs
- `server`: TLS Server certificates
- Component CA CRL

## Installation

To install `make-ca`, follow these steps:

1. Clone the repository: `git clone https://github.com/jam82/make-ca.git /etc/pki/tls/ca/<your name>`
2. Change into the project directory: `cd /etc/pki/tls/ca/<your name>`
3. Customize `settings.mk` to your needs
4. Initialize the CAs wit the command: `make init`

## Usage Examples

Here are a few examples how to use `make-ca`.

### Create TLS Server certificate with subjectAltNames

```bash
make client CN=server01.example.com SAN=="DNS:server01.example.com,DNS:www.example.com,IP:10.12.10.11"

# example output:
Signature ok
Certificate Details:
        Serial Number:
            61:3b:bc:01:8b:c1:34:99:db:1b:b2:e3:8a:0c:77:fa:64:6e:bd:0c
        Validity
            Not Before: Feb 24 21:25:10 2024 GMT
            Not After : Feb 23 21:25:10 2026 GMT
        Subject:
            countryName               = DE
            stateOrProvinceName       = Bayern
            localityName              = Strunzenoed
            organizationName          = Example
            organizationalUnitName    = Example PKI
            commonName                = server01.example.com
        X509v3 extensions:
            X509v3 Key Usage: critical
                Digital Signature, Key Encipherment
            X509v3 Extended Key Usage: 
                TLS Web Client Authentication, TLS Web Server Authentication
            X509v3 Subject Key Identifier: 
                42:BE:22:33:44:CF:72:02:58:EB:EF:88:4B:BA:1C:10:B6:AA:DB:C8
            X509v3 Authority Key Identifier: 
                FE:80:D7:E5:6D:27:9E:85:18:13:99:E5:79:B4:9E:CB:FA:42:21:F4
            Authority Information Access: 
                CA Issuers - URI:http://pki.example.com/component-ca.cer
                OCSP - URI:http://ocsp.example.com/component
            X509v3 CRL Distribution Points: 
                Full Name:
                  URI:http://pki.example.com/component-ca.crl
            X509v3 Subject Alternative Name: 
                DNS:server01.example.com, DNS:www.example.com, IP:10.12.10.11
Certificate is to be certified until Feb 23 21:25:10 2026 GMT (730 days)

Write out database with 1 new entries
Data Base Updated
```

### Revoke TLS Server certificate

Use the CA specific target to revoke, in this case `make rev-component`.

```bash
make rev-component CN=server01.example.com REASON=superseded
```

### Create Ed25519 TLS Server certificate

```bash
KEY_ALG=ED25519 make server CN=test.example.com
```

### Create S/MIME certificate

```bash
make smime CN="John Doe" EMAIL="john.doe@example.com"
```

### Revoke S/MIME certificate

Use the CA specific target to revoke, in this case `make rev-identity`.

```bash
make rev-identity EMAIL="john.doe@example.com"
```

## License

This project is licensed under the [MIT License](https://github.com/jam82/make-ca/blob/main/LICENSE).

## Author(s)

- @jam82 (2022)
