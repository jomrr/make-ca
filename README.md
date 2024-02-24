# make-ca

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/jam82/make-ca/blob/main/LICENSE)

Makefile for creating and managing a 3-tier certificate authority.

> This is not meant for production use, but because I can.
>
> The passwords for the CA keys are stored on disk.

## Table of Contents

- [make-ca](#make-ca)
  - [Table of Contents](#table-of-contents)
  - [Getting started](#getting-started)
    - [Directory Structure](#directory-structure)
    - [Root CA](#root-ca)
      - [Intermediate CA](#intermediate-ca)
        - [Identity CA](#identity-ca)
        - [Component CA](#component-ca)
  - [Installation](#installation)
  - [Usage Examples](#usage-examples)
    - [Create TLS Server certificate with subjectAltNames](#create-tls-server-certificate-with-subjectaltnames)
    - [Revoke TLS Server certificate](#revoke-tls-server-certificate)
  - [License](#license)
  - [Author(s)](#authors)

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
