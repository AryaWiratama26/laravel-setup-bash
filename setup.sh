#!/usr/bin/env bash

set -o pipefail

GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
CYAN='\033[36m'
BOLD='\033[1m'
NC='\033[0m'

ok()    { printf "${GREEN}✔${NC} %s\n" "$1"; }
warn()  { printf "${YELLOW}!${NC} %s\n" "$1"; }
err()   { printf "${RED}✘${NC} %s\n" "$1"; }
info()  { printf "${CYAN}›${NC} %s\n" "$1"; }
head1() { printf "\n${BOLD}%s${NC}\n" "$1"; }

die() { err "$1"; exit 1; }

ask() {
    local __var="$1" __prompt="$2" __default="${3:-}" __reply
    if [[ -n "$__default" ]]; then
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

ask_yn() {
    local __var="$1" __prompt="$2" __reply
    while true; do
        printf "%s [y/n]: " "$__prompt"
        IFS= read -r __reply || { printf "\n"; exit 130; }
        case "${__reply,,}" in
            y|yes) printf -v "$__var" '%s' "yes"; return ;;
            n|no)  printf -v "$__var" '%s' "no"; return ;;
            *)     warn "Please answer y or n." ;;
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
    if (( status == 0 )); then
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
        [[ -f "$file" ]] || continue
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

# Preflight
head1 "Preflight checks"

require_cmd php "php is required but not installed."
require_cmd composer "Composer is required but not installed. See https://getcomposer.org"

php_version="$(php -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;')"
if ! php -r 'exit(PHP_VERSION_ID >= 80200 ? 0 : 1);'; then
    warn "PHP $php_version detected. Laravel 11+ requires PHP >= 8.2."
fi
ok "php $php_version"
ok "$(composer --version 2>/dev/null | head -n1)"

# Project
head1 "Laravel project"

laravel_name=""
ask laravel_name "Name of Laravel Project" "my_app_default"

if [[ ! "$laravel_name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    die "Invalid project name '$laravel_name'. Use letters, numbers, dot, dash or underscore (no spaces)."
fi

if [[ -e "$laravel_name" ]]; then
    overwrite=""
    ask_yn overwrite "Directory '$laravel_name' already exists. Continue anyway?"
    [[ "$overwrite" == "yes" ]] || die "Aborted."
fi

laravel_version=""
ask laravel_version "Version of Laravel Project (11/12/13)" "12"
[[ "$laravel_version" =~ ^[0-9]+$ ]] || die "Version must be a number."
(( laravel_version >= 11 )) || die "Only Laravel 11, 12 or 13 are supported."

app_name="${laravel_name//[_-]/ }"
app_name="${app_name^}"

ok "Project : $app_name"
ok "Version : Laravel $laravel_version"

# Create
head1 "Creating project"

run_step "composer create-project laravel/laravel:^$laravel_version $laravel_name" \
    composer create-project "laravel/laravel:^${laravel_version}" "$laravel_name" --no-interaction \
    || die "composer create-project failed. Nothing to clean up - fix the error and re-run."

cd "$laravel_name" || die "Failed to enter project directory."
[[ -f .env ]] || { cp .env.example .env; ok ".env created from .env.example"; }

# Database
head1 "Database"

db_option=""
while true; do
    info "1. MySQL   2. PostgreSQL   3. SQLite"
    ask db_option "Choose database" "1"
    case "$db_option" in
        1|2|3) break ;;
        *) warn "Please choose 1, 2 or 3." ;;
    esac
done

db_name="${laravel_name//[^A-Za-z0-9_]/_}"

case "$db_option" in
    1)
        check_php_extension pdo_mysql
        db_host="127.0.0.1"; db_port="3306"
        ask db_host "Database host" "$db_host"
        ask db_port "Database port" "$db_port"
        ask db_name "Database name" "$db_name"
        ask db_user "Database user" "root"
        ask db_password "Database password" ""
        db_password_quoted="$(quote_env "$db_password")"

        set_env APP_NAME "$(quote_env "$app_name")"
        set_env DB_CONNECTION mysql
        set_env DB_HOST "$(quote_env "$db_host")"
        set_env DB_PORT "$(quote_env "$db_port")"
        set_env DB_DATABASE "$(quote_env "$db_name")"
        set_env DB_USERNAME "$(quote_env "$db_user")"
        set_env DB_PASSWORD "$db_password_quoted"
        ok "MySQL configured ($db_user@$db_host:$db_port/$db_name)"

        create_db=""
        if command -v mysql >/dev/null 2>&1; then
            ask_yn create_db "Create the database if it does not exist?"
            if [[ "$create_db" == "yes" ]]; then
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
        db_host="127.0.0.1"; db_port="5432"
        ask db_host "Database host" "$db_host"
        ask db_port "Database port" "$db_port"
        ask db_name "Database name" "$db_name"
        ask db_user "Database user" "postgres"
        ask db_password "Database password" ""
        db_password_quoted="$(quote_env "$db_password")"

        set_env APP_NAME "$(quote_env "$app_name")"
        set_env DB_CONNECTION pgsql
        set_env DB_HOST "$(quote_env "$db_host")"
        set_env DB_PORT "$(quote_env "$db_port")"
        set_env DB_DATABASE "$(quote_env "$db_name")"
        set_env DB_USERNAME "$(quote_env "$db_user")"
        set_env DB_PASSWORD "$db_password_quoted"
        ok "PostgreSQL configured ($db_user@$db_host:$db_port/$db_name)"

        create_db=""
        if command -v psql >/dev/null 2>&1; then
            ask_yn create_db "Create the database if it does not exist?"
            if [[ "$create_db" == "yes" ]]; then
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

# Laravel setup
head1 "Laravel setup"

run_step "php artisan key:generate" php artisan key:generate --force --no-interaction
run_step "php artisan storage:link" php artisan storage:link --force
run_step "php artisan migrate" php artisan migrate --force

if [[ -f package.json ]]; then
    if ! command -v npm >/dev/null 2>&1; then
        warn "npm not found - skipping frontend dependencies."
    else
        if [[ -f pnpm-lock.yaml ]] && command -v pnpm >/dev/null 2>&1; then
            run_step "pnpm install" pnpm install
        elif [[ -f yarn.lock ]] && command -v yarn >/dev/null 2>&1; then
            run_step "yarn install" yarn install
        else
            run_step "npm install" npm install --no-audit --no-fund
        fi
        run_step "npm run build" npm run build
    fi
fi

if [[ -d .git ]]; then
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
