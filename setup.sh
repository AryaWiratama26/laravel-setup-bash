#!/usr/bin/env bash

set -o pipefail

VERSION="1.0.0"

GREEN=$'\033[32m'
YELLOW=$'\033[33m'
RED=$'\033[31m'
CYAN=$'\033[36m'
BOLD=$'\033[1m'
NC=$'\033[0m'

ok()    { printf "${GREEN}✔${NC} %s\n" "$1"; }
warn()  { printf "${YELLOW}!${NC} %s\n" "$1"; }
err()   { printf "${RED}✘${NC} %s\n" "$1"; }
info()  { printf "${CYAN}›${NC} %s\n" "$1"; }
head1() { printf "\n${BOLD}%s${NC}\n" "$1"; }

die() { err "$1"; exit 1; }

opt_name=""
opt_version=""
opt_db=""
opt_db_host=""
opt_db_port=""
opt_db_name=""
opt_db_user=""
opt_db_password=""
opt_dir=""
opt_yes="no"
opt_dry_run="no"
opt_seed="no"
opt_no_build="no"

usage() {
    cat <<EOF
${BOLD}setup.sh${NC} - scaffold a Laravel project interactively

${BOLD}USAGE${NC}
  bash setup.sh [options]

  ${BOLD}Interactive (default)${NC}
    bash setup.sh

  ${BOLD}Non-interactive (CI, containers)${NC}
    bash setup.sh --name=shop --version=12 --db=sqlite --yes

${BOLD}OPTIONS${NC}
  --name=NAME          Project directory name (default: my_app_default)
  --version=VERSION    Laravel major version: 11, 12, or 13 (default: 12)
  --db=ENGINE          mysql | pgsql | sqlite (default: prompt, else mysql)
  --db-host=HOST       Database host (default: 127.0.0.1)
  --db-port=PORT       Database port (default: 3306 / 5432)
  --db-name=NAME       Database name (default: derived from --name)
  --db-user=USER       Database user (default: root / postgres)
  --db-password=PASS   Database password (default: empty)
  --dir=PATH           Create the project in PATH (default: current directory)
  --seed               Run "php artisan db:seed" after migrating
  --no-build           Skip installing and building front-end assets
  -n, --dry-run        Print the resolved plan and exit
  -y, --yes            Accept defaults, never prompt
  -h, --help           Show this help
  -V, --version        Show the script version
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --name=*)          opt_name="${1#*=}" ;;
        --version=*)       opt_version="${1#*=}" ;;
        --db=*)            opt_db="${1#*=}" ;;
        --db-host=*)       opt_db_host="${1#*=}" ;;
        --db-port=*)       opt_db_port="${1#*=}" ;;
        --db-name=*)       opt_db_name="${1#*=}" ;;
        --db-user=*)       opt_db_user="${1#*=}" ;;
        --db-password=*)   opt_db_password="${1#*=}" ;;
        --dir=*)           opt_dir="${1#*=}" ;;
        --seed)            opt_seed="yes" ;;
        --no-build)        opt_no_build="yes" ;;
        -n|--dry-run)      opt_dry_run="yes" ;;
        -y|--yes)          opt_yes="yes" ;;
        -h|--help)         usage; exit 0 ;;
        -V|--version)      echo "laravel-setup-bash $VERSION"; exit 0 ;;
        -*)                die "Unknown option: $1 (run with --help)" ;;
        *)                 die "Unexpected argument: $1 (run with --help)" ;;
    esac
    shift
done

ask() {
    local __var="$1" __prompt="$2" __default="${3:-}" __reply
    if [ -n "$__default" ]; then
        printf "%s [%s]: " "$__prompt" "$__default"
    else
        printf "%s: " "$__prompt"
    fi
    if ! IFS= read -r __reply; then
        printf "\n"
        exit 130
    fi
    printf -v "$__var" '%s' "${__reply:-$__default}"
}

