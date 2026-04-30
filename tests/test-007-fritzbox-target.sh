#!/usr/bin/env bash
# Verify the dedicated FRITZ!Box target family.

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=tests/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

declare fritzbox_pem=""
declare leaf_cert=""
declare first_label=""
declare first_key_line=""
declare first_cert_line=""
declare cert_count=""
declare key_pub_hash=""
declare cert_pub_hash=""

trap test_cleanup EXIT

setup_workspace fritzbox

fritzbox_pem="dist/${TEST_CERT_SPEC}/fritzbox.pem"
leaf_cert="dist/${TEST_CERT_SPEC}/certificate.pem"

test_log "verify FRITZ!Box spec is not exposed as certs/${TEST_CERT_SPEC}"

if run_make -n "certs/${TEST_CERT_SPEC}" >/dev/null 2>&1; then
    test_fail "FRITZ!Box spec must not be exposed as certs/${TEST_CERT_SPEC}"
fi

test_log "build fritzbox/${TEST_CERT_SPEC}"

run_make "fritzbox/${TEST_CERT_SPEC}"

require_file "dist/${TEST_CERT_SPEC}/key.pem"
require_file "${leaf_cert}"
require_file "dist/${TEST_CERT_SPEC}/certificate.txt"
require_file "${fritzbox_pem}"
require_file "ca/refs/${TEST_CERT_SPEC}/serial"

test_log "verify FRITZ!Box PEM order"

first_label="$(
    grep -m 1 '^-----BEGIN ' "${fritzbox_pem}" \
        | sed 's/^-----BEGIN //; s/-----$//'
)"

case "${first_label}" in
    "PRIVATE KEY"|"RSA PRIVATE KEY")
        ;;
    *)
        test_fail "FRITZ!Box PEM must start with a private key, got: ${first_label}"
        ;;
esac

first_key_line="$(
    grep -n -m 1 '^-----BEGIN .*PRIVATE KEY-----' "${fritzbox_pem}" \
        | cut -d ':' -f 1
)"

first_cert_line="$(
    grep -n -m 1 '^-----BEGIN CERTIFICATE-----' "${fritzbox_pem}" \
        | cut -d ':' -f 1
)"

[[ -n "${first_key_line}" ]] || test_fail "FRITZ!Box PEM does not contain a private key"
[[ -n "${first_cert_line}" ]] || test_fail "FRITZ!Box PEM does not contain a certificate"

if (( first_key_line >= first_cert_line )); then
    test_fail "FRITZ!Box PEM must contain private key before certificate"
fi

cert_count="$(
    grep -c '^-----BEGIN CERTIFICATE-----' "${fritzbox_pem}"
)"

if (( cert_count < 2 )); then
    test_fail "FRITZ!Box PEM must contain leaf certificate and CA chain"
fi

test_log "verify first certificate in FRITZ!Box PEM is the leaf certificate"

awk '
    /^-----BEGIN CERTIFICATE-----$/ {
        capture = 1
    }

    capture {
        print
    }

    /^-----END CERTIFICATE-----$/ && capture {
        exit
    }
' "${fritzbox_pem}" > first-bundled-cert.pem

if ! cmp -s -- "${leaf_cert}" first-bundled-cert.pem; then
    test_fail "first certificate in FRITZ!Box PEM is not the leaf certificate"
fi

test_log "verify FRITZ!Box key is RSA"

openssl rsa \
    -in "dist/${TEST_CERT_SPEC}/key.pem" \
    -check \
    -noout \
    >/dev/null

test_log "verify private key matches certificate"

key_pub_hash="$(
    openssl pkey \
        -in "dist/${TEST_CERT_SPEC}/key.pem" \
        -pubout \
        -outform DER \
        | sha256sum \
        | awk '{ print $1 }'
)"

cert_pub_hash="$(
    openssl x509 \
        -in "${leaf_cert}" \
        -pubkey \
        -noout \
        | openssl pkey \
            -pubin \
            -outform DER \
        | sha256sum \
        | awk '{ print $1 }'
)"

[[ "${key_pub_hash}" == "${cert_pub_hash}" ]] \
    || test_fail "FRITZ!Box private key does not match certificate public key"

test_log "verify certificate text export"

grep -q 'Subject Alternative Name' "dist/${TEST_CERT_SPEC}/certificate.txt" \
    || test_fail "FRITZ!Box certificate text output is missing SAN extension"

test_log "FRITZ!Box target test passed"
