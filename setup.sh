#!/bin/bash
set -euo pipefail

# One universal setup for any Ubuntu development environment, physical or
# virtual. Currently exercised on an Ubuntu 24.04 workstation (x86_64) and an
# Ubuntu Server 26.04 VM (aarch64), but nothing here is pinned to a release or
# an architecture: package names resolve against whatever apt offers, the Go
# version comes from go.mod, and the arch is detected at runtime.
#
# Run as your normal user, NOT with sudo. The script escalates only for the
# apt steps; running the whole thing as root would drop the Go module cache
# in /root and force a re-download on the first user-owned build.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

info()  { echo "  $*"; }
step()  { echo; echo "==> $*"; }
warn()  { echo "  [warn] $*" >&2; }
die()   { echo "  [error] $*" >&2; exit 1; }

# ── Preconditions ─────────────────────────────────────────────────────────

if [[ "$(uname -s)" != "Linux" ]]; then
    die "This project targets Linux kernel APIs (Netlink, XDP, eBPF) and cannot
  build or run on $(uname -s). Run this script on an Ubuntu machine — physical
  or a VM — see the Quick Start in README.md."
fi

if [[ "${EUID}" -eq 0 ]]; then
    die "Do not run this script as root or with sudo. Run: ./setup.sh
  It will prompt for sudo only where it needs to install packages."
fi

if ! command -v apt-get &> /dev/null; then
    die "Expected an apt-based Ubuntu system. Found: $(. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-unknown}")"
fi

case "$(uname -m)" in
    x86_64)  GO_ARCH=amd64; MULTIARCH_DIR=x86_64-linux-gnu  ;;
    aarch64) GO_ARCH=arm64; MULTIARCH_DIR=aarch64-linux-gnu ;;
    *)       die "Unsupported architecture: $(uname -m). Expected x86_64 or aarch64." ;;
esac

echo "--- xdp-ebpf-mitigator environment setup ---"
info "Distro:   $(. /etc/os-release && echo "${PRETTY_NAME}")"
info "Kernel:   $(uname -r) ($(uname -m))"

# Keep sudo warm so the long apt step doesn't stall on a password prompt.
sudo -v

# ── 1. System dependencies ────────────────────────────────────────────────

step "Installing system dependencies"

# Wait out unattended-upgrades, which holds the dpkg lock on a fresh VM.
if sudo fuser /var/lib/dpkg/lock-frontend &>/dev/null; then
    info "Waiting for another package manager to finish..."
    while sudo fuser /var/lib/dpkg/lock-frontend &>/dev/null; do sleep 3; done
fi

sudo apt-get update -qq

# build-essential/make        — cgo and the Makefile
# clang, llvm                 — compile restricted C to BPF bytecode (-target bpf)
# libbpf-dev, libelf-dev,
#   zlib1g-dev, pkg-config    — ELF/BTF handling for the loader
# linux-headers-$(uname -r)   — kernel headers for the BPF C includes
# iproute2                    — ip link / ip netns; also `ip link set ... xdp`
# ethtool                     — check driver XDP support and ring config
# strace, tcpdump             — debugging the control plane and the wire
sudo apt-get install -y \
    build-essential \
    make \
    clang \
    llvm \
    libbpf-dev \
    libelf-dev \
    zlib1g-dev \
    pkg-config \
    "linux-headers-$(uname -r)" \
    iproute2 \
    ethtool \
    strace \
    tcpdump

# True only when apt can actually install $1. `apt-cache show` is not a valid
# test here: it exits 0 for referenced-but-uninstallable packages, so check
# that policy reports a real candidate version instead.
apt_has_candidate() {
    [[ "$(apt-cache policy "$1" 2>/dev/null | awk '/Candidate:/{print $2}')" != "(none)" ]] \
        && apt-cache policy "$1" 2>/dev/null | grep -q 'Candidate:'
}

# bpftool's packaging varies by release: some ship a standalone package, others
# only bundle it in the versioned linux-tools package. Try both rather than
# assuming. It is not required to build, so a miss warns instead of failing.
step "Installing bpftool"
if command -v bpftool &> /dev/null; then
    info "Already present: $(bpftool version 2>/dev/null | head -1)"
elif apt_has_candidate bpftool && sudo apt-get install -y bpftool 2>/dev/null; then
    info "Installed the standalone bpftool package."
elif sudo apt-get install -y linux-tools-common "linux-tools-$(uname -r)" 2>/dev/null; then
    info "Installed via linux-tools-$(uname -r)."
else
    warn "Could not install bpftool for kernel $(uname -r). It is optional for the
         build, but needed to inspect loaded programs and generate vmlinux.h.
         Try: sudo apt-get install linux-tools-generic"
fi

# eBPF C includes <linux/types.h>, which pulls in <asm/types.h>. Ubuntu ships
# the arch-specific headers under /usr/include/$MULTIARCH_DIR/asm and expects
# the compiler to find them via the multiarch search path — clang with
# `-target bpf` does not, so it needs an explicit symlink or -I flag.
step "Checking eBPF C include path"
if [[ -e /usr/include/asm ]]; then
    info "/usr/include/asm already resolves — no fixup needed."