prompt_var() {
    local provided="$1" __var="$2" label="$3" default="${4:-}"
    if [ -n "$provided" ]; then
        printf -v "$__var" '%s' "$provided"
        ok "$label: ${!__var} (from option)"
        return 0
    fi
    if [ "$opt_yes" = "yes" ]; then
        printf -v "$__var" '%s' "$default"
        return 0
    fi
    ask "$__var" "$label" "$default"
}

ask_yn() {
    local __var="$1" __prompt="$2" __reply
    if [ "$opt_yes" = "yes" ]; then
        printf -v "$__var" '%s' "yes"
        return 0
    fi
    while true; do
        printf "%s [y/n]: " "$__prompt"
        if ! IFS= read -r __reply; then
            printf "\n"
            exit 130
        fi
        case "$__reply" in
            [yY]|[yY][eE][sS]) printf -v "$__var" '%s' "yes"; return 0 ;;
            [nN]|[nN][oO])     printf -v "$__var" '%s' "no";  return 0 ;;
            *) warn "Please answer y or n." ;;
        esac
    done
}

run_step() {
    local label="$1"; shift
    local out status
    out="$(mktemp)"
    ("$@") >"$out" 2>&1 &
    local pid=$!
    printf "${CYAN}…${NC} %s" "$label"
    while kill -0 "$pid" 2>/dev/null; do
        printf "."
        sleep 0.3
    done
    wait "$pid"; status=$?
    printf "\r\033[K"
    if [ "$status" -eq 0 ]; then
        ok "$label"
    else
        warn "$label failed"
        sed 's/^/    /' "$out"
    fi
    rm -f "$out"
    return "$status"
}

quote_env() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//\$/\\\$}"
    printf '"%s"' "$value"
}

set_env() {
    local key="$1" value="$2" file tmp
    for file in .env .env.example; do
        [ -f "$file" ] || continue
        if grep -qE "^[[:space:]]*#?[[:space:]]*${key}=" "$file"; then
            tmp="$(mktemp)"
            ENV_KEY="$key" ENV_VALUE="$value" awk '
                BEGIN { k = ENVIRON["ENV_KEY"]; v = ENVIRON["ENV_VALUE"]; seen = 0 }
                $0 ~ "^[[:space:]]*#?[[:space:]]*" k "=" {
                    if (seen == 0) { print k "=" v; seen = 1 }
                    next
                }
                { print }
            ' "$file" > "$tmp" && cat "$tmp" > "$file"
            rm -f "$tmp"
        else
            printf '%s=%s\n' "$key" "$value" >> "$file"
        fi
    done
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "$2"
}

check_php_extension() {
    php -m 2>/dev/null | grep -qi "^${1}$" || die "PHP extension '${1}' is missing. Install it first (e.g. sudo apt install php${1#php_})."
}

target_dir="."
[ -n "$opt_dir" ] && target_dir="$opt_dir"

if [ "$opt_dry_run" = "yes" ]; then
    head1 "Dry run"
    printf "  Directory : %s\n" "$(cd "$target_dir" 2>/dev/null && pwd || echo "$target_dir (missing)")"
    printf "  Project   : %s\n" "${opt_name:-my_app_default (prompt)}"
    printf "  Version   : Laravel %s\n" "${opt_version:-12 (prompt)}"
    printf "  Database  : %s\n" "${opt_db:-prompt}"
    printf "  Build     : %s\n" "$([ "$opt_no_build" = "yes" ] && echo "skipped" || echo "npm/pnpm/yarn + build")"
    printf "  Seed      : %s\n" "$([ "$opt_seed" = "yes" ] && echo "yes" || echo "no")"
    printf "\n"
    ok "Dry run finished. Nothing was created."
    exit 0
fi

if [ -n "$opt_dir" ]; then
    [ -d "$opt_dir" ] || die "Target directory '$opt_dir' does not exist."
    cd "$opt_dir" || die "Could not change to '$opt_dir'."
    ok "Working in $(pwd)"
fi

head1 "Preflight checks"

require_cmd php "php is required but not installed."
require_cmd composer "Composer is required but not installed. See https://getcomposer.org"

