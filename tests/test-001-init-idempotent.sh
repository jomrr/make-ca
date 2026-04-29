#!/usr/bin/env bash
# Verify that init does not rebuild existing CA state.

set -Eeuo pipefail

# shellcheck source=tests/lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/common.sh"

declare BEFORE_SNAPSHOT=""
declare AFTER_SNAPSHOT=""

trap test_cleanup EXIT
setup_workspace

BEFORE_SNAPSHOT="${TEST_WORK_DIR}/ca-before.sha256"
AFTER_SNAPSHOT="${TEST_WORK_DIR}/ca-after.sha256"

run_make init
snapshot_ca_identity_state "${BEFORE_SNAPSHOT}"

find etc -maxdepth 1 -type f -name '*.cnf' -exec touch {} +
touch settings.mk

run_make init
snapshot_ca_identity_state "${AFTER_SNAPSHOT}"

assert_same_file "${BEFORE_SNAPSHOT}" "${AFTER_SNAPSHOT}"
