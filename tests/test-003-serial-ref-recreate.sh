#!/usr/bin/env bash
# Verify that the current serial reference can be recreated from certificate.pem.

set -Eeuo pipefail

# shellcheck source=tests/lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/common.sh"

declare EXPECTED_SERIAL=""
declare ACTUAL_SERIAL=""

trap test_cleanup EXIT
setup_workspace

run_make "certs/${TEST_CERT_SPEC}"

EXPECTED_SERIAL="$(cat -- "ca/refs/${TEST_CERT_SPEC}/serial")"

rm -f -- "ca/refs/${TEST_CERT_SPEC}/serial"
run_make "ca/refs/${TEST_CERT_SPEC}/serial"

ACTUAL_SERIAL="$(cat -- "ca/refs/${TEST_CERT_SPEC}/serial")"

[[ "${ACTUAL_SERIAL}" == "${EXPECTED_SERIAL}" ]] \
    || test_fail "serial reference recreation failed"
