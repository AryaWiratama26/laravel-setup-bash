#!/usr/bin/env bash

if [ -z "${BASH_VERSION:-}" ]; then
    echo "This installer must be run with Bash, not sh." >&2
    echo "Try:  curl -sSL <url> | bash -s -- [options]" >&2
    exit 1
fi

set -eu

VERSION="1.0.0"
DEFAULT_BASE_URL="https://aryawiratama.web.id"
BASE_URL="${LARAVEL_SETUP_URL:-$DEFAULT_BASE_URL}"
VERIFY="yes"
DRY_RUN="no"
ALLOW_ROOT="no"

GREEN=$'\033[32m'
YELLOW=$'\033[33m'
RED=$'\033[31m'
CYAN=$'\033[36m'
BOLD=$'\033[1m'
NC=$'\033[0m'

ok()   { printf "${GREEN}✔${NC} %s\n" "$1"; }
warn() { printf "${YELLOW}!${NC} %s\n" "$1"; }
err()  { printf "${RED}✘${NC} %s\n" "$1"; }
info() { printf "${CYAN}›${NC} %s\n" "$1"; }
die()  { err "$1"; exit 1; }

ARGS=()

usage() {
    cat <<EOF
${BOLD}laravel-setup-bash installer${NC} $VERSION

Downloads the latest setup.sh and runs it in an interactive terminal.

${BOLD}USAGE${NC}
  curl -sSL $DEFAULT_BASE_URL/install.sh | bash
  curl -sSL $DEFAULT_BASE_URL/install.sh | bash -s -- [options]

${BOLD}INSTALLER OPTIONS${NC}
  -n, --dry-run        Download setup.sh, print it, and exit without running.
      --base-url=URL   Fetch setup.sh from URL instead of $DEFAULT_BASE_URL
      --no-verify      Skip the SHA-256 integrity check.
      --allow-root     Run even when invoked with sudo (not recommended).
  -h, --help           Show this help.
  -V, --version        Show the installer version.

${BOLD}SETUP OPTIONS${NC} (forwarded to setup.sh)
  --name=NAME          Project directory name.
  --version=VERSION    Laravel major version (11, 12, or 13).
  --db=ENGINE          mysql | pgsql | sqlite
  --db-host=HOST       Database host.
  --db-port=PORT       Database port.
  --db-name=NAME       Database name.
  --db-user=USER       Database user.
  --db-password=PASS   Database password.
  --dir=PATH           Directory to create the project in (default: current).
  --seed               Run "php artisan db:seed" after migrating.
  --no-build           Skip installing and building front-end assets.
  -y, --yes            Accept every default, never prompt. Requires the
                       options above for any value that has no default.
  -h, --help           Show setup.sh help.

${BOLD}EXAMPLES${NC}
  ${CYAN}curl -sSL $DEFAULT_BASE_URL/install.sh | bash${NC}
  ${CYAN}curl -sSL $DEFAULT_BASE_URL/install.sh | bash -s -- --name=shop --db=sqlite${NC}
  ${CYAN}curl -sSL $DEFAULT_BASE_URL/install.sh | bash -s -- --name=shop --db=mysql --yes${NC}
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        -V|--version)
            echo "laravel-setup-bash installer $VERSION"
            exit 0
            ;;
        -n|--dry-run)
            DRY_RUN="yes"
            ;;
        --base-url=*)
            BASE_URL="${1#*=}"
            ;;
        --no-verify)
            VERIFY="no"
            ;;
        --allow-root)
            ALLOW_ROOT="yes"
            ;;
        --)
            shift
            while [ "$#" -gt 0 ]; do
                ARGS[${#ARGS[@]}]="$1"
                shift
            done
            break
            ;;
        *)
            ARGS[${#ARGS[@]}]="$1"
            ;;
    esac
    shift
done

if [ "$ALLOW_ROOT" != "yes" ] && [ "$(id -u)" = "0" ]; then
    die "Refusing to run as root. Project files would be owned by root.
    Re-run without sudo, or pass --allow-root if you know what you are doing."
fi

if [ -z "${BASE_URL%/}" ]; then
    die "Base URL is empty."
fi

info "laravel-setup-bash installer $VERSION"
info "Source: $BASE_URL"

case "$BASE_URL" in
    http://*|https://*)
        SCRIPT_URL="$BASE_URL/setup.sh?v=$VERSION"
        CHECKSUM_URL="$BASE_URL/setup.sh.sha256"
        ;;
    *)
        SCRIPT_URL="$BASE_URL/setup.sh"
        CHECKSUM_URL="$BASE_URL/setup.sh.sha256"
        ;;
esac

WORK_DIR="$(mktemp -d 2>/dev/null || mktemp -d -t laravel-setup)"
TARGET="$WORK_DIR/setup.sh"
CHECKSUM_FILE="$WORK_DIR/setup.sh.sha256"

cleanup() {
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT TERM

download() {
    url="$1"
    dest="$2"
    found="no"
    if command -v curl >/dev/null 2>&1; then
        found="yes"
        if curl -fsSL --retry 3 --connect-timeout 20 -o "$dest" "$url" 2>/dev/null; then
            return 0
        fi
    fi
    if command -v wget >/dev/null 2>&1; then
        found="yes"
        if wget -q -O "$dest" "$url" 2>/dev/null; then
            return 0
        fi
    fi
    if [ "$found" = "no" ]; then
        err "Neither curl nor wget is available."
        exit 1
    fi
    return 1
}

sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    elif command -v openssl >/dev/null 2>&1; then
        openssl dgst -sha256 "$1" | awk '{print $NF}'
    else
        return 1
    fi
}

have_tty() {
    ( exec 3<>/dev/tty ) >/dev/null 2>&1 || return 1
    return 0
}

has_non_interactive_flag() {
    for arg in ${ARGS[@]+"${ARGS[@]}"}; do
        if [ "$arg" = "-y" ] || [ "$arg" = "--yes" ]; then
            return 0
        fi
    done
    return 1
}

info "Downloading setup.sh"
if ! download "$SCRIPT_URL" "$TARGET"; then
    die "Could not download $SCRIPT_URL
    Check your connection, or set LARAVEL_SETUP_URL to an alternative source."
fi

[ -s "$TARGET" ] || die "The downloaded setup.sh is empty."

if ! head -n 1 "$TARGET" | grep -q '^#!.*bash'; then
    die "The downloaded file is not a Bash script.
    Refusing to execute it. Check the URL, or run the installer with --dry-run."
fi
ok "setup.sh downloaded ($(wc -c <"$TARGET" | tr -d ' ') bytes)"

if [ "$VERIFY" = "yes" ]; then
    if download "$CHECKSUM_URL" "$CHECKSUM_FILE" && [ -s "$CHECKSUM_FILE" ]; then
        expected="$(awk '{print $1; exit}' "$CHECKSUM_FILE")"
        actual="$(sha256_of "$TARGET" || echo "")"
        if [ -z "$actual" ]; then
            warn "No SHA-256 tool found - skipping the integrity check."
        elif [ "$expected" = "$actual" ]; then
            ok "Checksum verified"
        else
            die "Checksum mismatch for setup.sh.
    expected: $expected
    actual:   $actual
    The download was modified in transit. Aborting."
        fi
    else
        warn "No setup.sh.sha256 published - skipping the integrity check."
    fi
else
    warn "Integrity check skipped (--no-verify)."
fi

if [ "$DRY_RUN" = "yes" ]; then
    echo
    warn "Dry run: setup.sh was NOT executed. Its contents follow."
    echo
    cat "$TARGET"
    echo
    ok "Dry run finished. Nothing was installed."
    exit 0
fi

echo

if have_tty; then
    bash "$TARGET" ${ARGS[@]+"${ARGS[@]}"} </dev/tty || status=$?
elif has_non_interactive_flag; then
    bash "$TARGET" ${ARGS[@]+"${ARGS[@]}"} || status=$?
else
    cleanup
    die "No interactive terminal available.
    This happens in CI, cron, or over SSH without a TTY. Either pass the
    options and --yes, for example:

      curl -sSL $DEFAULT_BASE_URL/install.sh | bash -s -- --name=my_app --db=sqlite --yes

    or download the script and run it from a real terminal:

      curl -fsSL $DEFAULT_BASE_URL/setup.sh -o setup.sh && bash setup.sh"
fi

cleanup
exit "${status:-0}"
