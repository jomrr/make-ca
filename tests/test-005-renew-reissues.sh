#!/usr/bin/env bash
# Verify that renew keeps the private key and revokes the previous serial.

set -Eeuo pipefail

# shellcheck source=tests/lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/common.sh"

declare KEY_BEFORE=""
declare KEY_AFTER=""
declare SERIAL_BEFORE=""
declare SERIAL_AFTER=""

trap test_cleanup EXIT
setup_workspace

run_make "certs/${TEST_CERT_SPEC}"

KEY_BEFORE="$(file_sha256 "dist/${TEST_CERT_SPEC}/key.pem")"
SERIAL_BEFORE="$(cat -- "ca/refs/${TEST_CERT_SPEC}/serial")"

run_make "renew/${TEST_CERT_SPEC}"

require_file "dist/${TEST_CERT_SPEC}/key.pem"
require_file "dist/${TEST_CERT_SPEC}/certificate.pem"
require_file "ca/refs/${TEST_CERT_SPEC}/serial"

KEY_AFTER="$(file_sha256 "dist/${TEST_CERT_SPEC}/key.pem")"
SERIAL_AFTER="$(cat -- "ca/refs/${TEST_CERT_SPEC}/serial")"

[[ "${KEY_AFTER}" == "${KEY_BEFORE}" ]] \
    || test_fail "renew changed the private key"

[[ "${SERIAL_AFTER}" != "${SERIAL_BEFORE}" ]] \
    || test_fail "renew did not create a new serial"

assert_serial_revoked "${TEST_CERT_CA}" "${SERIAL_BEFORE}"
