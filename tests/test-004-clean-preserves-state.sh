#!/usr/bin/env bash
# Verify that clean removes only derived export artifacts.

set -Eeuo pipefail

# shellcheck source=tests/lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/common.sh"

trap test_cleanup EXIT
setup_workspace

run_make "certs/${TEST_CERT_SPEC}"
run_make clean

require_file "dist/${TEST_CERT_SPEC}/key.pem"
require_file "dist/${TEST_CERT_SPEC}/request.csr"
require_file "dist/${TEST_CERT_SPEC}/certificate.pem"

require_missing "dist/${TEST_CERT_SPEC}/certificate.der"
require_missing "dist/${TEST_CERT_SPEC}/certificate.txt"
require_missing "dist/${TEST_CERT_SPEC}/fullchain.pem"

run_make "certs/${TEST_CERT_SPEC}"

require_file "dist/${TEST_CERT_SPEC}/certificate.der"
require_file "dist/${TEST_CERT_SPEC}/certificate.txt"
require_file "dist/${TEST_CERT_SPEC}/fullchain.pem"
