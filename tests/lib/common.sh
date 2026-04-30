#!/usr/bin/env bash
# Common test helpers for make-ca.
#
# The helpers create an isolated temporary copy of the source tree and expose
# small assertions used by the individual test scripts.

set -Eeuo pipefail

: "${TEST_REPO_ROOT:?TEST_REPO_ROOT must be set by the test orchestrator}"

declare TEST_WORK_DIR=""
declare TEST_CERT_SPEC=""
declare TEST_CERT_CA=""

test_fail() {
    local message
    message="$1"

    printf 'ERROR: %s\n' "${message}" >&2
    exit 1
}

test_log() {
    local message
    message="$1"

    printf '    %s\n' "${message}"
}

test_cleanup() {
    if [[ -n "${TEST_WORK_DIR}" && -d "${TEST_WORK_DIR}" ]]; then
        rm -rf -- "${TEST_WORK_DIR}"
    fi
}

run_make() {
    make --no-print-directory "$@"
}

require_file() {
    local path
    path="$1"

    [[ -f "${path}" ]] || test_fail "missing file: ${path}"
}

require_missing() {
    local path
    path="$1"

    [[ ! -e "${path}" ]] || test_fail "path should not exist: ${path}"
}

file_sha256() {
    local path
    path="$1"

    sha256sum -- "${path}" | awk '{ print $1 }'
}

snapshot_ca_identity_state() {
    local snapshot_file

    snapshot_file="$1"

    {
        find ca/private -type f -print
        find ca/reqs -type f -print
        find ca/certs -type f -print
        find ca/db -type f \
            ! -name '*.crlnumber' \
            ! -name '*.crlnumber.old' \
            -print
    } | sort | while read -r file_path; do
        sha256sum -- "${file_path}"
    done > "${snapshot_file}"
}

snapshot_tree() {
    local source_dir
    local snapshot_file

    source_dir="$1"
    snapshot_file="$2"

    (
        cd -- "${source_dir}"
        find . -type f -print0 \
            | sort -z \
            | while IFS= read -r -d '' file_path; do
                sha256sum -- "${file_path}"
            done
    ) > "${snapshot_file}"
}

assert_same_file() {
    local left
    local right

    left="$1"
    right="$2"

    if ! cmp -s -- "${left}" "${right}"; then
        diff -u -- "${left}" "${right}" || true
        test_fail "snapshots differ: ${left} ${right}"
    fi
}

choose_standard_cert_spec() {
    local spec

    spec="$(
        find etc -mindepth 3 -maxdepth 3 -type f -name '*.cnf' \
            ! -path 'etc/*/fritzbox/*' \
            | sort \
            | sed 's#^etc/##; s#\.cnf$##' \
            | head -n 1
    )"

    [[ -n "${spec}" ]] || test_fail "no standard certificate spec found below etc/<CA>/<TYPE>/<ID>.cnf"

    TEST_CERT_SPEC="${spec}"
    TEST_CERT_CA="${TEST_CERT_SPEC%%/*}"
}

choose_fritzbox_cert_spec() {
    local spec

    spec="$(
        find etc -mindepth 3 -maxdepth 3 -type f -path 'etc/*/fritzbox/*.cnf' \
            | sort \
            | sed 's#^etc/##; s#\.cnf$##' \
            | head -n 1
    )"

    [[ -n "${spec}" ]] || test_fail "no FRITZ!Box certificate spec found below etc/<CA>/fritzbox/<ID>.cnf"

    TEST_CERT_SPEC="${spec}"
    TEST_CERT_CA="${TEST_CERT_SPEC%%/*}"
}

setup_workspace() {
    local spec_type

    spec_type="${1:-standard}"
    TEST_WORK_DIR="$(mktemp -d)"

    tar -C "${TEST_REPO_ROOT}" -cf - Makefile settings.mk bin etc \
        | tar -C "${TEST_WORK_DIR}" -xf -

    cd -- "${TEST_WORK_DIR}"

    case "${spec_type}" in
        fritzbox)
            choose_fritzbox_cert_spec
            ;;
        *)
            choose_standard_cert_spec
            ;;
    esac

    test_log "workspace: ${TEST_WORK_DIR}"
    test_log "cert spec: ${TEST_CERT_SPEC}"
}

assert_serial_revoked() {
    local ca
    local serial

    ca="$1"
    serial="$2"

    if ! grep -F -- "${serial}" "ca/db/${ca}.txt" | grep -q '^R'; then
        test_fail "serial was not revoked: ${serial}"
    fi
}