php_version="$(php -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;')"
if ! php -r 'exit(PHP_VERSION_ID >= 80200 ? 0 : 1);'; then
    warn "PHP $php_version detected. Laravel 11+ requires PHP >= 8.2."
fi
ok "php $php_version"
ok "$(composer --version 2>/dev/null | head -n1)"

head1 "Laravel project"

prompt_var "$opt_name" laravel_name "Name of Laravel Project" "my_app_default"

if [ ! "$laravel_name" ]; then
    die "A project name is required. Pass --name=NAME or answer the prompt."
fi

if ! printf '%s' "$laravel_name" | grep -qE '^[A-Za-z0-9][A-Za-z0-9._-]*$'; then
    die "Invalid project name '$laravel_name'. Use letters, numbers, dot, dash or underscore (no spaces)."
fi

if [ -e "$laravel_name" ]; then
    confirm=""
    ask_yn confirm "Directory '$laravel_name' already exists. Continue anyway?"
    [ "$confirm" = "yes" ] || die "Aborted."
fi

prompt_var "$opt_version" laravel_version "Version of Laravel Project (11/12/13)" "12"

case "$laravel_version" in
    ''|*[!0-9]*) die "Version must be a number." ;;
esac
[ "$laravel_version" -ge 11 ] || die "Only Laravel 11, 12 or 13 are supported."

app_name="${laravel_name//[_-]/ }"
app_name="${app_name^}"

ok "Project : $app_name"
ok "Version : Laravel $laravel_version"

head1 "Creating project"

run_step "composer create-project laravel/laravel:^$laravel_version $laravel_name" \
    composer create-project "laravel/laravel:^${laravel_version}" "$laravel_name" --no-interaction \
    || die "composer create-project failed. Nothing to clean up - fix the error and re-run."

cd "$laravel_name" || die "Failed to enter project directory."
[ -f .env ] || { cp .env.example .env; ok ".env created from .env.example"; }

head1 "Database"

db_option=""
if [ -n "$opt_db" ]; then
    case "$opt_db" in
        1|mysql|MYSQL)                                 db_option=1; db_label="MySQL" ;;
        2|pgsql|pg|postgres|postgresql|PGSQL)          db_option=2; db_label="PostgreSQL" ;;
        3|sqlite|SQLITE)                               db_option=3; db_label="SQLite" ;;
        *) die "Unknown database '$opt_db'. Use mysql, pgsql, or sqlite." ;;
    esac
    ok "Database: $db_label (from option)"
else
    while true; do
        info "1. MySQL   2. PostgreSQL   3. SQLite"
        ask db_option "Choose database" "1"
        case "$db_option" in
            1|2|3) break ;;
            *) warn "Please choose 1, 2 or 3." ;;
        esac
    done
fi

db_name="${laravel_name//[^A-Za-z0-9_]/_}"

