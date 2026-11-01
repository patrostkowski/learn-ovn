#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OVN_DIR="${ROOT_DIR}/ovn"
OVN_REPO_URL="https://github.com/ovn-org/ovn.git"
JOBS="${JOBS:-$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)}"
GIT_DEPTH="${GIT_DEPTH:-1}"
BUILD_TOOLS=(git make cc autoconf automake libtoolize python3)

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

require_build_tools() {
    local missing=()
    local tool
    for tool in "${BUILD_TOOLS[@]}"; do
        command -v "${tool}" >/dev/null 2>&1 || missing+=("${tool}")
    done
    if (( ${#missing[@]} > 0 )); then
        cat >&2 <<EOF
Missing build tools: ${missing[*]}

Install them first, for example:
  Fedora/RHEL:   sudo dnf install git make gcc autoconf automake libtool python3 openssl-devel
  Debian/Ubuntu: sudo apt install git make gcc autoconf automake libtool python3 libssl-dev
EOF
        exit 1
    fi
}

# Fetches the pinned ovn submodule when the clone was made without --recurse-submodules.
ensure_ovn_checkout() {
    if [[ -f "${OVN_DIR}/configure.ac" ]]; then
        return
    fi

    if git -C "${ROOT_DIR}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        run git -C "${ROOT_DIR}" submodule update --init --depth "${GIT_DEPTH}" ovn
        return
    fi

    echo "Not a git checkout, cloning latest OVN from ${OVN_REPO_URL} (not the pinned commit)." >&2
    if [[ -d "${OVN_DIR}" ]] && ! rmdir "${OVN_DIR}" 2>/dev/null; then
        echo "${OVN_DIR} exists but is not an OVN checkout, remove it and rerun." >&2
        exit 1
    fi
    run git clone --depth "${GIT_DEPTH}" "${OVN_REPO_URL}" "${OVN_DIR}"
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
    require_build_tools
    ensure_ovn_checkout
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
