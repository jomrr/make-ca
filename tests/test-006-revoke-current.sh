#!/usr/bin/env bash
# Verify that revoke revokes the current certificate and removes current state.

set -Eeuo pipefail

# shellcheck source=tests/lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/common.sh"

declare SERIAL_BEFORE=""

trap test_cleanup EXIT
setup_workspace

run_make "certs/${TEST_CERT_SPEC}"

SERIAL_BEFORE="$(cat -- "ca/refs/${TEST_CERT_SPEC}/serial")"

run_make "revoke/${TEST_CERT_SPEC}"

require_missing "dist/${TEST_CERT_SPEC}"
require_missing "ca/refs/${TEST_CERT_SPEC}/serial"

assert_serial_revoked "${TEST_CERT_CA}" "${SERIAL_BEFORE}"
