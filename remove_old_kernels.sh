#!/bin/bash
#
# remove_old_kernels.sh
# Safely remove old kernels on Oracle Linux 9.x, keeping only the newest N
# versions (default: 2). The running kernel is always protected.
# Also handles kernel-uek packages alongside regular kernel packages.
# Integrates with crash/travamento audit settings.
#
# Usage: see --help

set -euo pipefail

KEEP=2
DRY_RUN=0
SET_LIMIT=0
CLEAN=0
INCLUDE_UKE=0   # 1=also consider kernel-uek, 0=only regular kernel (default)
LIST_ONLY=0     # 1=only list, don't propose removal

log()  { printf '%s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<'EOF'
Usage: remove_old_kernels.sh [options]

  -k, --keep N           How many total kernels to keep (default: 2)
  -n, --dry-run          Only show what would be removed, change nothing
  -c, --set-limit        Also set installonly_limit=N in /etc/dnf/dnf.conf
  -u, --include-uek      Also include kernel-uek packages in the count
  -U, --exclude-uek      Only consider regular kernel packages (default)
      --clean             Run 'dnf clean all' after a successful removal
      --list-only         List kernels without proposing removal
  -h, --help              Show this help

The newest N kernels are kept across both regular and UEK kernels (if
included). The running kernel is always protected — if it is not among the
newest N, the oldest of those N is dropped instead so the system stays
bootable.  Old kernels are a common cause of boot issues and
travamentos; removing them frees disk space and reduces maintenance overhead.
EOF
}

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
while (( $# )); do
    case "$1" in
        -k|--keep)           KEEP="${2:?--keep requires a number}"; shift 2 ;;
        -k=*|--keep=*)       KEEP="${1#*=}"; shift ;;
        -n|--dry-run)        DRY_RUN=1; shift ;;
        -c|--set-limit)      SET_LIMIT=1; shift ;;
        -u|--include-uek)    INCLUDE_UKE=1; shift ;;
        -U|--exclude-uek)    INCLUDE_UKE=0; shift ;;
        --clean)             CLEAN=1; shift ;;
        --list-only)         LIST_ONLY=1; shift ;;
        -h|--help)           usage; exit 0 ;;
        *)                   usage >&2; die "unknown option: $1" ;;
    esac
done

[[ "$KEEP" =~ ^[1-9][0-9]*$ ]] || die "--keep must be a positive integer (got '$KEEP')"

# ---------------------------------------------------------------------------
# Determine which kernel packages to query
# ---------------------------------------------------------------------------
if (( INCLUDE_UKE )); then
    PKG_BASES=(kernel kernel-uek)
else
    PKG_BASES=(kernel)
fi

# ---------------------------------------------------------------------------
# Gather installed kernel versions from rpm
# Stores:  installed[0..n-1] = "VERSION-RELEASE.ARCH" sorted newest last
# ---------------------------------------------------------------------------
running="$(uname -r)"

read_versions() {  # $1 = package name pattern (e.g. "kernel" or "kernel-uek")
    # Only output versions if package is installed; rpm -q returns non-zero if not found
    if rpm -q "$1" >/dev/null 2>&1; then
        rpm -q "$1" --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' | sort -Vu
    fi
}

# Collect versions from all requested package bases
mapfile -t installed < <(for pb in "${PKG_BASES[@]}"; do
    read_versions "$pb"
done | sort -Vu)

