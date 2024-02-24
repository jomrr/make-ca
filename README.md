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
make client CN=server01.example.com SAN=="DNS:tatooine.example.com,DNS:www.example.com,IP:10.12.10.11"
```

### Revoke TLS Server certificate

Use \<tab\> for autocompletion after `make revoke-`.

```bash
make revoke-server01<tab>.example.com REASON=superseded
```

## License

This project is licensed under the [MIT License](https://github.com/jam82/make-ca/blob/main/LICENSE).

## Author(s)

- @jam82 (2022)
