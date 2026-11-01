#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OVN_DIR="${ROOT_DIR}/ovn"
JOBS="${JOBS:-$(nproc)}"
GIT_DEPTH="${GIT_DEPTH:-1}"

usage() {
    cat <<'EOF'
Usage: ./sandbox.sh [start|setup|cleanup|distclean]

Commands:
  start      Build OVN/OVS if needed, then launch `make sandbox` (default).
  setup      Bootstrap, configure, and build OVN/OVS without starting sandbox.
  cleanup    Stop sandbox daemons and remove the runtime sandbox directory.
  distclean  Run cleanup, then remove generated build/configure artifacts.

Environment:
  JOBS=N          Parallel make jobs. Defaults to nproc.
  GIT_DEPTH=N     Git submodule clone depth. Defaults to 1.
  SANDBOXFLAGS=  Extra flags passed to `make sandbox`.
EOF
}

require_ovn_checkout() {
    if [[ ! -d "${OVN_DIR}" ]]; then
        echo "OVN checkout not found at ${OVN_DIR}" >&2
        exit 1
    fi
}

run() {
    echo "+ $*"
    "$@"
}

ensure_ovs() {
    cd "${OVN_DIR}"
    run git submodule update --init --depth "${GIT_DEPTH}"

    cd "${OVN_DIR}/ovs"
    if [[ ! -x ./configure ]]; then
        run ./boot.sh
    fi
    if [[ ! -f Makefile ]]; then
        run ./configure
    fi
    run make -j"${JOBS}"
}

ensure_ovn() {
    cd "${OVN_DIR}"
    if [[ ! -x ./configure ]]; then
        run ./boot.sh
    fi
    if [[ ! -f Makefile ]]; then
        run ./configure
    fi
    run make -j"${JOBS}"
}

setup() {
    require_ovn_checkout
    ensure_ovs
    ensure_ovn
}

start() {
    setup
    cd "${OVN_DIR}"
    run make sandbox SANDBOXFLAGS="${SANDBOXFLAGS:-}"
}

cleanup() {
    require_ovn_checkout

    local sandbox_dir="${OVN_DIR}/tutorial/sandbox"
    if [[ -d "${sandbox_dir}" ]]; then
        if compgen -G "${sandbox_dir}/*.pid" >/dev/null; then
            while IFS= read -r pid_file; do
                local pid
                pid="$(cat "${pid_file}")"
                if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
                    run kill "${pid}"
                fi
            done < <(find "${sandbox_dir}" -maxdepth 1 -name '*.pid' -type f)
        fi
        run rm -rf "${sandbox_dir}"
    else
        echo "No sandbox runtime directory found at ${sandbox_dir}"
    fi
}

distclean() {
    cleanup

    if [[ -f "${OVN_DIR}/Makefile" ]]; then
        cd "${OVN_DIR}"
        run make distclean
    fi

    if [[ -f "${OVN_DIR}/ovs/Makefile" ]]; then
        cd "${OVN_DIR}/ovs"
        run make distclean
    fi
}

cmd="${1:-start}"
case "${cmd}" in
    start)
        start
        ;;
    setup)
        setup
        ;;
    cleanup)
        cleanup
        ;;
    distclean)
        distclean
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        echo "Unknown command: ${cmd}" >&2
        usage >&2
        exit 2
        ;;
esac
