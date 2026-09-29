<div align="center">

# Laravel Setup Bash

**An interactive Bash script that scaffolds a fully configured Laravel project in a single run.**

Create the project · Configure the database · Generate the app key · Run migrations · Build assets

[![Bash](https://img.shields.io/badge/bash-3.2%2B-blue.svg)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS-lightgrey.svg)](#requirements)

</div>

---

## Table of Contents

- [Quick Install](#quick-install)
- [Overview](#overview)
- [Features](#features)
- [Requirements](#requirements)
- [Usage](#usage)
  - [Interactive](#interactive)
  - [Non-interactive](#non-interactive)
  - [Running the script without the installer](#running-the-script-without-the-installer)
- [What the Script Does](#what-the-script-does)
- [Options](#options)
- [Database Support](#database-support)
- [Configuration](#configuration)
- [After Setup](#after-setup)
- [Security](#security)
- [Exit Codes and Troubleshooting](#exit-codes-and-troubleshooting)
- [Deploying on Vercel](#deploying-on-vercel)
- [Project Structure](#project-structure)
- [License](#license)

---

## Quick Install

```bash
curl -sSL https://aryawiratama.web.id/install.sh | bash
```

Inspect the script before running it:

```bash
curl -sSL https://aryawiratama.web.id/install.sh | bash -s -- --dry-run
```

Without installing anything. `install.sh` downloads `setup.sh` into a temporary directory, verifies it, and hands the terminal over to it — which is what makes the pipe safe.

---

## Overview

Bootstrapping a new Laravel application usually means repeating the same sequence of commands: create the project, edit `.env` by hand, paste database credentials, generate an app key, run migrations, install front-end dependencies, and build assets.

`setup.sh` automates that sequence behind a guided prompt. It asks a handful of questions, performs every step, and reports exactly what succeeded and what failed — so you always know the state of the project it produced.

`install.sh` is a thin bootstrapper for one-liner installs. It exists because `curl … | bash` breaks interactive scripts: piped into `bash`, a script's `read` calls consume the remaining lines of the script itself instead of user input. `install.sh` downloads `setup.sh` to a temp file and re-runs it with the terminal attached to `stdin`.

## Features

| | |
|---|---|
| **One-line install** | `curl -sSL …/install.sh \| bash` — works because the installer restores the terminal. |
| **Guided prompts** | Sensible defaults for every question; press `Enter` to accept. |
| **Non-interactive** | Every prompt has a matching option, so the script runs in CI, Docker, and cron. |
| **Input validation** | Rejects invalid project names, unsupported versions, and malformed answers before anything is written to disk. |
| **Dependency checks** | Verifies PHP, Composer, and the PDO driver required by the database you select. |
| **Database provisioning** | MySQL, PostgreSQL, or SQLite — including optional automatic database creation. |
| **Safe `.env` handling** | Updates keys in place (and uncomments them when needed) instead of rewriting the file; values are quoted and escaped. |
| **Frontend build** | Detects npm, pnpm, or Yarn, installs dependencies, and builds assets. |
| **Integrity check** | SHA-256 verification against a published `setup.sh.sha256`, plus a structural check of the download. |
| **Readable output** | Each step shows a live progress indicator; command output is captured and only printed when a step fails. |

## Requirements

**Mandatory**

- Bash 3.2 or newer (macOS ships Bash 3.2 by default)
- PHP 8.2 or newer
- [Composer](https://getcomposer.org)

The script targets Linux and macOS. It relies only on Bash built-ins and standard command-line utilities, so it runs unchanged on both platforms.

**Conditional**

| Tool | Required for |
|---|---|
| Node.js + npm / pnpm / Yarn | Installing and building front-end assets |
| `mysql` client | Automatic MySQL database creation |
| `psql` / `createdb` client | Automatic PostgreSQL database creation |
| PDO driver (`pdo_mysql`, `pdo_pgsql`, `pdo_sqlite`) | The database engine you select |

## Usage

### Interactive

```bash
curl -sSL https://aryawiratama.web.id/install.sh | bash
```

```
Preflight checks
✔ php 8.3.12
✔ Composer version 2.8.6

Laravel project
Name of Laravel Project [my_app_default]: shop
Version of Laravel Project (11/12/13) [12]: 12
✔ Project : Shop
✔ Version : Laravel 12

Creating project
… composer create-project laravel/laravel:^12 shop..............................
✔ composer create-project laravel/laravel:^12 shop

Database
› 1. MySQL   2. PostgreSQL   3. SQLite
Choose database [1]: 1
Database host [127.0.0.1]: 127.0.0.1
Database port [3306]: 3306
Database name [shop]: shop
Database user [root]: root
Database password: ********
✔ MySQL configured (root@127.0.0.1:3306/shop)
Create the database if it does not exist? [y/n]: y
✔ Database 'shop' is ready

Laravel setup
… php artisan key:generate.
✔ php artisan key:generate
… php artisan storage:link..
✔ php artisan storage:link
… php artisan migrate....
✔ php artisan migrate
… npm install............................
✔ npm install
… npm run build...
✔ npm run build
… git init.
✔ git init

Done
```

### Non-interactive

Pass the options and `--yes` to skip every prompt. Required in CI, cron, and Docker builds, where no terminal is attached:

```bash
curl -sSL https://aryawiratama.web.id/install.sh \
  | bash -s -- --name=shop --version=12 --db=sqlite --yes
```

```yaml
# GitHub Actions
- run: curl -sSL https://aryawiratama.web.id/install.sh | bash -s -- --name=app --db=sqlite --yes --no-build
```

```dockerfile
RUN curl -sSL https://aryawiratama.web.id/install.sh | bash -s -- --name=app --db=sqlite --yes --dir=/app
```

### Running the script without the installer

`install.sh` is optional. Cloning the repository works identically:

```bash
git clone <repository-url> laravel-setup-bash
cd laravel-setup-bash
./setup.sh
```

Or, to inspect the script before trusting it:

```bash
curl -fsSL https://aryawiratama.web.id/setup.sh -o setup.sh
less setup.sh
bash setup.sh
```

Downloading to a file and running it is always safe for interactive prompts, because `stdin` stays attached to your terminal.

## What the Script Does

The script runs in six phases.

### 1. Preflight checks

Confirms that `php` and `composer` are available and reports their versions. If PHP is older than 8.2, it prints a warning — Laravel 11+ will not run on it. The script stops immediately if a required tool is missing.

### 2. Project definition

Prompts for a project directory name and a Laravel version (11, 12, or 13). Input is validated before Composer is invoked:

- Names must match `[A-Za-z0-9][A-Za-z0-9._-]*` — this prevents paths with spaces from breaking `cd` and Composer arguments.
- Versions must be numeric and at least 11.
- If the target directory already exists, you are asked to confirm before continuing.

`APP_NAME` is derived from the directory name by replacing `-` and `_` with spaces and capitalising the first letter.

### 3. Project creation

Runs `composer create-project laravel/laravel:^<version> <name> --no-interaction` and moves into the new directory. If `.env` is missing, it is copied from `.env.example`.

### 4. Database configuration

Presents a menu of supported engines and writes the corresponding `DB_*` keys to `.env` (and to `.env.example`, keeping the committed template in sync). See [Database Support](#database-support) for engine-specific behaviour.

### 5. Laravel and front-end setup

Runs the standard post-install commands, in order:

| Step | Command |
|---|---|
| App key | `php artisan key:generate --force` |
| Storage symlink | `php artisan storage:link --force` |
| Migrations | `php artisan migrate --force` |
| Database seeder | `php artisan db:seed --force` — only with `--seed` |
| Dependencies | `pnpm install`, `yarn install`, or `npm install` — chosen from the lockfile present |
| Asset build | `npm run build` |
| Version control | `git init` (skipped if the directory is already a repository) |

### 6. Summary

Prints the directory to change into, the command to start the development server, and follow-up commands for seeding and testing.

## Options

`install.sh` accepts its own options and forwards everything else to `setup.sh`.

### Installer options

| Option | Description |
|---|---|
| `-n`, `--dry-run` | Download `setup.sh`, print it, and exit without running it. |
| `--base-url=URL` | Fetch `setup.sh` from `URL` instead of `https://aryawiratama.web.id`. |
| `--no-verify` | Skip the SHA-256 integrity check. |
| `--allow-root` | Run even when invoked with `sudo` (off by default). |
| `-h`, `--help` | Show the installer's help. |
| `-V`, `--version` | Show the installer version. |

Pass installer options *before* `--`; everything after it is forwarded verbatim.

### Setup options

| Option | Default | Description |
|---|---|---|
| `--name=NAME` | `my_app_default` | Project directory name. |
| `--version=VERSION` | `12` | Laravel major version: `11`, `12`, or `13`. |
| `--db=ENGINE` | `1` (MySQL) | `mysql`, `pgsql` (or `postgres`), or `sqlite`. |
| `--db-host=HOST` | `127.0.0.1` | Database host. |
| `--db-port=PORT` | `3306` / `5432` | Database port. |
| `--db-name=NAME` | Derived from `--name` | Database name. |
| `--db-user=USER` | `root` / `postgres` | Database user. |
| `--db-password=PASS` | *(empty)* | Database password. |
| `--dir=PATH` | Current directory | Directory to create the project in. Must exist. |
| `--seed` | off | Run `php artisan db:seed` after migrating. |
| `--no-build` | off | Skip installing and building front-end assets. |
| `-n`, `--dry-run` | off | Print the resolved plan and exit. |
| `-y`, `--yes` | off | Accept every default and never prompt. |
| `-h`, `--help` | — | Show `setup.sh` help. |
| `-V`, `--version` | — | Show the script version. |

## Database Support

| Engine | Driver | Automatic database creation | Notes |
|---|---|---|---|
| **MySQL** | `pdo_mysql` | Yes, via the `mysql` client | Creates the database with `utf8mb4` / `utf8mb4_unicode_ci` if it does not exist. |
| **PostgreSQL** | `pdo_pgsql` | Yes, via `psql` / `createdb` | Checks for an existing database first, then creates it if needed. |
| **SQLite** | `pdo_sqlite` | Not applicable | Creates `database/database.sqlite` and clears `DB_HOST`, `DB_PORT`, `DB_USERNAME`, and `DB_PASSWORD`. |

Credentials are always sent to the client through the `MYSQL_PWD` and `PGPASSWORD` environment variables rather than command-line arguments, so they do not appear in the process list.

## Configuration

The script is fully interactive and takes no arguments. Every value it needs is collected at runtime:

| Prompt | Default | Notes |
|---|---|---|
| Project name | `my_app_default` | Also becomes the project directory and the basis for `APP_NAME`. |
| Laravel version | `12` | Accepts 11, 12, or 13. |
| Database engine | `1` (MySQL) | `1` MySQL · `2` PostgreSQL · `3` SQLite. |
| Database host | `127.0.0.1` | MySQL and PostgreSQL only. |
| Database port | `3306` / `5432` | Default depends on the engine. |
| Database name | Derived from the project name | Non-alphanumeric characters become underscores. |
| Database user | `root` / `postgres` | Default depends on the engine. |
| Database password | *(empty)* | Written to `.env` quoted and escaped. |

The resulting `.env` will contain, for example:

```dotenv
APP_NAME="Shop"
DB_CONNECTION=mysql
DB_HOST="127.0.0.1"
DB_PORT="3306"
DB_DATABASE="shop"
DB_USERNAME="root"
DB_PASSWORD="s3cr#t p@ss"
```

## After Setup

```bash
cd shop
php artisan serve          # http://127.0.0.1:8000
php artisan db:seed        # load sample data
php artisan test           # run the test suite
```

## Security

Piping a script from the internet into `bash` deserves a second look. The measures this project takes:

| Measure | Behaviour |
|---|---|
| **Dry run** | `--dry-run` prints the script and exits. Nothing is executed. |
| **Structural check** | The download is rejected if it is empty or is not a Bash script. |
| **Checksum** | If `setup.sh.sha256` is published next to `setup.sh`, its SHA-256 is verified and a mismatch aborts the install. Missing checksum is a warning, not a failure. |
| **No `sudo`** | The installer refuses to run as root. Project files would be owned by root. Override with `--allow-root` if you know what you are doing. |
| **Temp cleanup** | `setup.sh` is executed from a temporary directory that is removed on exit, including on `Ctrl+C`. |
| **No secrets in argv** | Database passwords are passed to the client through the environment, never as command-line arguments. |
| **Non-interactive guard** | With no terminal attached and no `--yes`, the installer stops with instructions instead of failing halfway through. |

Always serving over HTTPS matters: the checksum only protects against a modified file if the transport itself is trusted.

## Exit Codes and Troubleshooting

| Exit code | Meaning |
|---|---|
| `0` | Setup completed. Individual steps may still have reported warnings. |
| `1` | Fatal error — a missing dependency, invalid input, a failed download, or a failed `composer create-project`. |
| `130` | Interrupted with `Ctrl+C` or end-of-input. |

**A step shows `! … failed`.** Setup continues so you can fix the problem without re-running everything. The captured output is printed under the warning; run the same command manually inside the project to investigate.

**`No interactive terminal available.`** CI, cron, or SSH without a TTY. Pass the options with `--yes`, or download the script and run it from a real terminal.

**`Checksum mismatch for setup.sh.`** Either the download was tampered with, or the published `setup.sh.sha256` is stale. Verify manually, then regenerate the checksum or delete the file.

**`PHP extension 'pdo_mysql' is missing.`** Install the driver for your package manager, for example `sudo apt install php8.3-mysql`.

**`mysql client not found - skipping automatic database creation.`** Install the client, or create the database manually and re-run `php artisan migrate`.

**The target directory already exists.** Composer will not overwrite a non-empty directory. Remove it, choose a different name, or let the script continue and resolve merge prompts yourself.

**The script updated but users get the old version.** That is CDN caching. Bump `VERSION` in `install.sh` (it is used as a cache-busting query parameter) and redeploy.

## Deploying on Vercel

The installer is served as a static file — Vercel never executes it, and no `chmod` is needed. Two supported layouts.

### Option A — a dedicated Vercel project

Deploy this repository as its own Vercel project and point a subdomain at it. The website stays untouched, and the files served are exactly the ones in this repository.

1. Import the repository in Vercel with the **Other** framework preset (no build command).
2. Set the output directory to the repository root.
3. Add the domain, for example `install.aryawiratama.web.id`.
4. Deploy.

```
https://install.aryawiratama.web.id/install.sh
```

### Option B — inside an existing Vercel project

If `aryawiratama.web.id` already serves a site, drop the files into that project's `public/` directory:

```
public/
├── install.sh
└── setup.sh
```

```
https://aryawiratama.web.id/install.sh
```

### Caching

Both layouts need the headers in `vercel.json`, otherwise the CDN keeps serving an old `setup.sh` after you update it:

```json
{
  "headers": [
    {
      "source": "/(install|setup)\\.sh",
      "headers": [
        { "key": "Cache-Control", "value": "public, max-age=0, must-revalidate" }
      ]
    }
  ]
}
```

`install.sh` also appends `?v=<VERSION>` to the download URL, so bumping `VERSION` guarantees users get the current script.

### Checksum publishing (optional)

To enable integrity verification, publish `setup.sh.sha256` next to `setup.sh` and regenerate it **every time `setup.sh` changes**:

```bash
sha256sum setup.sh > setup.sh.sha256
```

A stale checksum aborts the installer for every user, so it is git-ignored in this repository. If you publish it from CI, regenerate it in the same job that deploys — for example a build step that runs the command above before `vercel deploy`.

## Project Structure

```
laravel-setup-bash/
├── install.sh      # Bootstrapper for one-line installs
├── setup.sh        # The setup script
├── vercel.json     # Cache headers for the published files
└── README.md       # Documentation
```

## License

Released under the MIT License.