(( ${#installed[@]} )) || die "no installed kernel packages found"

# Helper: check if a version string matches the running kernel
is_running() { [[ "$1" == "$running" ]]; }

log "=== Current running kernel: $running ==="
log "Installed kernels (${#installed[@]}):"
printf '  %s\n' "${installed[@]}"
log

n=${#installed[@]}
if (( n <= KEEP )); then
    log "Only $n kernel(s) installed and keep=$KEEP -> nothing to do."
    exit 0
fi

# ---------------------------------------------------------------------------
# Decide which versions to keep: the newest KEEP, forcing the running kernel in
# ---------------------------------------------------------------------------
declare -A keep=()
# Initially mark the newest KEEP versions from the sorted list
for (( i = n - KEEP; i < n; i++ )); do
    keep["${installed[i]}"]=1
done

# If the running kernel is not already among the kept versions, replace the
# oldest of the kept ones with the running kernel so the system stays bootable.
if ! [[ -v keep["$running"] ]]; then
    running_installed=0
    for v in "${installed[@]}"; do
        is_running "$v" && running_installed=1
    done
    if (( running_installed )); then
        oldest_kept="${installed[n-KEEP]}"
        unset "keep[$oldest_kept]"
        keep["$running"]=1
        warn "running kernel $running is not among the newest $KEEP;"
        warn "keeping it instead of $oldest_kept so the system stays bootable."
    else
        warn "running kernel $running is not an installed kernel package; it will not be touched."
    fi
fi

# ---------------------------------------------------------------------------
# Versions to remove = installed - kept
# ---------------------------------------------------------------------------
remove_versions=()
for v in "${installed[@]}"; do
    [[ -v keep["$v"] ]] || remove_versions+=("$v")
done

if (( ${#remove_versions[@]} == 0 )); then
    log "Nothing to remove."
    exit 0
fi

# ---------------------------------------------------------------------------
# Build the full package name list for the versions to remove
# ---------------------------------------------------------------------------
mapfile -t all_pkgs < <(rpm -qa --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n')

specs=()
for v in "${remove_versions[@]}"; do
    for p in "${all_pkgs[@]}"; do
        # Match: package name starts with kernel- or kernel, and version-release.arch matches
        if [[ "$p" == kernel* || "$p" == kernel-uek* ]]; then
            if [[ "$p" == kernel-uek-* ]]; then
                pkg_version="${p#kernel-uek-}"
            else
                pkg_version="${p#kernel-}"
            fi
            if [[ "$pkg_version" == "$v" ]]; then
                specs+=("$p")
            fi
        fi
    done
done

(( ${#specs[@]} )) || die "no packages matched the old versions (unexpected)"

# ---------------------------------------------------------------------------
# Summary / Propose removal
# ---------------------------------------------------------------------------
log "Keeping:"
for v in "${installed[@]}"; do
    [[ -v keep["$v"] ]] && log "  $v"
done
log "Removing:"
printf '  %s\n' "${remove_versions[@]}"
log

if (( DRY_RUN )); then
    log "Dry run: nothing was removed."
    exit 0
fi

if (( LIST_ONLY )); then
    log "List-only mode: no packages will be removed."
    exit 0
fi

(( EUID == 0 )) || command -v sudo >/dev/null || die "need root or sudo to remove packages"

# ---------------------------------------------------------------------------
# Remove
# ---------------------------------------------------------------------------
log "Removing packages:"
sudo dnf remove -y "${specs[@]}"

# ---------------------------------------------------------------------------
# Optional: make dnf keep only $KEEP kernels automatically from now on
# ---------------------------------------------------------------------------
if (( SET_LIMIT )); then
    set_dnf_opt() {  # $1 = option, $2 = value
        if grep -qE "^[[:space:]]*$1=" /etc/dnf/dnf.conf 2>/dev/null; then
            sudo sed -i -E "s/^([[:space:]]*$1=).*/\1$2/" /etc/dnf/dnf.conf
        else
            grep -q '^\[main\]' /etc/dnf/dnf.conf 2>/dev/null || printf '\n[main]\n' | sudo tee -a /etc/dnf/dnf.conf >/dev/null
            printf '%s=%s\n' "$1" "$2" | sudo tee -a /etc/dnf/dnf.conf >/dev/null
        fi
    }
    set_dnf_opt installonly_limit "$KEEP"
    set_dnf_opt protect_running_kernel true
    log "dnf.conf updated: installonly_limit=$KEEP, protect_running_kernel=true"
fi

if (( CLEAN )); then
    log
    log "Cleaning cached packages..."
    sudo dnf clean all
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
mapfile -t remaining < <(for pb in "${PKG_BASES[@]}"; do
    read_versions "$pb"
done | sort -Vu)
log
log "Done! Kernels now installed (${#remaining[@]}):"
printf '  %s\n' "${remaining[@]}"

if (( ${#remaining[@]} > KEEP )); then
    warn "more than $KEEP kernels still installed - check the output above"
fi

# ---------------------------------------------------------------------------
# Post-removal: check for crashkernel/travamento related settings
# ---------------------------------------------------------------------------
if (( DRY_RUN == 0 && CLEAN == 0 )); then
    say()  { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
    ok()   { printf '   \033[1;32mOK\033[0m  %s\n' "$*"; }
    warn() { printf '   \033[1;33mAVISO\033[0m  %s\n' "$*" >&2; }

    say "Checking crashkernel/kdump configuration..."
    if grep -q 'crashkernel=' /proc/cmdline; then
        if systemctl is-active --quiet kdump 2>/dev/null; then
            ok "kdump is active - crashkernel will be preserved for crash recovery"
        else
            warn "crashkernel is in cmdline but kdump is NOT active"
            warn "Consider removing crashkernel parameter if kdump is not used"
            warn "  This can free ~448 MiB RAM (current: $(tr ' ' '\n' < /proc/cmdline | grep '^crashkernel=' | head -1))"
        fi
    else
        ok "no crashkernel parameter in kernel cmdline"
    fi

    say "Checking installonly_limit..."
    current_limit="$(grep -oP '^installonly_limit=\K[0-9]+' /etc/dnf/dnf.conf 2>/dev/null || echo 'not set')"
    if [[ "$current_limit" != "$KEEP" ]]; then
        log "installonly_limit is currently: $current_limit (recommended: $KEEP)"
        log "Run: sudo remove_old_kernels.sh --set-limit --keep $KEEP"
    else
        ok "installonly_limit=$KEEP is correctly set"
    fi
fi