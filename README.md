# Custom DB Manager

**A local-first data management tool featuring a command-line interface, HTTP API, and automated backup capabilities.**

[![Version](https://img.shields.io/badge/version-1.0-informational)](#version-and-distribution) [![Runtime](https://img.shields.io/badge/runtime-Bash%20%2B%20Python-blue)](#requirements) [![Architecture](https://img.shields.io/badge/architecture-single--file-success)](#architecture)

**Custom DB Manager** is a data management tool distributed as a single executable `.sh` file. It is designed for both personal and professional use: from information organisation, inventories, and small technical projects to local workflows, laboratories, development environments, and team operations that require a straightforward solution to administer.

The tool combines an interactive CLI, a file-based storage engine, an optional HTTP API, and backup mechanisms. Its architecture prioritises straightforward installation, local control of data, per-database configuration, and the ability to operate without external services.

> **Important positioning:** Custom DB Manager is a local, file-based data manager. It is not a SQL server and does not implement distributed replication, automatic high availability, clustering, or a complete user-and-role management system. For mission-critical workloads, multiple writer servers, or specific regulatory requirements, it should be evaluated as a component of a broader architecture rather than as a direct replacement for a dedicated enterprise DBMS.

---

## Table of Contents

- [Overview](#overview)
- [Key Capabilities](#key-capabilities)
- [Architecture](#architecture)
- [Requirements](#requirements)
- [Installation with curl](#installation-with-curl)
- [Getting Started](#getting-started)
- [Command Reference](#command-reference)
- [Storage Model](#storage-model)
- [HTTP API](#http-api)
- [Backup and Recovery](#backup-and-recovery)
- [Backup Configuration](#backup-configuration)
- [Processes and Automation](#processes-and-automation)
- [Directory Structure](#directory-structure)
- [Operational Best Practices](#operational-best-practices)
- [Known Limitations and Scope](#known-limitations-and-scope)
- [Security](#security)
- [Version and Distribution](#version-and-distribution)

---

## Overview

Custom DB Manager aims to provide a direct and controllable data administration experience without requiring the installation of a separate database server. The application is launched from a terminal and can manage multiple databases within its own directory structure.

Each database maintains its own metadata, tables, API configuration, credentials, and backup settings. Operations are performed locally through the CLI or, when configured, through an HTTP API associated with that database.

### Intended Users and Use Cases

- **Personal use:** structured lists, records, household inventories, collections, projects, and information organisation.
- **Development and laboratory environments:** prototypes, integration tests, demonstrations, utility tools, and local storage for applications.
- **Small teams and professional operations:** internal catalogues, operational records, inventories, process-support data, and low-to-medium-volume internal services.
- **Automation:** scheduled tasks, backup exports, tool integration through the HTTP API, and repeatable command-driven operations.

Suitability for each scenario depends on data volume, concurrency, data criticality, continuity requirements, and the security controls required by the organisation.

## Key Capabilities

### Database and Table Management

- Create, list, select, describe, rename, and remove databases.
- Create, list, inspect, rename, and remove tables.
- Create, list, rename, and remove columns.
- Insert, update, query, and delete records.
- Display tables and database structure in the terminal.

### Structured Storage

- Column values are stored as text while preserving spaces.
- `append-only` insertion: each `insert_into` operation appends a new record; it does not reuse or overwrite an existing record.
- Numeric, increasing primary identifiers.
- Record partitioning into blocks of **1,000 IDs**.
- Storage generations, a manifest, and atomic publication of the table state.
- Optional file-persisted index, with enable, disable, status, and rebuild operations.
- Read/migration compatibility with the legacy line-based format.

> `append-only` describes insertion behaviour. It does not make the database an immutable ledger: explicit update and deletion commands exist, so data can be changed or removed through those operations.

### Concurrency and Local Consistency

The code combines `threading.RLock` with `fcntl.flock` to coordinate table operations between threads and processes on the same system. Data and metadata writes are published through temporary files and atomic replacement (`os.replace`), with file/directory synchronisation where supported by the operating system.

This mechanism is designed to coordinate the CLI and API processes within a local installation. It must not be interpreted as a distributed locking mechanism or as a guarantee of multi-host writes on every network filesystem.

### HTTP API

- Per-database API with `public` and `secret` types.
- Authentication using two distinct keys.
- Authentication through `Authorization: Bearer` or the compatibility parameter `?key=`.
- Configurable permissions for the `public` API.
- Basic request rate limiting for the `public` API.
- JSON responses and an HTML status page at the API root.

### Backups and Continuity

- Manual and scheduled backups per database.
- Optional compression.
- Optional encryption with OpenSSL.
- Optional SHA-256 verification.
- Optional HMAC signature of the SHA-256 digest.
- Retention policy, including daily and weekly preservation.
- Local destination or a directory on a secondary filesystem.
- Restore with archive verification and restart of services that were active, when possible.

---

## Architecture

The distribution consists of a **single Bash file**. The Python code used by the storage engine, API, backups, and helper processes is embedded in that file. Bash extracts the embedded Python block at runtime; no separate Python module needs to be installed.

Main components:

| Component | Responsibility |
|---|---|
| Bash CLI | Interactive interface, command history, banner, and command routing. |
| Embedded Python layer | Data management, HTTP API, backups, configuration, and internal processes. |
| JSONL storage | Table records organised into generations and partitions. |
| Table manifest | Reference to the active generation, partitions, columns, record count, and index. |
| Locks | Coordination between threads and processes on the same host. |
| HTTP API | Authenticated access to operations exposed through endpoints. |
| Backup workers | Scheduled backup and cleanup execution per database. |

### Execution Model

The main application runs in the terminal. API servers and scheduled workers are launched as managed processes in separate sessions/process groups, with identification metadata that allows the CLI to monitor and terminate them.

The backup log monitor may open a terminal window when a compatible terminal emulator is available. The log window is a monitoring interface; the worker runs as a separate process.

## Requirements

### Recommended Environment

- Linux (the recommended environment and target for process-management routines).
- Bash.
- Python 3.12 or later recommended.
- A local filesystem supporting Unix permissions, atomic file replacement, and `flock`.

### Optional External Dependencies

| Program | Usage |
|---|---|
| `curl` | `api_request` command and the file download instructions. |
| `openssl` | HTTPS certificate generation and backup encryption/decryption. |
| `notify-send` | Desktop completion notifications, when enabled and installed. |
| `gnome-terminal`, `konsole`, `xterm`, or `x-terminal-emulator` | Visible terminal window for monitoring backup-worker logs. |

The API layer, storage engine, and backup mechanisms do not depend on third-party Python packages; they use Python's standard library. The availability of the listed external programs is required for the corresponding optional features.

---

## Installation with curl

The distribution file is hosted in the project's GitHub repository.

### 1. Create a Working Directory

Choose a persistent directory. The `db_manage` folder is created relative to the current working directory; therefore, always run the program from the same location.

```bash
mkdir -p "$HOME/custom-db-manager"
cd "$HOME/custom-db-manager"
```

### 2. Download the Published Version

```bash
curl -fL \
  'https://raw.githubusercontent.com/afonsoinaciocarreira-cmd/custom-db-manager/refs/heads/main/customdb.sh' \
  -o customdb.sh
```

### 3. Set Executable Permissions

```bash
chmod 700 customdb.sh
```

### 4. Launch Custom DB Manager

```bash
./customdb.sh
```

You can also launch it explicitly through Bash:

```bash
bash customdb.sh
```

### 5. Update the Application

Before replacing a file that is in use, stop the managed servers and workers, back up `db_manage`, and download the new version into the same working directory. Do not replace the file while processes from the previous version are active.

> **Source verification:** the command above downloads the file directly from the `main` branch. For professional environments, pin an approved version/revision, record the file's SHA-256 hash, and validate its provenance before execution. This documentation does not assume that the repository publishes release signatures or checksums.

---

## Getting Started

When the program starts, it displays the Custom DB Manager banner. The prompt identifies the host and the currently selected database.

### Create Your First Database

```text
create_database crm
use crm
```

### Create a Table and Its Columns

```text
create_table contacts
create_column contacts name email company
```

The `id` column is created automatically and is the reserved primary key.

### Insert Data Containing Spaces

```text
insert_into contacts name "Ana Silva" email "ana@example.com" company "Acme Group"
```

Values are passed as quoted arguments. Spaces inside the quotes belong to the column value and do not separate columns.

### Query and Search

```text
show_tables contacts
select_from contacts
search contacts company "Acme Group"
```

### Update and Delete

```text
update contacts company "Acme Group" "Acme Europe"
delete_record contacts email "ana@example.com"
```

Deleting all records from a table is a separate operation:

```text
delete_from contacts
```

---

## Command Reference

Enter `help` inside the CLI to display the built-in menu. Commands that operate on database data generally require an active database selected through `use <name>`.

### System and Navigation

| Command | Description |
|---|---|
| `help` | Displays help. |
| `clear` | Clears the terminal area and displays the initial banner again. |
| `exit` / `quit` | Exits the CLI. |
| `system_process` | Lists processes managed by the application. |
| `system_process kill <managed-process-or-pid>` | Terminates a managed process identified by a supported name or registered PID. It is not a command for terminating arbitrary system PIDs. |
| `system_terminate [--force]` | Stops managed processes and removes/recreates the `db_manage` structure. This is a destructive operation. |

### Databases

| Command | Description |
|---|---|
| `create_database <name>` | Creates a database. |
| `show_databases` | Lists available databases. |
| `use <name>` | Selects the active database. |
| `describe <name>` | Displays database metadata/a summary of its structure. |
| `dump_db` | Displays metadata, tables, and records from the active database. |
| `rename_database <name> <newname>` | Renames a database. |
| `drop_database <name>` | Removes a database and its files. |

### Tables and Columns

| Command | Description |
|---|---|
| `create_table <name>` | Creates a table with the `id` column. |
| `show_tables` | Lists tables in the active database. |
| `show_tables <table>` | Displays a table's records and columns. |
| `rename_table <name> <newname>` | Renames a table. |
| `drop_table <name>` | Removes a table. |
| `create_column <table> <column> [<column> ...]` | Adds one or more columns. |
| `show_columns <table>` | Lists a table's columns. |
| `rename_column <table> <old> <new>` | Renames a column. |
| `drop_column <table> <column>` | Removes a column. The `id` column cannot be removed. |

### Record Operations

| Command | Description |
|---|---|
| `insert_into <table> <column> "<value>" [<column> "<value>"]` | Appends a record; supports values containing spaces and multiple column/value pairs. |
| `select_from <table>` | Displays table records. |
| `search <table> <column> "<value>"` | Searches for values in a column; it may use the configured index. |
| `index <table> <on\|off\|rebuild\|status>` | Manages the table's persistent index. |
| `update <table> <column> "<old>" "<new>"` | Updates records whose column value matches the specified value. |
| `delete_record <table> <column> <value>` | Deletes records matching the column value. |
| `delete_from <table>` | Deletes all records from a table. |

**Indexing example:**

```text
index contacts status
index contacts off
index contacts on
index contacts rebuild
```

The index is optional. Enabling it may accelerate equality searches, but it requires additional storage and maintenance during writes.

### API

| Command | Description |
|---|---|
| `api_setup <public\|secret>` | Configures an API and requests two distinct keys. |
| `api_edit <public\|secret>` | Edits the API configuration and its two keys. |
| `api_start <public\|secret>` | Starts the API server. |
| `api_stop <public\|secret>` | Stops the API server. |
| `api_status <public\|secret>` | Displays the server status and parameters. |
| `api_delete <public\|secret>` | Stops and removes the selected API's configuration files. |
| `api_permissions` | Lists permissions for the `public` API. |
| `api_permissions <perm> <true\|false>` | Enables or disables a public API permission. |
| `api_key list` | Lists the database's registered keys. |
| `api_key add <key>` | Registers a new key. |
| `api_key remove <key\|secret_key_N>` | Removes a key that is not currently used by an API configuration. |
| `api_request <public\|secret> <endpoint>` | Sends a local request to the configured API. |

### Backups

| Command | Description |
|---|---|
| `backup [<name>] [--force]` | Creates a backup of the active database. If the name is omitted, an automatic name is generated. |
| `backups` | Lists backups available for the active database. |
| `backup_restore <name> [--force]` | Restores a backup, replacing the active database's current data. |
| `backup_delete <name> [--force]` | Removes a specific backup. |
| `backup_schedule <backup\|backup_delete> <true\|false> [<interval>]` | Enables or disables the automatic backup or cleanup routine. |
| `backup_configs` | Displays backup settings by category. |
| `backup_configs <key>` | Displays the value of a setting. |
| `backup_configs <key> <value>` | Updates a setting. |

Supported intervals include values such as `30sec`, `5min`, `1h`, `1d`, and `1w`.

---

## Storage Model

The data structure is designed to preserve text values containing spaces and to avoid making every operation depend on a single data line separated by spaces.

### Table Structure

Each table contains:

- `columns`: the table's ordered schema;
- `.table.lock`: file used for thread/process synchronisation;
- `.next_id`: the next identifier to assign;
- `.index_enabled`: state of the optional index;
- `.storage/manifest.json`: manifest for the active generation;
- `.storage/generations/<generation>/`: JSONL partition files and, when enabled, the index.

### Partitioning

Records are grouped into partitions calculated from their IDs. The configured partition size is **1,000 IDs per block**. Partition files use JSON Lines (one JSON object per line) and store the record ID and row values.

The manifest identifies the generation and corresponding partition files, along with metadata such as columns, record count, maximum ID, and index availability. The manifest is published atomically after the generation files have been written.

### Index

When enabled, the index is stored as `index.json` in the table generation and maps column values to record IDs. It can be disabled and rebuilt through the `index` command.

### Compatibility with Legacy Data

When a table only contains the legacy format, the read layer interprets the old lines and initialises modern storage. Legacy lines that contained unquoted values with spaces may be ambiguous because the old format used spaces as value separators. Back up your data and inspect migrated records before relying on the converted data.

---

## HTTP API

### Configuration

Configuration is per database and per API type (`public` or `secret`). For example:

```text
use crm
api_setup public
```

The setup assistant requests a name, protocol (`http` or `https`), listening address, port, debug mode, and two different secret keys. Initial values are name `api`, protocol `http`, address `localhost`, port `8080`, and debug `true`; consciously review these values before exposing the service.

The base path is formed from the normalised API name:

```text
http(s)://<address>:<port>/customdb/<api-slug>/
```

The default address is `localhost`. To make the service available from another machine, deliberately configure the listening address and firewall rules.

### Authentication

The API requires two distinct keys. The recommended method is the header. The CLI's helper command `api_request` currently uses the query-string form; to avoid placing credentials in a URL, use an HTTP client such as `curl` with the header below:

```http
Authorization: Bearer <key1>/<key2>
```

The query parameter `?key=<key1>/<key2>` remains available for compatibility. To reduce credential exposure, prefer the `Authorization` header: URLs may be stored in histories, diagnostic tools, and proxy logs.

### curl Example

Example of inserting a record into a `contacts` table (replace the host, port, slug, and both keys):

```bash
curl --fail -X POST \
  -H 'Authorization: Bearer KEY_ONE/KEY_TWO' \
  -H 'Content-Type: application/json' \
  -d '{"data":{"name":"Ana Silva","company":"Acme Europe"}}' \
  'http://127.0.0.1:8080/customdb/crm-api/insert_into/contacts/'
```

The insert endpoint appends a record; the JSON object can provide a map of column names to values.

### Available Endpoints

All requests are authenticated before processing. Currently implemented endpoints include:

| Endpoint | Function | `public` API Permission |
|---|---|---|
| `/` and `/status` | Server status and table list. | Authentication; no additional permission required. |
| `/dump_db` | Metadata and table/record listing. | `dump_db` |
| `/show_tables` | Lists tables. | `show_tables` |
| `/select_from/<table>` and `/select/<table>` | Reads a table. | `select_from` |
| `/insert_into/<table>` and `/insert/<table>` | Appends a record. | `insert_into` |
| `/create_table/<table>` | Creates a table. | `create_table` |
| `/drop_table/<table>` | Removes a table. | `drop_table` |
| `/delete_from/<table>` | Deletes all records from a table. | `delete_from` |
| `/delete_record/<table>/<record>` | Deletes matching records. | `delete_record` |

The API implements handlers for `GET`, `POST`, `PUT`, and `DELETE`. `POST` and `PUT` request bodies are limited to 2 MB. The `public` API applies a basic limit of 10 requests per IP in 5 seconds; this control is in memory and does not replace a gateway/WAF or denial-of-service protection.

### `public` API and `secret` API

- **`public`:** checks the `permissions.cfg` permission matrix. Permissions are disabled (`false`) by default and must be explicitly enabled.
- **`secret`:** after authentication, permission-matrix checks are bypassed. Treat this API as a high-privilege administrative interface and do not expose it directly to untrusted networks.

The permission matrix contains operations listed in the CLI, but the effective HTTP endpoints are only those listed above. A configured permission does not, by itself, mean that a corresponding HTTP endpoint exists.

---

## Backup and Recovery

### Manual Backup

```text
use crm
backup
backup snapshot_2026_01
backups
```

Backup names accept letters, numbers, periods, underscores, and hyphens; spaces are not accepted. `--force` allows a backup with the same name to be replaced.

### Restore

```text
backup_restore snapshot_2026_01
```

Without `--force`, confirmation is requested. The restore process validates integrity/signature files when configuration or sidecar files require it, extracts the contents into a temporary area, and replaces the database directory. Active API servers and automatic workers are stopped before the restore and may be restarted after the operation.

A restore replaces existing data: create a backup of the current state first and rehearse the procedure in a separate environment.

### Secondary Destination

The `backup_storage_path` setting allows you to select an existing, mounted, writable absolute directory located on a filesystem different from the one containing `db_manage`.

```text
backup_configs backup_storage_path "/mnt/backup-disk"
```

Backups are stored inside a directory named after the database:

```text
/mnt/backup-disk/<database>/
```

The application validates the filesystem to avoid silently treating a missing mount point as an ordinary directory on the primary disk. If the external destination becomes unavailable, backup operations that require it should fail; the program must not be understood as automatically falling back to the primary disk.

### Formats and Controls

- Compression: `.tar.gz` when `auto_compression=true`; `.tar` when disabled.
- Encryption: adds `.enc` to the archive and uses OpenSSL AES-256-CBC with PBKDF2.
- Integrity: `.sha256` sidecar when `verify_integrity=true`.
- Signature: `.sig` sidecar with HMAC-SHA256 when `sign_manifest=true`.
- Retention: `max_backups`, `auto_cleanup`, `keep_daily`, and `keep_weekly`.

Encryption and signing keys are stored in `secrets` and excluded from the backup archive. Keep separate copies of these keys in a vault or other secure medium. If the encryption key is lost, the corresponding backups cannot be decrypted. The archive may also contain API configuration and credentials; therefore, enable encryption before transferring backups to external locations.

---

## Backup Configuration

Settings are specific to each database and are queried/updated through `backup_configs`.

| Category | Key | Purpose | Default |
|---|---|---|---|
| General | `default_backup_name` | Prefix used for automatically generated names. | `auto` |
| General | `auto_compression` | Enables/disables compression. | `true` |
| General | `verify_integrity` | Creates and validates a SHA-256 digest. | `false` |
| General | `backup_storage_path` | Secondary storage directory; an empty value uses the database's local backup directory. | empty |
| Retention | `max_backups` | Number of backups to retain, respecting protected daily/weekly retention points. | `10` |
| Retention | `auto_cleanup` | Runs cleanup after a backup is created. | `false` |
| Retention | `keep_daily` | Preserves the most recent backup from each day. | `false` |
| Retention | `keep_weekly` | Preserves the most recent backup from each week. | `false` |
| Schedule | `default_interval` | Default interval for automatic backups. | `1h` |
| Schedule | `background_daemon` | Persisted configuration field; the current worker is started in a dedicated process session. | `true` |
| Schedule | `notify_on_completion` | Sends a desktop notification through `notify-send`, if available. | `false` |
| Security | `encrypt_backups` | Encrypts archives with OpenSSL. | `false` |
| Security | `storage_permissions` | Octal mode used for backup directory and file permissions. | `700` |
| Security | `sign_manifest` | Creates and validates an HMAC-SHA256 signature of the backup digest. | `false` |

Examples:

```text
backup_configs
backup_configs max_backups
backup_configs max_backups 14
backup_configs auto_compression true
backup_configs verify_integrity true
backup_configs encrypt_backups true
backup_configs sign_manifest true
backup_configs auto_cleanup true
backup_configs keep_daily true
backup_configs keep_weekly true
```

### Scheduling

```text
backup_schedule backup true 1h
backup_schedule backup_delete true 1d
```

To disable each routine:

```text
backup_schedule backup false
backup_schedule backup_delete false
```

`backup` creates archives with a prefix and timestamp. `backup_delete` runs cleanup according to the retention policy. Schedule status and managed PIDs can be queried using `backup_schedule` without arguments and `system_process`.

---

## Processes and Automation

API servers and backup workers are child processes managed by the application. They are registered in PID files and associated metadata, including process identity information and a management token. The shutdown routine attempts to terminate the managed process and its descendants, while avoiding arbitrary PIDs that are not associated with the application.

Operational commands:

```text
system_process
system_process kill crm-public
system_process kill backup
system_process kill backup_delete
api_status public
api_stop public
```

The exact names accepted by `system_process kill` are those shown in the help menu and depend on the managed processes currently registered. This command is not a replacement for `kill` as a general system-administration utility.

Workers check whether their routine remains enabled in the configuration. When a function is set to `false`, the worker exits and its corresponding visible monitor is closed.

---

## Directory Structure

The `db_manage` directory is created in the **current working directory** from which the script is run.

```text
db_manage/
├── database/
│   └── <database>/
│       ├── <database>.db
│       ├── .schema.lock
│       ├── .cli_history
│       ├── api/
│       │   ├── public/
│       │   │   ├── api.cfg
│       │   │   ├── permissions.cfg
│       │   │   ├── api.pid
│       │   │   └── server.log
│       │   └── secret/
│       │       ├── api.cfg
│       │       ├── api.pid
│       │       └── server.log
│       ├── secrets/
│       │   ├── database.cfg
│       │   ├── backup_configs.cfg
│       │   ├── backup_schedule.cfg
│       │   ├── backup_encryption.key
│       │   └── backup_manifest.key
│       ├── backups/                 # local destination if no external path is configured
│       └── tables/
│           └── <table>/
│               ├── columns
│               ├── .table.lock
│               ├── .next_id
│               ├── .index_enabled
│               └── .storage/
│                   ├── manifest.json
│                   └── generations/
│                       └── <generation>/
│                           ├── shard_00000000.jsonl
│                           └── index.json
└── runtime/
    ├── .cli_history
    └── migration/runtime metadata
```

The exact files present depend on which features have been used. External backups are stored outside this tree at `<backup_storage_path>/<database>/`.

---

## Operational Best Practices

1. Always run the script from the same working directory.
2. Use a dedicated system account without unnecessary administrative privileges.
3. Keep `db_manage` and secrets protected by restrictive permissions.
4. Configure a backup destination on a genuinely independent filesystem.
5. Enable encryption, verification, and signing before storing copies off-host.
6. Preserve backup keys separately and test recovery periodically.
7. Prefer `Authorization: Bearer` instead of sending secrets in query strings.
8. Keep the `secret` API limited to localhost or a controlled administrative network.
9. Do not enable public permissions without a specific need.
10. Test updates and restores against a validation copy before applying them to production data.
11. Monitor free space on both the primary disk and the backup destination.
12. Avoid network filesystems for multi-host concurrent access unless the guarantees of `flock` and atomic replacement have been specifically validated.

## Known Limitations and Scope

The published code implements a compact local solution, but does not by itself demonstrate the following capabilities:

- node replication, clustering, or automatic failover;
- distributed transactions, synchronous replication, or consensus;
- individual user authentication, full RBAC, or SSO;
- automatic API-key rotation and expiry;
- immutable, centralised auditing;
- point-in-time recovery policies or WAL;
- a full web-based administration interface;
- performance guarantees for unbounded data volumes or concurrency;
- security certification, compliance certification, or external audit.

The API is based on Python's standard-library HTTP server. HTTPS mode can automatically generate a self-signed certificate; a professional installation exposed to clients should use trusted certificates and a validated TLS configuration. Consult [SECURITY.md](SECURITY.md) before exposing the API or storing sensitive data.

## Security

Installation security also depends on the operating system, the account running the program, directory permissions, network configuration, key management, and backup policy.

See **[SECURITY.md](SECURITY.md)** for the security model, deployment recommendations, API limitations, credential handling, and incident response guidance.

## Version and Distribution

- **Product:** Custom DB Manager
- **Version stated in the code:** 1.0
- **Format:** a single Bash file with an embedded Python layer
- **Published file:** `versions/customdb-manager (v1.0)/customdb.sh`
- **Repository:** <https://github.com/afonsoinaciocarreira-cmd/custom-db-manager>
- **Direct source:** <https://raw.githubusercontent.com/afonsoinaciocarreira-cmd/custom-db-manager/refs/heads/main/versions/customdb-manager%20%28v1.0%29/customdb.sh>

The licence and redistribution terms must be checked in the official repository. This document does not grant any usage or redistribution rights beyond those granted by the applicable licence.
