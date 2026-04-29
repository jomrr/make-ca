#!/usr/bin/env bash
# Verify that certificate configuration changes do not implicitly reissue leaves.

set -Eeuo pipefail

# shellcheck source=tests/lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/common.sh"

declare BEFORE_SNAPSHOT=""
declare AFTER_SNAPSHOT=""

trap test_cleanup EXIT
setup_workspace

BEFORE_SNAPSHOT="${TEST_WORK_DIR}/leaf-before.sha256"
AFTER_SNAPSHOT="${TEST_WORK_DIR}/leaf-after.sha256"

run_make "certs/${TEST_CERT_SPEC}"

{
    sha256sum -- "ca/db/${TEST_CERT_CA}.txt"
    sha256sum -- "ca/refs/${TEST_CERT_SPEC}/serial"
    sha256sum -- "dist/${TEST_CERT_SPEC}/key.pem"
    sha256sum -- "dist/${TEST_CERT_SPEC}/request.csr"
    sha256sum -- "dist/${TEST_CERT_SPEC}/certificate.pem"
} > "${BEFORE_SNAPSHOT}"

touch "etc/${TEST_CERT_SPEC}.cnf"
touch "etc/${TEST_CERT_CA}.cnf"

run_make "certs/${TEST_CERT_SPEC}"

{
    sha256sum -- "ca/db/${TEST_CERT_CA}.txt"
    sha256sum -- "ca/refs/${TEST_CERT_SPEC}/serial"
    sha256sum -- "dist/${TEST_CERT_SPEC}/key.pem"
    sha256sum -- "dist/${TEST_CERT_SPEC}/request.csr"
    sha256sum -- "dist/${TEST_CERT_SPEC}/certificate.pem"
} > "${AFTER_SNAPSHOT}"

assert_same_file "${BEFORE_SNAPSHOT}" "${AFTER_SNAPSHOT}"