elif [[ -d "/usr/include/${MULTIARCH_DIR}/asm" ]]; then
    info "Linking /usr/include/asm -> /usr/include/${MULTIARCH_DIR}/asm"
    sudo ln -sfn "/usr/include/${MULTIARCH_DIR}/asm" /usr/include/asm
else
    warn "Could not find /usr/include/${MULTIARCH_DIR}/asm. If a BPF compile
         fails on a missing <asm/types.h>, add -I/usr/include/${MULTIARCH_DIR}
         to the clang invocation."
fi

# ── 2. Go toolchain ───────────────────────────────────────────────────────

step "Checking Go toolchain"

# Source of truth for the minimum version is go.mod, so this never drifts.
GO_REQUIRED="$(awk '/^go [0-9]/ {print $2; exit}' "${REPO_ROOT}/go.mod")"
[[ -n "${GO_REQUIRED}" ]] || die "Could not read the go directive from go.mod"

# Prefer a system Go already on PATH; fall back to a manual install location.
export PATH="${PATH}:/usr/local/go/bin"

go_current() {
    command -v go &> /dev/null || return 1
    go version | awk '{print $3}' | sed 's/^go//'
}

version_ok() {
    # True when $1 >= $2 under version sort.
    [[ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1)" == "$2" ]]
}

GO_HAVE="$(go_current || true)"

if [[ -n "${GO_HAVE}" ]] && version_ok "${GO_HAVE}" "${GO_REQUIRED}"; then
    info "Go ${GO_HAVE} satisfies the go.mod minimum of ${GO_REQUIRED}."
else
    if [[ -n "${GO_HAVE}" ]]; then
        info "Go ${GO_HAVE} is older than the required ${GO_REQUIRED} — upgrading."
    else
        info "Go not found — installing ${GO_REQUIRED}."
    fi

    # A distro-packaged Go earlier in PATH will keep winning after we install
    # into /usr/local/go, which looks like the upgrade silently did nothing.
    if [[ -n "${GO_HAVE}" && "$(command -v go)" != "/usr/local/go/bin/go" ]]; then
        warn "An existing Go at $(command -v go) sits earlier in PATH and will
             shadow /usr/local/go/bin/go. Remove it if the version printed
             below is still wrong: sudo apt-get remove golang-go"
    fi

    GO_TARBALL="go${GO_REQUIRED}.linux-${GO_ARCH}.tar.gz"
    info "Downloading ${GO_TARBALL}..."
    curl -fsSL "https://go.dev/dl/${GO_TARBALL}" -o "/tmp/${GO_TARBALL}"

    sudo rm -rf /usr/local/go
    sudo tar -C /usr/local -xzf "/tmp/${GO_TARBALL}"
    rm -f "/tmp/${GO_TARBALL}"

    # Persist PATH for future interactive shells, once.
    if ! grep -qsF '/usr/local/go/bin' "${HOME}/.profile" "${HOME}/.bashrc"; then
        echo 'export PATH=$PATH:/usr/local/go/bin' >> "${HOME}/.profile"
        info "Added /usr/local/go/bin to PATH in ~/.profile (new shells only)."
    fi

    hash -r
    info "Installed $(go version)"
fi

# ── 3. Go modules ─────────────────────────────────────────────────────────

step "Fetching Go modules"
cd "${REPO_ROOT}"
go mod download
info "Module cache: $(go env GOMODCACHE)"

# ── 4. Kernel capability check ────────────────────────────────────────────

step "Verifying kernel eBPF/XDP support"

KCONFIG="/boot/config-$(uname -r)"
if [[ -r "${KCONFIG}" ]]; then
    for opt in CONFIG_BPF_SYSCALL CONFIG_XDP_SOCKETS CONFIG_DEBUG_INFO_BTF; do
        if grep -q "^${opt}=y" "${KCONFIG}"; then
            info "${opt}=y"
        else
            warn "${opt} is not enabled in ${KCONFIG}"
        fi
    done
else
    warn "Cannot read ${KCONFIG}; skipping kernel config check."
fi

# In a VM, virtio-net has no native XDP path — programs attach in generic
# (skb) mode. That is functionally correct and fine for development, just
# slower than a driver-native attach on the bare-metal box.
# systemd-detect-virt prints "none" *and* exits 1 on bare metal, so swallow
# the status and fall back only when the command is missing entirely.
VIRT="$(systemd-detect-virt 2>/dev/null || true)"
VIRT="${VIRT:-none}"
if [[ "${VIRT}" != "none" ]]; then
    info "Virtualized (${VIRT}) — expect generic/skb-mode XDP, not driver-native."
else
    info "Bare metal — driver-native XDP available if the NIC driver supports it."
fi

# ── Done ──────────────────────────────────────────────────────────────────

echo
echo "--- Setup complete ---"
echo
echo "  make build"
echo "  sudo ./mitigator-ctl   # Netlink/namespace ops need CAP_NET_ADMIN"
echo "  make test              # also requires root"
echo
# This script exported /usr/local/go/bin itself; a new login shell only picks
# it up once ~/.profile is re-sourced.
if [[ "$(command -v go)" == "/usr/local/go/bin/go" ]]; then
    echo "  If 'go' is not found in a new shell: source ~/.profile"
    echo
fi