case "$db_option" in
    1)
        check_php_extension pdo_mysql
        prompt_var "$opt_db_host" db_host "Database host" "127.0.0.1"
        prompt_var "$opt_db_port" db_port "Database port" "3306"
        prompt_var "$opt_db_name" db_name "Database name" "$db_name"
        prompt_var "$opt_db_user" db_user "Database user" "root"
        prompt_var "$opt_db_password" db_password "Database password" ""

        set_env APP_NAME "$(quote_env "$app_name")"
        set_env DB_CONNECTION mysql
        set_env DB_HOST "$(quote_env "$db_host")"
        set_env DB_PORT "$(quote_env "$db_port")"
        set_env DB_DATABASE "$(quote_env "$db_name")"
        set_env DB_USERNAME "$(quote_env "$db_user")"
        set_env DB_PASSWORD "$(quote_env "$db_password")"
        ok "MySQL configured ($db_user@$db_host:$db_port/$db_name)"

        create_db=""
        if command -v mysql >/dev/null 2>&1; then
            ask_yn create_db "Create the database if it does not exist?"
            if [ "$create_db" = "yes" ]; then
                if MYSQL_PWD="$db_password" mysql -h "$db_host" -P "$db_port" -u "$db_user" \
                    -e "CREATE DATABASE IF NOT EXISTS \`${db_name}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"; then
                    ok "Database '$db_name' is ready"
                else
                    warn "Could not create database. Create it manually, then re-run migrations."
                fi
            fi
        else
            warn "mysql client not found - skipping automatic database creation."
        fi
        ;;
    2)
        check_php_extension pdo_pgsql
        prompt_var "$opt_db_host" db_host "Database host" "127.0.0.1"
        prompt_var "$opt_db_port" db_port "Database port" "5432"
        prompt_var "$opt_db_name" db_name "Database name" "$db_name"
        prompt_var "$opt_db_user" db_user "Database user" "postgres"
        prompt_var "$opt_db_password" db_password "Database password" ""

        set_env APP_NAME "$(quote_env "$app_name")"
        set_env DB_CONNECTION pgsql
        set_env DB_HOST "$(quote_env "$db_host")"
        set_env DB_PORT "$(quote_env "$db_port")"
        set_env DB_DATABASE "$(quote_env "$db_name")"
        set_env DB_USERNAME "$(quote_env "$db_user")"
        set_env DB_PASSWORD "$(quote_env "$db_password")"
        ok "PostgreSQL configured ($db_user@$db_host:$db_port/$db_name)"

        create_db=""
        if command -v psql >/dev/null 2>&1; then
            ask_yn create_db "Create the database if it does not exist?"
            if [ "$create_db" = "yes" ]; then
                if PGPASSWORD="$db_password" psql -h "$db_host" -p "$db_port" -U "$db_user" \
                    -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='${db_name}'" | grep -q 1; then
                    ok "Database '$db_name' already exists"
                elif PGPASSWORD="$db_password" createdb -h "$db_host" -p "$db_port" -U "$db_user" "$db_name"; then
                    ok "Database '$db_name' created"
                else
                    warn "Could not create database. Create it manually, then re-run migrations."
                fi
            fi
        else
            warn "psql client not found - skipping automatic database creation."
        fi
        ;;
    3)
        check_php_extension pdo_sqlite
        mkdir -p database
        : > database/database.sqlite

        set_env APP_NAME "$(quote_env "$app_name")"
        set_env DB_CONNECTION sqlite
        set_env DB_HOST ""
        set_env DB_PORT ""
        set_env DB_DATABASE database/database.sqlite
        set_env DB_USERNAME ""
        set_env DB_PASSWORD ""
        ok "SQLite configured (database/database.sqlite)"
        ;;
esac

head1 "Laravel setup"

run_step "php artisan key:generate" php artisan key:generate --force --no-interaction
run_step "php artisan storage:link" php artisan storage:link --force
run_step "php artisan migrate" php artisan migrate --force

if [ "$opt_seed" = "yes" ]; then
    run_step "php artisan db:seed" php artisan db:seed --force
fi

if [ "$opt_no_build" = "yes" ]; then
    warn "Front-end build skipped (--no-build)."
elif [ ! -f package.json ]; then
    info "No package.json - skipping front-end dependencies."
elif ! command -v npm >/dev/null 2>&1; then
    warn "npm not found - skipping frontend dependencies."
else
    if [ -f pnpm-lock.yaml ] && command -v pnpm >/dev/null 2>&1; then
        run_step "pnpm install" pnpm install
    elif [ -f yarn.lock ] && command -v yarn >/dev/null 2>&1; then
        run_step "yarn install" yarn install
    else
        run_step "npm install" npm install --no-audit --no-fund
    fi
    run_step "npm run build" npm run build
fi

if [ -d .git ]; then
    warn ".git already exists - skipping git init."
elif command -v git >/dev/null 2>&1; then
    run_step "git init" git init -q
fi

head1 "Done"
printf "Project ready. Next steps:\n\n"
printf "  cd %s\n" "$laravel_name"
printf "  php artisan serve\n\n"
printf "  Database  : %s\n" "$(grep -m1 '^DB_CONNECTION=' .env | cut -d= -f2-)"
printf "  Seeder    : php artisan db:seed\n"
printf "  Test      : php artisan test\n\n"
