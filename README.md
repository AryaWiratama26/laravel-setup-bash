<div align="center">

# Laravel Setup Bash

**An interactive Bash script that scaffolds a fully configured Laravel project in a single run.**

Create the project · Configure the database · Generate the app key · Run migrations · Build assets

[![Bash](https://img.shields.io/badge/bash-4.0%2B-blue.svg)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS-lightgrey.svg)](#requirements)

</div>

---

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Usage](#usage)
- [What the Script Does](#what-the-script-does)
- [Database Support](#database-support)
- [Environment Variables](#environment-variables)
- [After Setup](#after-setup)
- [Exit Codes and Troubleshooting](#exit-codes-and-troubleshooting)
- [Project Structure](#project-structure)
- [License](#license)

---

## Overview

Bootstrapping a new Laravel application usually means repeating the same sequence of commands: create the project, edit `.env` by hand, paste database credentials, generate an app key, run migrations, install front-end dependencies, and build assets.

`setup.sh` automates that sequence behind a guided prompt. It asks a handful of questions, performs every step, and reports exactly what succeeded and what failed — so you always know the state of the project it produced.

## Features

| | |
|---|---|
| **Guided prompts** | Sensible defaults for every question; press `Enter` to accept. |
| **Input validation** | Rejects invalid project names, unsupported versions, and malformed answers before anything is written to disk. |
| **Dependency checks** | Verifies PHP, Composer, and the PDO driver required by the database you select. |
| **Database provisioning** | MySQL, PostgreSQL, or SQLite — including optional automatic database creation. |
| **Safe `.env` handling** | Updates keys in place (and uncomments them when needed) instead of rewriting the file; values are quoted and escaped. |
| **Frontend build** | Detects npm, pnpm, or Yarn, installs dependencies, and builds assets. |
| **Readable output** | Each step shows a live progress indicator; command output is captured and only printed when a step fails. |

## Requirements

**Mandatory**

- Bash 4.0 or newer (macOS ships Bash 3.2 by default — use a newer shell)
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

## Installation

```bash
git clone <repository-url> laravel-setup-bash
cd laravel-setup-bash
chmod +x setup.sh
```

No installation step is required — the script has no dependencies beyond the tools listed above.

## Usage

Run the script from this directory:

```bash
./setup.sh
```

Or invoke it from anywhere:

```bash
bash /path/to/laravel-setup-bash/setup.sh
```

### Example session

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
| Dependencies | `pnpm install`, `yarn install`, or `npm install` — chosen from the lockfile present |
| Asset build | `npm run build` |
| Version control | `git init` (skipped if the directory is already a repository) |

### 6. Summary

Prints the directory to change into, the command to start the development server, and follow-up commands for seeding and testing.

## Database Support

| Engine | Driver | Automatic database creation | Notes |
|---|---|---|---|
| **MySQL** | `pdo_mysql` | Yes, via the `mysql` client | Creates the database with `utf8mb4` / `utf8mb4_unicode_ci` if it does not exist. |
| **PostgreSQL** | `pdo_pgsql` | Yes, via `psql` / `createdb` | Checks for an existing database first, then creates it if needed. |
| **SQLite** | `pdo_sqlite` | Not applicable | Creates `database/database.sqlite` and clears `DB_HOST`, `DB_PORT`, `DB_USERNAME`, and `DB_PASSWORD`. |

Credentials are always sent to the client through the `MYSQL_PWD` and `PGPASSWORD` environment variables rather than command-line arguments, so they do not appear in the process list.

## Environment Variables

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

## Exit Codes and Troubleshooting

| Exit code | Meaning |
|---|---|
| `0` | Setup completed. Individual steps may still have reported warnings. |
| `1` | Fatal error — a missing dependency, invalid input, or a failed `composer create-project`. |
| `130` | Interrupted with `Ctrl+C` or end-of-input. |

**A step shows `! ... failed`.** Setup continues so you can fix the problem without re-running everything. The captured output is printed under the warning; run the same command manually inside the project to investigate.

**`PHP extension 'pdo_mysql' is missing.`** Install the driver for your package manager, for example `sudo apt install php8.3-mysql`.

**`mysql client not found - skipping automatic database creation.`** Install the client, or create the database manually and re-run `php artisan migrate`.

**The target directory already exists.** Composer will not overwrite a non-empty directory. Remove it, choose a different name, or let the script continue and resolve merge prompts yourself.

## Project Structure

```
laravel-setup-bash/
├── setup.sh      # The setup script
└── README.md     # Documentation
```
