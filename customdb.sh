#!/usr/bin/env bash
# ============================================================================
# CUSTOM DB MANAGER CLI - Version 1.0 (single-file unified edition)
# Bash CLI + embedded Python service layer. No external .py module is required.
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
BOLD='\033[1m'
NC='\033[0m'

CURRENT_DB="none"
HOST=$(hostname 2>/dev/null || echo "localhost")
SCRIPT_FILE=$(readlink -f -- "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")

# Python code is embedded below this Bash program and extracted directly from
# this same file. The delivered application is therefore one self-contained
# .sh file; API and backup child processes relaunch this file as well.
_dbm_python() {
    DB_MANAGER_SCRIPT="$SCRIPT_FILE" python3 - "$@" < <(
        sed -n '/^#__DBM_PYTHON_BEGIN__$/,/^#__DBM_PYTHON_END__$/p' "$SCRIPT_FILE" | sed '1d;$d'
    )
}

# Internal entry point used by API servers and independent backup workers.
if [ "${1:-}" = "--db-manager-internal" ]; then
    shift
    _dbm_python "$@"
    exit $?
fi

if ! command -v python3 >/dev/null 2>&1; then
    printf '%b\n' "${RED}Error: Python 3 is required to run Custom DB Manager.${NC}" >&2
    exit 1
fi

mkdir -p db_manage/database db_manage/runtime
set -o history
HISTSIZE=100000
HISTFILESIZE=100000
shopt -s histappend 2>/dev/null || true

# Internal clear command: never leave a blank terminal; redraw the startup banner.
clear() {
    if [ -t 1 ]; then printf '\033[H\033[2J\033[3J'; fi
    printf '%b' "${CYAN}==================================================${NC}\n"
    printf '%b' "${BOLD}        CUSTOM DB MANAGER CLI - Version 1.0     ${NC}\n"
    printf '%b' "${CYAN}==================================================${NC}\n"
    printf '%b' " Type '${YELLOW}help${NC}' for commands or '${RED}exit${NC}' to quit.\n\n"
}

show_banner() { clear; }

show_help() {
    printf '%b' "\n${CYAN}==================================================${NC}\n"
    printf '%b' "${BOLD}            DATABASE COMMANDS (HELP)              ${NC}\n"
    printf '%b' "${CYAN}==================================================${NC}\n\n"
    printf '%b' " ${YELLOW}[ 🌐 API INTERACTION ]${NC}\n"
    printf '%b' "   ${CYAN}api_status <public|secret>${NC}        ${GRAY}- Check API server status${NC}\n"
    printf '%b' "   ${CYAN}api_start <public|secret>${NC}         ${GRAY}- Start API server${NC}\n"
    printf '%b' "   ${CYAN}api_stop <public|secret> [--force]${NC} ${GRAY}- Stop API server${NC}\n"
    printf '%b' "   ${CYAN}api_delete <public|secret>${NC}        ${GRAY}- Delete API files${NC}\n"
    printf '%b' "   ${CYAN}api_request <public|secret> <cmd>${NC} ${GRAY}- Run CLI command via API (query key or Authorization header)${NC}\n"
    printf '%b' "   ${CYAN}api_setup <public|secret>${NC}         ${GRAY}- Setup API configuration${NC}\n"
    printf '%b' "   ${CYAN}api_edit <public|secret>${NC}          ${GRAY}- Edit API configuration${NC}\n"
    printf '%b' "   ${CYAN}api_permissions <perm> <true|false>${NC} ${GRAY}- Manage public API permissions${NC}\n"
    printf '%b' "   ${CYAN}api_key <add|remove|list> <key>${NC}   ${GRAY}- Manage database API keys${NC}\n\n"
    printf '%b' " ${YELLOW}[ 📂 DATABASE MANAGEMENT ]${NC}\n"
    printf '%b' "   ${CYAN}create_database <name>${NC}            ${GRAY}- Create a new database${NC}\n"
    printf '%b' "   ${CYAN}drop_database <name>${NC}              ${GRAY}- Delete a database${NC}\n"
    printf '%b' "   ${CYAN}rename_database <name> <newname>${NC}  ${GRAY}- Rename a database${NC}\n"
    printf '%b' "   ${CYAN}use <name>${NC}                        ${GRAY}- Select active database${NC}\n"
    printf '%b' "   ${CYAN}show_databases${NC}                    ${GRAY}- List all databases${NC}\n"
    printf '%b' "   ${CYAN}describe <name>${NC}                   ${GRAY}- Show database metadata${NC}\n"
    printf '%b' "   ${CYAN}dump_db${NC}                           ${GRAY}- Show full database dump${NC}\n\n"
    printf '%b' " ${YELLOW}[ 🗄 TABLE MANAGEMENT ]${NC}\n"
    printf '%b' "   ${CYAN}create_table <name>${NC}               ${GRAY}- Create a new table${NC}\n"
    printf '%b' "   ${CYAN}drop_table <name>${NC}                 ${GRAY}- Delete a table${NC}\n"
    printf '%b' "   ${CYAN}rename_table <name> <newname>${NC}     ${GRAY}- Rename a table${NC}\n"
    printf '%b' "   ${CYAN}show_tables <table>${NC}               ${GRAY}- List tables or show a table${NC}\n"
    printf '%b' "   ${CYAN}create_column <table> <column>${NC}    ${GRAY}- Add a column${NC}\n"
    printf '%b' "   ${CYAN}drop_column <table> <column>${NC}      ${GRAY}- Delete a column${NC}\n"
    printf '%b' "   ${CYAN}show_columns <table>${NC}              ${GRAY}- List columns${NC}\n"
    printf '%b' "   ${CYAN}rename_column <table> <old> <new>${NC} ${GRAY}- Rename a column${NC}\n\n"
    printf '%b' " ${YELLOW}[ ⚡ DATA OPERATIONS ]${NC}\n"
    printf '%b' "   ${CYAN}insert_into <table> <column> \"<value with spaces>\"${NC} ${GRAY}- Append data (never overwrites existing rows)${NC}\n"
    printf '%b' "   ${CYAN}select_from <table>${NC}               ${GRAY}- Query data from a table${NC}\n"
    printf '%b' "   ${CYAN}search <table> <column> \"<value>\"${NC} ${GRAY}- Search records using the optional index${NC}\n"
    printf '%b' "   ${CYAN}index <table> <on|off|rebuild|status>${NC} ${GRAY}- Manage the table index${NC}\n"
    printf '%b' "   ${CYAN}update <table> <column> <old> <new>${NC} ${GRAY}- Update records${NC}\n"
    printf '%b' "   ${CYAN}delete_from <table>${NC}               ${GRAY}- Delete all records${NC}\n"
    printf '%b' "   ${CYAN}delete_record <table> <column> <val>${NC} ${GRAY}- Delete a record${NC}\n\n"
    printf '%b' " ${YELLOW}[ 📦 BACKUP MANAGEMENT ]${NC}\n"
    printf '%b' "   ${CYAN}backup <name> [--force]${NC}           ${GRAY}- Create a database-only backup${NC}\n"
    printf '%b' "   ${CYAN}backups${NC}                           ${GRAY}- List backups${NC}\n"
    printf '%b' "   ${CYAN}backup_restore <name> [--force]${NC}   ${GRAY}- Restore a backup${NC}\n"
    printf '%b' "   ${CYAN}backup_delete <name> [--force]${NC}    ${GRAY}- Delete a backup${NC}\n"
    printf '%b' "   ${CYAN}backup_schedule <func> <true|false> <interval>${NC} ${GRAY}- Schedule backup functions${NC}\n"
    printf '%b' "   ${CYAN}backup_configs <key> <value>${NC}      ${GRAY}- Show/configure backup features, including backup_storage_path${NC}\n\n"
    printf '%b' " ${YELLOW}[ 🛠 SYSTEM ]${NC}\n"
    printf '%b' "   ${CYAN}system_terminate [--force]${NC}        ${GRAY}- Stop processes and reset db_manage${NC}\n"
    printf '%b' "   ${CYAN}system_process${NC}                    ${GRAY}- List managed processes${NC}\n"
    printf '%b' "   ${CYAN}system_process <kill> <database|public|secret|backup|backup_delete|pid>${NC} ${GRAY}- Terminate a managed process${NC}\n"
    printf '%b' "   ${CYAN}clear${NC}                             ${GRAY}- Clear screen${NC}\n"
    printf '%b' "   ${CYAN}help${NC}                              ${GRAY}- Show this help menu${NC}\n"
    printf '%b' "   ${CYAN}exit / quit${NC}                       ${GRAY}- Exit application${NC}\n\n"
    printf '%b' "${CYAN}==================================================${NC}\n\n"
}

history_file_for_db() {
    if [ "$CURRENT_DB" = "none" ]; then
        printf '%s' "db_manage/runtime/.cli_history"
    else
        printf '%s' "db_manage/database/$CURRENT_DB/.cli_history"
    fi
}

load_database_history() {
    local hf
    hf=$(history_file_for_db)
    mkdir -p "$(dirname "$hf")"
    history -c
    [ -f "$hf" ] && history -r "$hf"
    HISTFILE="/dev/null"
}

save_database_history() {
    local hf
    hf=$(history_file_for_db)
    mkdir -p "$(dirname "$hf")"
    local last_entry
    last_entry=$(HISTTIMEFORMAT= history 1 2>/dev/null | sed -E 's/^[[:space:]]*[0-9]+[[:space:]]*//')
    [ "$last_entry" = "$1" ] || history -s "$1"
    printf '%s\n' "$1" >> "$hf"
    chmod 600 "$hf" 2>/dev/null || true
}

trim_text() {
    local v="$1"
    v="${v#"${v%%[![:space:]]*}"}"
    v="${v%"${v##*[![:space:]]}"}"
    printf '%s' "$v"
}

show_banner
load_database_history

while true; do
    line=""
    if ! IFS= read -e -r -p "$(printf '%b' "${CYAN}${HOST}${NC}@${BLUE}${CURRENT_DB}${NC} -> ")" line; then
        printf '%b\n' "${GREEN}Exiting. Goodbye!${NC}"
        exit 0
    fi
    line=$(trim_text "$line")
    [ -z "$line" ] && continue
    save_database_history "$line"

    OLD_IFS="$IFS"
    IFS='|' read -r -a command_items <<< "$line"
    IFS="$OLD_IFS"

    for cmd_item in "${command_items[@]}"; do
        cmd_item=$(trim_text "$cmd_item")
        [ -z "$cmd_item" ] && continue
        command="${cmd_item%%[[:space:]]*}"
        if [ "$command" = "$cmd_item" ]; then
            args=""
        else
            args="${cmd_item#"$command"}"
            args=$(trim_text "$args")
        fi

        case "$command" in
            exit|quit)
                printf '%b\n' "${GREEN}Exiting. Goodbye!${NC}"
                exit 0
                ;;
            help)
                show_help
                ;;
            clear)
                clear
                ;;
            use)
                use_name="$args"
                use_name="${use_name#\"}"; use_name="${use_name%\"}"
                use_name="${use_name#\'}"; use_name="${use_name%\'}"
                if [ -z "$use_name" ]; then
                    printf '%b\n' "${RED}Error: Database name required. Usage: use <name>${NC}"
                elif [ ! -f "db_manage/database/$use_name/$use_name.db" ]; then
                    printf '%b\n' "${RED}Error: Database '$use_name' does not exist.${NC}"
                else
                    _dbm_python "$CURRENT_DB" use "$(printf '%q' "$use_name" | sed "s/^'//;s/'$//")"
                    if [ $? -eq 0 ]; then CURRENT_DB="$use_name"; load_database_history; fi
                fi
                ;;
            system_terminate)
                _dbm_python "$CURRENT_DB" "$command" "$args"
                if [ "$CURRENT_DB" != "none" ] && [ ! -f "db_manage/database/$CURRENT_DB/$CURRENT_DB.db" ]; then
                    CURRENT_DB="none"
                    load_database_history
                fi
                show_banner
                ;;
            drop_database)
                _dbm_python "$CURRENT_DB" "$command" "$args"
                if [ "$CURRENT_DB" != "none" ] && [ ! -f "db_manage/database/$CURRENT_DB/$CURRENT_DB.db" ]; then
                    CURRENT_DB="none"
                    load_database_history
                fi
                ;;
            rename_database)
                _old_name="${args%%[[:space:]]*}"
                _new_name="${args#"$_old_name"}"
                _new_name=$(trim_text "$_new_name")
                _old_name="${_old_name#\"}"; _old_name="${_old_name%\"}"
                _new_name="${_new_name#\"}"; _new_name="${_new_name%\"}"
                _dbm_python "$CURRENT_DB" "$command" "$args"
                if [ "$CURRENT_DB" = "$_old_name" ] && [ -f "db_manage/database/$_new_name/$_new_name.db" ]; then
                    CURRENT_DB="$_new_name"
                    load_database_history
                fi
                ;;
            *)
                _dbm_python "$CURRENT_DB" "$command" "$args"
                _rc=$?
                if [ "$_rc" -eq 2 ]; then
                    printf '%b\n' "${RED}Unknown command: '$command'. Type 'help' for available commands.${NC}"
                fi
                ;;
        esac
    done
done

# The following here-document is a protected payload: it is Python source code,
# not a second file. _dbm_python extracts it from this .sh file at run time.
: <<'__DB_MANAGER_PYTHON_PAYLOAD__'
#__DBM_PYTHON_BEGIN__
#!/usr/bin/env python3
from __future__ import annotations
import contextlib
import datetime as dt
import fcntl
import getpass
import hashlib
import html
import hmac
import http.server
import json
import os
import pathlib
import pwd
import re
import shlex
import shutil
import signal
import socket
import subprocess
import sys
import tarfile
import tempfile
import threading
import time
import urllib.parse
import uuid
from typing import Any

# The Python implementation is embedded inside the distributed Bash file.
# Bash passes its absolute path through DB_MANAGER_SCRIPT so API/backup workers
# can relaunch this same single file without an external Python module.
SHELL_SCRIPT = pathlib.Path(os.environ.get("DB_MANAGER_SCRIPT", os.path.abspath(sys.argv[0]))).resolve()
try:
    _dbm_tty_in = open("/dev/tty", "r", encoding="utf-8", errors="replace")
    if _dbm_tty_in.isatty():
        sys.stdin = _dbm_tty_in
except OSError:
    pass

ROOT = pathlib.Path.cwd() / "db_manage"
DB_ROOT = ROOT / "database"
RESET = "\033[0m"
RED = "\033[0;31m"
GREEN = "\033[0;32m"
YELLOW = "\033[1;33m"
CYAN = "\033[0;36m"
BOLD = "\033[1m"

# Cross-thread and cross-process synchronization. Each table has its own lock,
# while the lock file is held with flock() so API workers and the CLI coordinate.
_TABLE_LOCKS: dict[str, threading.RLock] = {}
_TABLE_LOCKS_GUARD = threading.Lock()
SHARD_SIZE = 1000
STORAGE_VERSION = 2


def atomic_write_bytes(path: pathlib.Path, payload: bytes, mode: int | None = None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp_name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=str(path.parent))
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(payload)
            stream.flush()
            os.fsync(stream.fileno())
        if mode is not None:
            os.chmod(temp_name, mode)
        os.replace(temp_name, path)
        with contextlib.suppress(OSError):
            dir_fd = os.open(path.parent, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
            try:
                os.fsync(dir_fd)
            finally:
                os.close(dir_fd)
    except Exception:
        with contextlib.suppress(FileNotFoundError):
            os.unlink(temp_name)
        raise


def atomic_write_text(path: pathlib.Path, value: str, mode: int | None = None) -> None:
    atomic_write_bytes(path, value.encode("utf-8"), mode)


def atomic_write_json(path: pathlib.Path, value: Any, mode: int | None = None) -> None:
    atomic_write_text(path, json.dumps(value, ensure_ascii=False, separators=(",", ":")) + "\n", mode)


@contextlib.contextmanager
def file_lock(lock_path: pathlib.Path, create_parent: bool = True):
    key = str(lock_path.resolve())
    with _TABLE_LOCKS_GUARD:
        thread_lock = _TABLE_LOCKS.setdefault(key, threading.RLock())
    with thread_lock:
        if create_parent:
            lock_path.parent.mkdir(parents=True, exist_ok=True)
        elif not lock_path.parent.is_dir():
            raise FileNotFoundError(f"Lock parent directory no longer exists: {lock_path.parent}")
        fd = os.open(lock_path, os.O_CREAT | os.O_RDWR, 0o600)
        try:
            fcntl.flock(fd, fcntl.LOCK_EX)
            yield
        finally:
            with contextlib.suppress(OSError):
                fcntl.flock(fd, fcntl.LOCK_UN)
            os.close(fd)


def table_lock(folder: pathlib.Path):
    if not folder.is_dir():
        raise FileNotFoundError(f"Table directory does not exist: {folder}")
    return file_lock(folder / ".table.lock", create_parent=False)


def clean_cell_value(value: Any) -> str:
    value = str(value)
    if "\n" in value or "\r" in value or "\x00" in value:
        raise ValueError("Column values cannot contain line breaks or NUL characters.")
    return value


def cprint(text: str, color: str = GREEN) -> None:
    print(f"{color}{text}{RESET}")


def show_cli_banner() -> None:
    print(f"{CYAN}=================================================={RESET}")
    print(f"{BOLD}        CUSTOM DB MANAGER CLI - Version 1.0     {RESET}")
    print(f"{CYAN}=================================================={RESET}")
    print(f" Type '{YELLOW}help{RESET}' for commands or '{RED}exit{RESET}' to quit.\n")


def valid_name(name: str, what: str = "name") -> str:
    # Preserve the original CLI's support for spaces in database/table names,
    # while preventing path traversal or control characters.
    if (not name or name in {".", ".."} or "/" in name or "\x00" in name
            or len(name.encode("utf-8")) > 200 or any(ord(ch) < 32 for ch in name)):
        raise ValueError(f"Invalid {what}: path separators and control characters are not allowed.")
    return name


def valid_backup_name(name: str) -> str:
    if not name or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,63}", name):
        raise ValueError("Invalid backup name: spaces are not allowed; use letters, numbers, '.', '_' or '-'.")
    return name


def db_dir(db: str) -> pathlib.Path:
    valid_name(db, "database name")
    return DB_ROOT / db


def dirs(db: str) -> dict[str, pathlib.Path]:
    base = db_dir(db)
    return {
        "base": base,
        "tables": base / "tables",
        "api": base / "api",
        "secrets": base / "secrets",
        "backups": base / "backups",
        "history": base / ".cli_history",
        "backup_cfg": base / "secrets" / "backup_configs.cfg",
        "schedule_cfg": base / "secrets" / "backup_schedule.cfg",
        "keys_cfg": base / "secrets" / "database.cfg",
        "secrets_env": base / "secrets" / "secrets.env",
    }


def migrate_legacy_storage() -> None:
    """Migrate former global settings into independent per-database copies once."""
    runtime = ROOT / "runtime"
    marker = runtime / ".legacy_storage_migrated"
    if marker.exists():
        return
    legacy_secrets = ROOT / "secrets"
    legacy_backups = ROOT / "backups"
    runtime.mkdir(parents=True, exist_ok=True)
    databases = [p for p in DB_ROOT.iterdir() if p.is_dir()] if DB_ROOT.exists() else []
    if legacy_secrets.exists():
        # Old global backup daemons must not continue operating on the old layout.
        for pid_file in legacy_secrets.glob("backup_*.pid"):
            # Use the same safe identity-aware process-tree termination as the
            # current service manager; never signal a bare, potentially reused PID.
            with contextlib.suppress(Exception):
                stop_pid_file(pid_file)
        for base in databases:
            target = base / "secrets"
            target.mkdir(parents=True, exist_ok=True)
            for filename in ("secrets.env", "database.cfg", "backup_configs.cfg", "backup_schedule.cfg"):
                source = legacy_secrets / filename
                dest = target / filename
                if source.is_file() and (not dest.exists() or dest.stat().st_size == 0):
                    shutil.copy2(source, dest)
                    os.chmod(dest, 0o600)
            schedule = target / "backup_schedule.cfg"
            if schedule.exists():
                # Do not silently start legacy global jobs against a different database.
                lines = []
                for line in schedule.read_text(encoding="utf-8", errors="replace").splitlines():
                    if "=" in line:
                        name, value = line.split("=", 1)
                        _, sep, interval = value.partition(":")
                        lines.append(f"{name}=false:{interval if sep and interval else '1h'}")
                if lines: atomic_write_text(schedule, "\n".join(lines) + "\n", 0o600)
        archived_name = "pending-global-secrets" if not databases else "legacy-global-secrets"
        archived = runtime / archived_name
        if archived.exists(): archived = runtime / f"{archived_name}-{int(time.time())}"
        with contextlib.suppress(OSError): legacy_secrets.rename(archived)
    if legacy_backups.exists():
        archived = runtime / "legacy-global-backups"
        if archived.exists(): archived = runtime / f"legacy-global-backups-{int(time.time())}"
        with contextlib.suppress(OSError): legacy_backups.rename(archived)
    atomic_write_text(marker, "migrated\n", 0o600)


def write_api_server_stub(db: str, api_type: str, api_dir: pathlib.Path) -> None:
    path = api_dir / "server.py"
    content = (
        "#!/usr/bin/env bash\n"
        "# DB_MANAGER_EXT_SERVER_STUB\n"
        f"exec bash {shlex.quote(str(SHELL_SCRIPT))} --db-manager-internal --serve {shlex.quote(db)} {shlex.quote(api_type)}\n"
    )
    atomic_write_text(path, content, 0o700)


def write_backup_server_stub(db: str, secrets_dir: pathlib.Path) -> None:
    path = secrets_dir / "backup_server.py"
    content = (
        "#!/usr/bin/env bash\n"
        "# DB_MANAGER_EXT_BACKUP_STUB\n"
        f"exec bash {shlex.quote(str(SHELL_SCRIPT))} --db-manager-internal --worker {shlex.quote(db)} \"$1\" \"${{2:-300}}\"\n"
    )
    atomic_write_text(path, content, 0o700)


def ensure_db_layout(db: str) -> dict[str, pathlib.Path]:
    migrate_legacy_storage()
    d = dirs(db)
    for key in ("tables", "api", "secrets", "backups"):
        d[key].mkdir(parents=True, exist_ok=True)
    pending = ROOT / "runtime" / "pending-global-secrets"
    if pending.is_dir():
        for filename in ("secrets.env", "database.cfg", "backup_configs.cfg", "backup_schedule.cfg"):
            src, dst = pending / filename, d["secrets"] / filename
            if src.is_file() and (not dst.exists() or dst.stat().st_size == 0):
                shutil.copy2(src, dst); os.chmod(dst, 0o600)
        schedule = d["secrets"] / "backup_schedule.cfg"
        if schedule.exists():
            safe_lines = []
            for line in schedule.read_text(encoding="utf-8", errors="replace").splitlines():
                if "=" in line:
                    fn, value = line.split("=", 1); _, sep, interval = value.partition(":")
                    safe_lines.append(f"{fn}=false:{interval if sep and interval else '1h'}")
            if safe_lines: atomic_write_text(schedule, "\n".join(safe_lines) + "\n", 0o600)
        archived = ROOT / "runtime" / "legacy-global-secrets"
        if archived.exists(): archived = ROOT / "runtime" / f"legacy-global-secrets-{int(time.time())}"
        with contextlib.suppress(OSError): pending.rename(archived)
    write_backup_server_stub(db, d["secrets"])
    for api_type in ("public", "secret"):
        api_dir = d["api"] / api_type
        api_dir.mkdir(parents=True, exist_ok=True)
        write_api_server_stub(db, api_type, api_dir)
        if api_type == "public":
            perm = api_dir / "permissions.cfg"
            if not perm.exists():
                atomic_write_text(
                    perm,
                    "show_tables=false\ndump_db=false\nselect_from=false\ninsert_into=false\n"
                    "create_table=false\ndrop_table=false\ndelete_from=false\ndelete_record=false\n"
                    "create_column=false\ndrop_column=false\nshow_columns=false\nrename_column=false\n"
                    "update=false\nrename_table=false\n", 0o600)
    if not (d["base"] / f"{db}.db").exists():
        atomic_write_text(d["base"] / f"{db}.db",
                          json.dumps({"database": db, "tables": {}}, indent=2) + "\n", 0o600)
    if not d["backup_cfg"].exists() or d["backup_cfg"].stat().st_size == 0:
        write_backup_config(d["backup_cfg"], default_backup_config())
    if not d["schedule_cfg"].exists() or d["schedule_cfg"].stat().st_size == 0:
        atomic_write_text(d["schedule_cfg"], "backup=false:1h\nbackup_delete=false:1d\n", 0o600)
    if not d["keys_cfg"].exists():
        d["keys_cfg"].touch(mode=0o600)
    if not d["secrets_env"].exists():
        d["secrets_env"].touch(mode=0o600)
    with contextlib.suppress(OSError):
        os.chmod(d["secrets"], 0o700)
        os.chmod(d["keys_cfg"], 0o600)
        os.chmod(d["secrets_env"], 0o600)
    return d


def default_backup_config() -> dict[str, dict[str, str]]:
    return {
        "General": {"default_backup_name": "auto", "auto_compression": "true", "verify_integrity": "false", "backup_storage_path": ""},
        "Retention": {"max_backups": "10", "auto_cleanup": "false", "keep_daily": "false", "keep_weekly": "false"},
        "Schedule": {"default_interval": "1h", "background_daemon": "true", "notify_on_completion": "false"},
        "Security": {"encrypt_backups": "false", "storage_permissions": "700", "sign_manifest": "false"},
    }


def write_backup_config(path: pathlib.Path, cfg: dict[str, dict[str, str]]) -> None:
    lines = []
    for section, values in cfg.items():
        lines.append(f"[{section}]")
        lines.extend(f"{k}={v}" for k, v in values.items())
    path.parent.mkdir(parents=True, exist_ok=True)
    atomic_write_text(path, "\n".join(lines) + "\n", 0o600)


def read_backup_config(db: str) -> dict[str, dict[str, str]]:
    d = ensure_db_layout(db)
    cfg = default_backup_config()
    section = None
    for raw in d["backup_cfg"].read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1]
            cfg.setdefault(section, {})
        elif "=" in line and section:
            k, v = line.split("=", 1)
            cfg.setdefault(section, {})[k.strip()] = v.strip()
    return cfg


def cfg_value(cfg: dict[str, dict[str, str]], key: str, default: str = "") -> str:
    for values in cfg.values():
        if key in values:
            return values[key]
    return default


def backup_directory(db: str, cfg: dict[str, dict[str, str]] | None = None, create: bool = True) -> pathlib.Path:
    """Return the per-database backup directory, optionally on another filesystem.

    A configured external path must already exist and reside on a different
    filesystem from db_manage. This prevents a missing secondary disk from
    silently becoming an ordinary directory on the primary disk.
    """
    d = dirs(db)
    if cfg is None:
        cfg = read_backup_config(db)
    raw = cfg_value(cfg, "backup_storage_path", "").strip()
    if not raw:
        target = d["backups"]
        if create:
            target.mkdir(parents=True, exist_ok=True)
        return target

    base = pathlib.Path(raw).expanduser()
    if not base.is_absolute():
        raise ValueError("backup_storage_path must be an absolute directory on the secondary disk.")
    try:
        base = base.resolve(strict=True)
    except OSError as exc:
        raise RuntimeError(f"Configured backup storage is unavailable: {raw} ({exc}).") from exc
    if not base.is_dir():
        raise ValueError("backup_storage_path must point to an existing directory.")
    try:
        primary_device = ROOT.resolve().stat().st_dev
        backup_device = base.stat().st_dev
    except OSError as exc:
        raise RuntimeError(f"Cannot verify backup storage filesystem: {exc}") from exc
    if backup_device == primary_device:
        raise ValueError("backup_storage_path must be on a different filesystem from the primary db_manage directory.")
    if not os.access(base, os.W_OK | os.X_OK):
        raise PermissionError(f"Backup storage directory is not writable: {base}")
    target = base / valid_name(db, "database name")
    if create:
        target.mkdir(parents=True, exist_ok=True)
        os.chmod(target, 0o700)
    return target


def validate_backup_storage_path(value: str) -> str:
    value = value.strip()
    if not value:
        return ""
    base = pathlib.Path(value).expanduser()
    if not base.is_absolute():
        raise ValueError("backup_storage_path must be an absolute path. Use an empty value to restore local storage.")
    if not base.exists() or not base.is_dir():
        raise ValueError("The selected backup_storage_path must already exist and be mounted.")
    resolved = base.resolve(strict=True)
    if resolved.stat().st_dev == ROOT.resolve().stat().st_dev:
        raise ValueError("The selected directory is on the primary filesystem. Choose a directory on the secondary disk.")
    if not os.access(resolved, os.W_OK | os.X_OK):
        raise PermissionError(f"The selected directory is not writable: {resolved}")
    return str(resolved)


def migrate_backup_files(old_dir: pathlib.Path, new_dir: pathlib.Path) -> int:
    """Copy existing backup archives/manifests to the newly selected store."""
    if old_dir.resolve() == new_dir.resolve():
        return 0
    if not old_dir.is_dir():
        return 0
    new_dir.mkdir(parents=True, exist_ok=True)
    copied = 0
    for item in old_dir.iterdir():
        if not item.is_file():
            continue
        destination = new_dir / item.name
        if not destination.exists():
            shutil.copy2(item, destination)
            copied += 1
    return copied


def parse_interval(value: str) -> int:
    m = re.fullmatch(r"\s*(\d+)\s*(sec|s|min|m|h|d|w|y)?\s*", value.lower())
    if not m:
        raise ValueError("Invalid interval. Use values such as 30sec, 5min, 1h, 1d or 1w.")
    n = int(m.group(1))
    unit = m.group(2) or "sec"
    factors = {"sec": 1, "s": 1, "min": 60, "m": 60, "h": 3600, "d": 86400, "w": 604800, "y": 31536000}
    if n < 1:
        raise ValueError("Interval must be greater than zero.")
    return n * factors[unit]


def parse_bool(value: str) -> str:
    v = value.lower()
    if v not in ("true", "false"):
        raise ValueError("Value must be 'true' or 'false'.")
    return v


def key_records(db: str) -> list[tuple[str, str]]:
    d = ensure_db_layout(db)
    result = []
    for line in d["keys_cfg"].read_text(encoding="utf-8", errors="replace").splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            if k.strip().startswith("secret_key_") and v.strip():
                result.append((k.strip(), v.strip()))
    return result


def write_key_records(db: str, records: list[tuple[str, str]]) -> None:
    d = ensure_db_layout(db)
    tmp = d["keys_cfg"].with_suffix(".tmp")
    atomic_write_text(d["keys_cfg"], "".join(f"{k}={v}\n" for k, v in records), 0o600)


def register_key(db: str, value: str) -> None:
    if not value or any(ch in value for ch in "\n=/\r"):
        raise ValueError("API keys cannot contain '/', '=' or line breaks.")
    records = key_records(db)
    if any(existing == value for _, existing in records): return
    idx = 1
    names = {name for name, _ in records}
    while f"secret_key_{idx}" in names: idx += 1
    records.append((f"secret_key_{idx}", value))
    write_key_records(db, records)


def resolve_key(db: str, raw: str) -> str:
    for name, value in key_records(db):
        if raw == name:
            return value
    return raw


def show_keys(db: str) -> None:
    records = key_records(db)
    print(f"{CYAN}{BOLD}Configured API Secret Keys ({db}):{RESET}")
    if not records:
        print("  (No secret keys found)")
    for name, value in records:
        print(f"  - {CYAN}{name}{RESET}: {value}")


def api_cfg_path(db: str, api_type: str) -> pathlib.Path:
    if api_type not in ("public", "secret"):
        raise ValueError("API type must be 'public' or 'secret'.")
    return ensure_db_layout(db)["api"] / api_type / "api.cfg"


def read_kv(path: pathlib.Path) -> dict[str, str]:
    data: dict[str, str] = {}
    if path.exists():
        for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
            if "=" in raw:
                k, v = raw.split("=", 1)
                data[k.strip()] = v.strip()
    return data


def write_kv(path: pathlib.Path, data: dict[str, str], mode: int = 0o600) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    atomic_write_text(path, "".join(f"{k}={v}\n" for k, v in data.items()), mode)


def api_pair(db: str, api_type: str) -> tuple[str, str]:
    cfg = read_kv(api_cfg_path(db, api_type))
    k1 = cfg.get("SecretKey1", "")
    k2 = cfg.get("SecretKey2", "")
    if not k1 or not k2 or hmac.compare_digest(k1, k2):
        raise ValueError(f"API ({api_type}) must have two different secret keys configured.")
    return k1, k2


def api_prefix(cfg: dict[str, str]) -> str:
    name = cfg.get("Name", "api")
    slug = re.sub(r"[^A-Za-z0-9_.-]+", "-", name.strip()).strip("-._") or "api"
    return "/customdb/" + urllib.parse.quote(slug, safe="-._")


def server_main(db: str, api_type: str) -> None:
    d = ensure_db_layout(db)
    cfg_file = api_cfg_path(db, api_type)
    cfg = read_kv(cfg_file)
    if not cfg:
        raise RuntimeError(f"API ({api_type}) is not configured.")
    key1, key2 = api_pair(db, api_type)
    port = int(cfg.get("Port", "8080"))
    address = cfg.get("Address", "localhost") or "localhost"
    proto = cfg.get("Protocol", "http").lower()
    debug = cfg.get("ApiDebug", "true").lower() == "true"
    base_path = api_prefix(cfg)
    tables_dir = d["tables"]
    perm_file = d["api"] / "public" / "permissions.cfg"

    class Handler(http.server.BaseHTTPRequestHandler):
        server_version = "CustomDB/1.0"

        def log_message(self, fmt: str, *args: Any) -> None:
            # Avoid logging query strings: the URL contains the two credentials.
            sys.stderr.write(f"{self.client_address[0]} - {self.command} request\n")

        def send_json(self, code: int, data: dict[str, Any]) -> None:
            if debug:
                if "message" in data:
                    data["message"] += " - Powered by Afonso Carreira.Inc"
                else:
                    data["message"] = "Powered by Afonso Carreira.Inc"
                data["api_type"] = api_type
            payload = json.dumps(data, indent=2, ensure_ascii=False).encode("utf-8")
            self.send_response(code)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(payload)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(payload)

        def send_html(self, code: int, data: dict[str, Any]) -> None:
            tables = data.get("tables", [])
            table_items = "".join(f"<li>📁 &nbsp; {html.escape(str(t))}</li>" for t in tables)
            if not table_items: table_items = "<li>(No tables found)</li>"
            footer_html = '<div class="footer">Powered by Afonso Carreira.Inc</div>' if debug else ""
            type_html = f"<p><strong>API Type:</strong> <code>{html.escape(api_type.upper())}</code></p>" if debug else ""
            message = html.escape(str(data.get("message", "Database API running successfully!")))
            payload_data = html.escape(json.dumps(data, indent=2, ensure_ascii=False))
            html_doc = f"""<!DOCTYPE html>
<html lang="en"><head><meta charset="UTF-8"><title>Database API Dashboard</title>
<style>body {{ font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; background: #0f172a; color: #f8fafc; margin: 0; padding: 30px; }}
.container {{ max-width: 850px; margin: 0 auto; background: #1e293b; padding: 40px; border-radius: 12px; border: 1px solid #334155; }}
h1 {{ color: #38bdf8; border-bottom: 2px solid #334155; padding-bottom: 12px; }}
pre {{ background: #0f172a; padding: 20px; border-radius: 8px; overflow-x: auto; color: #38bdf8; border: 1px solid #334155; }}
ul {{ list-style-type: none; padding: 0; }} li {{ background: #334155; margin: 8px 0; padding: 12px 16px; border-radius: 6px; }}
.status-box {{ background: #064e3b; border: 1px solid #059669; color: #34d399; padding: 12px 16px; border-radius: 6px; margin-bottom: 20px; }}
.footer {{ margin-top: 20px; text-align: center; color: #38bdf8; font-weight: bold; }}</style></head>
<body><div class="container"><h1>Database Server Dashboard <span>{html.escape(db)}</span></h1>
<div class="status-box">✓ {message}</div>{type_html}<p><strong>Protocol:</strong> <code>{html.escape(proto.upper())}</code></p>
<h3>Active Database Tables:</h3><ul>{table_items}</ul><h3>Output (JSON):</h3><pre>{payload_data}</pre>{footer_html}
</div></body></html>"""
            body = html_doc.encode("utf-8")
            self.send_response(code)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)

        def permission(self, name: str) -> bool:
            if api_type == "secret":
                return True
            permissions = read_kv(perm_file)
            return permissions.get(name, "false").lower() == "true"

        def authenticate(self, parsed: urllib.parse.SplitResult) -> bool:
            """Authenticate with Authorization: Bearer key1/key2 or legacy ?key=.

            A supplied but malformed Authorization header is rejected instead of
            silently falling back to query credentials. This prevents ambiguous
            mixed-auth requests and keeps credentials out of URLs when headers
            are available.
            """
            header_value = (self.headers.get("Authorization", "") or "").strip()
            if header_value:
                pieces = header_value.split(None, 1)
                if len(pieces) != 2 or pieces[0].casefold() != "bearer":
                    return False
                credential = urllib.parse.unquote(pieces[1].strip())
            else:
                values = urllib.parse.parse_qs(parsed.query, keep_blank_values=True).get("key", [])
                if len(values) != 1:
                    return False
                credential = values[0]

            separator = next((sep for sep in ("/", ":", ",") if sep in credential), None)
            if separator is None:
                return False
            first, second = credential.split(separator, 1)
            if not first or not second:
                return False
            return (hmac.compare_digest(first.strip(), key1)
                    and hmac.compare_digest(second.strip(), key2))

        def do_GET(self) -> None: self._handle_api("GET")
        def do_POST(self) -> None: self._handle_api("POST")
        def do_PUT(self) -> None: self._handle_api("PUT")
        def do_DELETE(self) -> None: self._handle_api("DELETE")

        def _handle_api(self, method: str) -> None:
            parsed = urllib.parse.urlsplit(self.path)
            if not self.authenticate(parsed):
                self.send_json(401, {"status": "error", "error": "Unauthorized: both API keys are required."})
                return
            path = parsed.path
            if path == base_path or path == base_path + "/":
                path = "/"
            elif path.startswith(base_path + "/"):
                path = path[len(base_path):]
            else:
                self.send_json(404, {"status": "error", "error": "Invalid API base path."})
                return
            path = path.rstrip("/") or "/"
            if api_type == "public":
                now = time.monotonic()
                with self.server.rate_limit_lock:
                    recent = self.server.requests_by_ip
                    arr = [t for t in recent.get(self.client_address[0], []) if now - t < 5]
                    if len(arr) >= 10:
                        self.send_json(429, {"status": "error", "error": "Rate limit exceeded."})
                        return
                    arr.append(now)
                    recent[self.client_address[0]] = arr
            body: dict[str, Any] = {}
            if method in ("POST", "PUT"):
                length = int(self.headers.get("Content-Length", "0") or 0)
                if length > 2_000_000:
                    self.send_json(413, {"status": "error", "error": "Request body too large."})
                    return
                raw = self.rfile.read(length) if length else b""
                if raw:
                    try:
                        body = json.loads(raw.decode("utf-8"))
                        if not isinstance(body, dict): body = {"data": body}
                    except Exception:
                        body = {"raw_body": raw.decode("utf-8", errors="ignore")}
            query = {k: v[0] if len(v) == 1 else v for k, v in urllib.parse.parse_qs(parsed.query).items() if k != "key"}
            params = {**query, **body}
            out: dict[str, Any] = {"status": "success", "database": db, "method": method,
                                   "endpoint": path, "protocol": proto}
            code = 200
            try:
                if path.startswith(("/api_", "/create_database", "/drop_database", "/show_databases", "/use")):
                    raise PermissionError(f"API restriction: endpoint '{path}' is prohibited.")
                if path in ("/", "/status"):
                    tables = sorted(p.name for p in tables_dir.iterdir() if p.is_dir())
                    out.update({"message": "Database API running successfully!", "tables": tables,
                                "base_path": base_path})
                    accept_header = self.headers.get("Accept", "")
                    if "text/html" in accept_header or path == "/":
                        self.send_html(code, out)
                        return
                elif path == "/dump_db":
                    if not self.permission("dump_db"): raise PermissionError("Permission denied for 'dump_db'.")
                    meta_file = d["base"] / f"{db}.db"
                    metadata: Any = meta_file.read_text(encoding="utf-8") if meta_file.exists() else ""
                    with contextlib.suppress(Exception): metadata = json.loads(metadata)
                    out.update({"message": f"Universal database dump for '{db}'.", "metadata": metadata,
                                "tables": sorted(p.name for p in tables_dir.iterdir() if p.is_dir())})
                elif path == "/show_tables":
                    if not self.permission("show_tables"): raise PermissionError("Permission denied for 'show_tables'.")
                    out["tables"] = sorted(p.name for p in tables_dir.iterdir() if p.is_dir())
                elif path.startswith(("/select_from/", "/select/")):
                    if not self.permission("select_from"): raise PermissionError("Permission denied for 'select_from'.")
                    table = valid_name(urllib.parse.unquote(path.rstrip("/").split("/")[-1]), "table name")
                    cols, rows, _ = read_table(db, table)
                    filter_column = query.get("column")
                    filter_value = query.get("value")
                    if filter_column is not None:
                        if filter_column not in cols: raise ValueError(f"Column '{filter_column}' does not exist.")
                        rows = search_rows(db, table, filter_column, str(filter_value if filter_value is not None else ""), cols, rows)
                    out.update({"table": table, "columns": cols, "records": rows})
                elif path.startswith(("/insert_into/", "/insert/")):
                    if not self.permission("insert_into"): raise PermissionError("Permission denied for 'insert_into'.")
                    table = valid_name(urllib.parse.unquote(path.rstrip("/").split("/")[-1]), "table name")
                    values = params.get("data") or params.get("record") or body.get("raw_body")
                    if values is None or values == "": raise ValueError("Missing data to insert.")
                    # api_append_record holds the table's RLock + flock across
                    # schema lookup, ID allocation, shard write and manifest publish.
                    inserted = api_append_record(db, table, values)
                    out.update({"message": f"Data successfully appended to table '{table}'.",
                                "inserted_data": inserted, "append_only": True,
                                "storage": "locked_atomic"})
                elif path.startswith("/create_table/"):
                    if not self.permission("create_table"): raise PermissionError("Permission denied for 'create_table'.")
                    table = valid_name(path.rstrip("/").split("/")[-1], "table name")
                    tdir = tables_dir / table
                    with file_lock(d["base"] / ".schema.lock"):
                        if tdir.exists(): code = 409; raise FileExistsError(f"Table '{table}' already exists.")
                        tdir.mkdir(parents=True)
                        atomic_write_text(tdir / "columns", "id\n", 0o600)
                        (tdir / "tables").touch()
                        atomic_write_text(tdir / ".index_enabled", "true\n", 0o600)
                        atomic_write_text(tdir / ".next_id", "1\n", 0o600)
                    out["message"] = f"Table '{table}' created successfully."
                elif path.startswith("/drop_table/"):
                    if not self.permission("drop_table"): raise PermissionError("Permission denied for 'drop_table'.")
                    table = valid_name(path.rstrip("/").split("/")[-1], "table name")
                    tdir = tables_dir / table
                    with file_lock(d["base"] / ".schema.lock"):
                        if not tdir.is_dir(): code = 404; raise FileNotFoundError(f"Table '{table}' does not exist.")
                        with table_lock(tdir):
                            shutil.rmtree(tdir)
                    out["message"] = f"Table '{table}' dropped successfully."
                elif path.startswith("/delete_from/"):
                    if not self.permission("delete_from"): raise PermissionError("Permission denied for 'delete_from'.")
                    table = valid_name(path.rstrip("/").split("/")[-1], "table name")
                    tdir = tables_dir / table
                    if not tdir.exists(): code = 404; raise FileNotFoundError(f"Table '{table}' does not exist.")
                    with edit_table(db, table) as (_cols, rows, _data_file):
                        deleted_count = len(rows)
                        rows.clear()
                    out["message"] = f"All {deleted_count} records deleted from table '{table}'."
                elif path.startswith("/delete_record/"):
                    if not self.permission("delete_record"): raise PermissionError("Permission denied for 'delete_record'.")
                    bits = path.strip("/").split("/")
                    if len(bits) < 3: code = 400; raise ValueError("Use /delete_record/<table>/<record>")
                    table = valid_name(urllib.parse.unquote(bits[1]), "table name")
                    target = urllib.parse.unquote("/".join(bits[2:]))
                    # api_delete_record holds the table's RLock + flock for the
                    # complete read/modify/atomic-generation-publish transaction.
                    removed_count = api_delete_record(db, table, target)
                    if not removed_count:
                        code = 404
                        raise FileNotFoundError("Record not found.")
                    out.update({"message": "Record deleted successfully.",
                                "deleted_records": removed_count, "storage": "locked_atomic"})
                else:
                    out["message"] = f"Endpoint '{path}' reached and executed successfully."
            except PermissionError as exc:
                code = 403; out = {"status": "error", "database": db, "endpoint": path, "error": str(exc)}
            except FileNotFoundError as exc:
                code = code if code != 200 else 404; out = {"status": "error", "database": db, "endpoint": path, "error": str(exc)}
            except FileExistsError as exc:
                code = 409; out = {"status": "error", "database": db, "endpoint": path, "error": str(exc)}
            except Exception as exc:
                code = code if code != 200 else 400; out = {"status": "error", "database": db, "endpoint": path, "error": str(exc)}
            self.send_json(code, out)

    class ThreadedHTTPServer(http.server.ThreadingHTTPServer):
        daemon_threads = True
        allow_reuse_address = True

    server = ThreadedHTTPServer((address, port), Handler)
    server.requests_by_ip = {}
    server.rate_limit_lock = threading.Lock()
    if proto == "https":
        api_dir = cfg_file.parent
        cert = api_dir / "server.crt"
        key = api_dir / "server.key"
        pem = api_dir / "server.pem"
        if not cert.exists() or not key.exists():
            subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-keyout", str(key),
                            "-out", str(cert), "-days", "365", "-nodes", "-subj", "/CN=localhost"],
                           check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            pem.write_bytes(cert.read_bytes() + key.read_bytes())
            os.chmod(key, 0o600); os.chmod(pem, 0o600)
        import ssl
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(str(cert), str(key))
        server.socket = context.wrap_socket(server.socket, server_side=True)
    print(f"[API] {db}/{api_type} listening at {proto}://{address}:{port}{base_path}/", flush=True)
    server.serve_forever()


def process_meta_path(pid_file: pathlib.Path) -> pathlib.Path:
    return pid_file.with_name(pid_file.name + ".meta.json")


def read_proc_stat(pid: int) -> dict[str, int] | None:
    try:
        raw = pathlib.Path(f"/proc/{pid}/stat").read_text(encoding="utf-8")
        close = raw.rfind(")")
        fields = raw[close + 2:].split()
        return {"ppid": int(fields[1]), "pgid": int(fields[2]), "start_ticks": int(fields[19])}
    except (OSError, ValueError, IndexError):
        return None


def proc_cmdline(pid: int) -> list[str]:
    try:
        raw = pathlib.Path(f"/proc/{pid}/cmdline").read_bytes()
        return [x.decode("utf-8", errors="replace") for x in raw.split(b"\0") if x]
    except OSError:
        return []


def process_token_pids(token: str) -> list[int]:
    """Find every live process carrying this service's unique token.

    Unlike killing only the Bash PID, this also finds the embedded Python
    interpreter and terminal shells even when a desktop terminal reparents
    them into a different process group.
    """
    if not token:
        return []
    expected = f"DBM_PROCESS_TOKEN={token}".encode()
    found: list[int] = []
    try:
        entries = list(pathlib.Path("/proc").iterdir())
    except OSError:
        return found
    for entry in entries:
        if not entry.name.isdigit():
            continue
        try:
            env = (entry / "environ").read_bytes().split(b"\0")
            if expected in env:
                found.append(int(entry.name))
        except (OSError, ValueError):
            continue
    return found


def process_group_has_token(pgid: int, token: str) -> bool:
    return any((info := read_proc_stat(pid)) and info["pgid"] == pgid
               for pid in process_token_pids(token))


def pid_value(pid_file: pathlib.Path) -> int | None:
    try:
        raw = pid_file.read_text(encoding="utf-8").strip()
        if raw.startswith("{"):
            raw = str(json.loads(raw).get("pid", ""))
        return int(raw)
    except (OSError, ValueError, TypeError, json.JSONDecodeError):
        return None


def write_managed_pid(pid_file: pathlib.Path, proc: subprocess.Popen, token: str, role: str) -> None:
    info = read_proc_stat(proc.pid)
    if not info:
        raise RuntimeError(f"Could not read process identity for PID {proc.pid}.")
    pid_file.parent.mkdir(parents=True, exist_ok=True)
    atomic_write_text(pid_file, f"{proc.pid}\n", 0o600)
    meta = {
        "pid": proc.pid,
        "pgid": info["pgid"],
        "start_ticks": info["start_ticks"],
        "token": token,
        "role": role,
        "script": str(SHELL_SCRIPT),
    }
    meta_path = process_meta_path(pid_file)
    atomic_write_text(meta_path, json.dumps(meta, indent=2) + "\n", 0o600)
    os.chmod(pid_file, 0o600)
    os.chmod(meta_path, 0o600)


def remove_managed_pid(pid_file: pathlib.Path, token: str | None = None) -> None:
    meta_path = process_meta_path(pid_file)
    if token and meta_path.exists():
        try:
            if json.loads(meta_path.read_text(encoding="utf-8")).get("token") != token:
                return
        except Exception:
            return
    with contextlib.suppress(FileNotFoundError): pid_file.unlink()
    with contextlib.suppress(FileNotFoundError): meta_path.unlink()


def _is_embedded_manager_script(candidate: str) -> bool:
    try:
        path = pathlib.Path(candidate)
        if not path.is_file() or path.suffix.lower() != ".sh":
            return False
        content = path.read_text(encoding="utf-8", errors="ignore")
        return "#__DBM_PYTHON_BEGIN__" in content and "--db-manager-internal" in content
    except OSError:
        return False


def legacy_managed_command(pid: int, pid_file: pathlib.Path) -> bool:
    """Identify this application's older PID-file formats without trusting PID alone."""
    cmd = proc_cmdline(pid)
    if not cmd:
        return False
    if pid_file.name == "api.pid":
        api_type = pid_file.parent.name
        db = pid_file.parents[2].name
        # Previous unified editions ran `bash <manager.sh> --db-manager-internal --serve ...`.
        embedded = any(_is_embedded_manager_script(item) for item in cmd)
        if embedded and "--db-manager-internal" in cmd and "--serve" in cmd:
            return db in cmd and api_type in cmd
        # Earlier editions ran Python directly from the database's server.py.
        legacy_server = str(pid_file.parent / "server.py")
        return legacy_server in cmd and "server.py" in " ".join(cmd)
    if pid_file.name.startswith("backup_") and pid_file.name.endswith(".pid"):
        func = pid_file.name[len("backup_"):-len(".pid")]
        embedded = any(_is_embedded_manager_script(item) for item in cmd)
        if embedded and "--db-manager-internal" in cmd and "--worker" in cmd:
            # Database-scoped worker PID files carry the database in their path.
            if pid_file.parent.parent.name == "secrets" and pid_file.parent.parent.parent.name == "database":
                db = pid_file.parent.parent.parent.name
                return db in cmd and func in cmd
            # Old global workers had no database-scoped folder; match function and script.
            return func in cmd
        # The initial manager launched the generated backup_server.py directly.
        legacy_worker = str(pid_file.parent / "backup_server.py")
        return legacy_worker in cmd and func in cmd
    return False


def process_alive(pid_file: pathlib.Path) -> bool:
    if not pid_file.exists():
        return False
    pid = pid_value(pid_file)
    if pid is None:
        remove_managed_pid(pid_file)
        return False
    meta_path = process_meta_path(pid_file)
    if meta_path.exists():
        try:
            meta = json.loads(meta_path.read_text(encoding="utf-8"))
            pgid = int(meta.get("pgid", pid))
            token = str(meta.get("token", ""))
            if token and process_token_pids(token):
                return True
        except (OSError, ValueError, TypeError, json.JSONDecodeError):
            pass
        remove_managed_pid(pid_file)
        return False
    # Compatibility for PIDs created by previous versions: only treat a PID
    # as ours when its command line identifies this exact embedded service.
    return bool(read_proc_stat(pid) and legacy_managed_command(pid, pid_file))


def process_tree(root_pid: int) -> list[int]:
    """Return descendants of root_pid (children first) using /proc PPID data."""
    ppid_map: dict[int, list[int]] = {}
    try:
        entries = pathlib.Path("/proc").iterdir()
        for entry in entries:
            if entry.name.isdigit():
                info = read_proc_stat(int(entry.name))
                if info:
                    ppid_map.setdefault(info["ppid"], []).append(int(entry.name))
    except OSError:
        return [root_pid]
    ordered: list[int] = []
    stack = [(root_pid, False)]
    seen: set[int] = set()
    while stack:
        pid, visited = stack.pop()
        if visited:
            ordered.append(pid)
            continue
        if pid in seen:
            continue
        seen.add(pid)
        stack.append((pid, True))
        for child in ppid_map.get(pid, []):
            stack.append((child, False))
    return ordered


def stop_pid_file(pid_file: pathlib.Path) -> bool:
    if not pid_file.exists() and not process_meta_path(pid_file).exists():
        return False
    pid = pid_value(pid_file)
    meta_path = process_meta_path(pid_file)
    stopped = False
    meta = {}
    if meta_path.exists():
        try:
            meta = json.loads(meta_path.read_text(encoding="utf-8"))
        except Exception:
            meta = {}
    token = str(meta.get("token", ""))
    pgid = int(meta.get("pgid", pid or -1)) if str(meta.get("pgid", pid or -1)).lstrip("-").isdigit() else -1

    # Current managed daemons get a unique environment token and a dedicated
    # process group. Killing the group always terminates the Bash wrapper, the
    # embedded Python interpreter and any subprocesses it spawned.
    managed_pids = process_token_pids(token) if token else []
    if token and managed_pids:
        # Signal each token-owned process, not merely the recorded Bash PID or
        # its process group. This also handles GUI terminal clients that reparent
        # their visible shell into another session/process group.
        for managed_pid in managed_pids:
            with contextlib.suppress(ProcessLookupError, PermissionError):
                os.kill(managed_pid, signal.SIGTERM)
        deadline = time.monotonic() + 2.5
        while time.monotonic() < deadline and process_token_pids(token):
            time.sleep(0.1)
        for managed_pid in process_token_pids(token):
            with contextlib.suppress(ProcessLookupError, PermissionError):
                os.kill(managed_pid, signal.SIGKILL)
        stopped = True
    elif pid and read_proc_stat(pid) and legacy_managed_command(pid, pid_file):
        info = read_proc_stat(pid) or {}
        group = info.get("pgid", -1)
        if group == pid:
            with contextlib.suppress(ProcessLookupError, PermissionError): os.killpg(group, signal.SIGTERM)
            time.sleep(0.25)
            with contextlib.suppress(ProcessLookupError, PermissionError): os.killpg(group, signal.SIGKILL)
        else:
            # Old workers could share the terminal's process group. Never kill
            # that group; terminate only the identified service's process tree.
            tree = process_tree(pid)
            for child in tree:
                with contextlib.suppress(ProcessLookupError, PermissionError): os.kill(child, signal.SIGTERM)
            time.sleep(0.25)
            for child in tree:
                with contextlib.suppress(ProcessLookupError, PermissionError): os.kill(child, signal.SIGKILL)
        stopped = True
    else:
        # Handle the narrow upgrade case where the old Bash parent died but its
        # child Python server remains in the old dedicated process group.
        remaining = process_token_pids(token) if token else []
        if remaining:
            for managed_pid in remaining:
                with contextlib.suppress(ProcessLookupError, PermissionError): os.kill(managed_pid, signal.SIGTERM)
            time.sleep(0.25)
            for managed_pid in process_token_pids(token):
                with contextlib.suppress(ProcessLookupError, PermissionError): os.kill(managed_pid, signal.SIGKILL)
            stopped = True

    remove_managed_pid(pid_file)
    return stopped or pid is not None


def process_env(token: str) -> dict[str, str]:
    env = os.environ.copy()
    env["DB_MANAGER_SCRIPT"] = str(SHELL_SCRIPT)
    env["DBM_PROCESS_TOKEN"] = token
    return env


def stop_backup_worker(db: str, func: str) -> bool:
    d = dirs(db)
    worker_stopped = stop_pid_file(d["secrets"] / f"backup_{func}.pid")
    viewer_stopped = stop_pid_file(d["secrets"] / f"backup_{func}_viewer.pid")
    return worker_stopped or viewer_stopped


def parse_args(raw: str) -> list[str]:
    # '&' is retained as a legacy separator; normal whitespace is also accepted.
    raw = raw.replace("&", " ")
    try: return shlex.split(raw)
    except ValueError: return raw.split()


def check_api_port_available(db: str, api_type: str, address: str, port: int) -> None:
    if DB_ROOT.exists():
        for base in DB_ROOT.iterdir():
            if not base.is_dir(): continue
            for kind in ("public", "secret"):
                if base.name == db and kind == api_type: continue
                cfg_path = base / "api" / kind / "api.cfg"
                cfg = read_kv(cfg_path)
                if cfg and cfg.get("Port", "8080") == str(port) and cfg.get("Address", "localhost") == address:
                    raise ValueError(f"Address '{address}' and port {port} are already configured for database '{base.name}' API '{kind}'.")


def prompt_value(label: str, default: str = "") -> str:
    suffix = f" [{default}]" if default else ""
    value = input(f"{label}{suffix}: ").strip()
    return value or default


def api_setup(db: str, api_type: str) -> None:
    ensure_db_layout(db)
    show_cli_banner()
    print(f"{CYAN}{BOLD}      API SETUP ({api_type.upper()}) FOR: {db}      {RESET}\n")
    name = prompt_value("Enter API Name", "api")
    if not name.strip(): raise ValueError("API name is required.")
    protocol = prompt_value("Enter Protocol (http or https)", "http").lower()
    if protocol not in ("http", "https"): raise ValueError("Protocol must be http or https.")
    address = prompt_value("Enter API Address", "localhost")
    port_text = prompt_value("Enter API Port", "8080")
    if not port_text.isdigit() or not (1 <= int(port_text) <= 65535): raise ValueError("Port must be between 1 and 65535.")
    port = int(port_text)
    check_api_port_available(db, api_type, address, port)
    debug = prompt_value("Enter API Debug (true or false)", "true").lower()
    if debug not in ("true", "false"): raise ValueError("API Debug must be true or false.")
    show_keys(db)
    key1 = resolve_key(db, getpass.getpass("Enter FIRST API Secret Key: ").strip())
    key2 = resolve_key(db, getpass.getpass("Enter SECOND API Secret Key: ").strip())
    if not key1 or not key2: raise ValueError("Both secret keys are required.")
    if any(ch in key1 + key2 for ch in "\n=/\r"): raise ValueError("API keys cannot contain '/', '=' or line breaks.")
    if hmac.compare_digest(key1, key2): raise ValueError("The two API keys must be different.")
    register_key(db, key1); register_key(db, key2)
    cfg_path = api_cfg_path(db, api_type)
    was_running = process_alive(cfg_path.parent / "api.pid")
    if was_running: stop_pid_file(cfg_path.parent / "api.pid")
    cfg = {"Name": name, "Protocol": protocol, "Address": address, "Port": str(port),
           "ApiDebug": debug, "SecretKey1": key1, "SecretKey2": key2}
    write_kv(cfg_path, cfg, 0o600)
    if was_running: api_start(db, api_type)
    cprint(f"API ({api_type}) setup completed successfully with two secret keys.")
    cprint(f"Base path: {protocol}://{address}:{port}{api_prefix(cfg)}/", CYAN)


def api_edit(db: str, api_type: str) -> None:
    show_cli_banner()
    path = api_cfg_path(db, api_type)
    cfg = read_kv(path)
    if not cfg: raise ValueError(f"API ({api_type}) is not configured.")
    cfg["Name"] = prompt_value("Enter new Name", cfg.get("Name", "api"))
    cfg["Protocol"] = prompt_value("Enter new Protocol", cfg.get("Protocol", "http")).lower()
    if cfg["Protocol"] not in ("http", "https"): raise ValueError("Protocol must be http or https.")
    cfg["Address"] = prompt_value("Enter new Address", cfg.get("Address", "localhost"))
    port = prompt_value("Enter new Port", cfg.get("Port", "8080"))
    if not port.isdigit() or not (1 <= int(port) <= 65535): raise ValueError("Invalid port.")
    check_api_port_available(db, api_type, cfg["Address"], int(port))
    cfg["Port"] = port
    cfg["ApiDebug"] = prompt_value("Enter new API Debug", cfg.get("ApiDebug", "true")).lower()
    if cfg["ApiDebug"] not in ("true", "false"): raise ValueError("API Debug must be true or false.")
    show_keys(db)
    cfg["SecretKey1"] = resolve_key(db, getpass.getpass("Enter FIRST API Secret Key: ").strip())
    cfg["SecretKey2"] = resolve_key(db, getpass.getpass("Enter SECOND API Secret Key: ").strip())
    if not cfg["SecretKey1"] or not cfg["SecretKey2"] or hmac.compare_digest(cfg["SecretKey1"], cfg["SecretKey2"]):
        raise ValueError("Two different, non-empty secret keys are required.")
    if any(ch in cfg["SecretKey1"] + cfg["SecretKey2"] for ch in "\n=/\r"):
        raise ValueError("API keys cannot contain '/', '=' or line breaks.")
    register_key(db, cfg["SecretKey1"]); register_key(db, cfg["SecretKey2"])
    was_running = process_alive(path.parent / "api.pid")
    if was_running: stop_pid_file(path.parent / "api.pid")
    write_kv(path, cfg, 0o600)
    if was_running: api_start(db, api_type)
    cprint("API configuration updated successfully.")


def api_start(db: str, api_type: str) -> None:
    d = ensure_db_layout(db)
    cfg_path = api_cfg_path(db, api_type)
    cfg = read_kv(cfg_path)
    if not cfg: raise ValueError(f"API ({api_type}) is not configured. Run api_setup {api_type} first.")
    api_pair(db, api_type)
    api_dir = cfg_path.parent
    pid_file = api_dir / "api.pid"
    if process_alive(pid_file): raise ValueError(f"API ({api_type}) is already running (PID {pid_value(pid_file)}).")
    address = cfg.get("Address", "localhost")
    port = int(cfg.get("Port", "8080"))
    with socket.socket() as s:
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try: s.bind((address, port))
        except OSError as exc: raise ValueError(f"Address '{address}' and port {port} are unavailable: {exc}")
    log = (api_dir / "server.log").open("ab")
    token = uuid.uuid4().hex
    proc = subprocess.Popen(["bash", str(SHELL_SCRIPT), "--db-manager-internal", "--serve", db, api_type],
                            stdin=subprocess.DEVNULL, stdout=log, stderr=log,
                            start_new_session=True, cwd=pathlib.Path.cwd(), env=process_env(token), close_fds=True)
    time.sleep(0.35)
    if proc.poll() is not None:
        log.close()
        raise RuntimeError(f"API failed to start. Check {api_dir / 'server.log'}.")
    write_managed_pid(pid_file, proc, token, f"api:{db}:{api_type}")
    log.close()
    cprint(f"API ({api_type}) server started successfully on port {port} (PID: {proc.pid})!")
    cprint(f"URL: {cfg.get('Protocol', 'http')}://{address}:{port}{api_prefix(cfg)}/?key=<key1>/<key2>", CYAN)


def api_status(db: str, api_type: str) -> None:
    path = api_cfg_path(db, api_type)
    cfg = read_kv(path)
    pid = path.parent / "api.pid"
    if not cfg: raise ValueError(f"API ({api_type}) is not configured.")
    running = process_alive(pid)
    print(f"{CYAN}{BOLD}=================================================={RESET}")
    print(f"{CYAN}{BOLD}       API SERVER STATUS ({api_type.upper()})       {RESET}")
    print(f"{CYAN}{BOLD}=================================================={RESET}")
    for label, value in (("Name", cfg.get("Name", "")), ("Type", api_type.upper()),
                         ("Status", "Running" if running else "Stopped"),
                         ("PID", str(pid_value(pid)) if running else "-"),
                         ("Protocol", cfg.get("Protocol", "http")), ("Address", cfg.get("Address", "localhost")),
                         ("Port", cfg.get("Port", "8080")), ("Base Path", api_prefix(cfg)),
                         ("Debug", cfg.get("ApiDebug", "true"))):
        print(f"  {BOLD}{label + ':':<15}{RESET} {GREEN if label == 'Status' and running else YELLOW}{value}{RESET}")
    print(f"{CYAN}=================================================={RESET}")


def api_request(db: str, args: list[str]) -> None:
    if len(args) < 2: raise ValueError("Usage: api_request <public|secret> <endpoint>")
    api_type = args[0]
    cfg = read_kv(api_cfg_path(db, api_type))
    if not cfg: raise ValueError(f"API ({api_type}) is not configured.")
    pid_file = api_cfg_path(db, api_type).parent / "api.pid"
    if not process_alive(pid_file): raise ValueError(f"API ({api_type}) is not running.")
    key1, key2 = api_pair(db, api_type)
    endpoint = " ".join(args[1:]).strip().lstrip("/")
    endpoint = endpoint.replace(" ", "/")
    base = f"{cfg.get('Protocol', 'http')}://{cfg.get('Address', 'localhost')}:{cfg.get('Port', '8080')}{api_prefix(cfg)}"
    key_value = urllib.parse.quote(key1, safe="") + "/" + urllib.parse.quote(key2, safe="")
    url = f"{base}/{endpoint}/?key={key_value}" if endpoint else f"{base}/?key={key_value}"
    result = subprocess.run(["curl", "-sS", "-k", "--max-time", "10", url], text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or "API request failed.")
    print(result.stdout)


def api_key_command(db: str, args: list[str]) -> None:
    if not args or args[0] == "list":
        show_keys(db); return
    action = args[0].lower()
    if action == "add":
        if len(args) != 2: raise ValueError("Usage: api_key add <key>")
        value = args[1]
        if not value or any(ch in value for ch in "\n=/") or "\r" in value: raise ValueError("Invalid key value. Keys cannot contain '/', '=' or line breaks.")
        records = key_records(db)
        if any(value == v for _, v in records): raise ValueError("This secret key already exists.")
        idx = 1
        names = {k for k, _ in records}
        while f"secret_key_{idx}" in names: idx += 1
        records.append((f"secret_key_{idx}", value)); write_key_records(db, records)
        cprint(f"Secret key added successfully as secret_key_{idx}.")
    elif action == "remove":
        if len(args) != 2: raise ValueError("Usage: api_key remove <key|secret_key_N>")
        target = args[1]
        records = key_records(db)
        match = next(((k, v) for k, v in records if k == target or v == target), None)
        if match:
            for api_type in ("public", "secret"):
                api_cfg = read_kv(api_cfg_path(db, api_type))
                if match[1] in (api_cfg.get("SecretKey1"), api_cfg.get("SecretKey2")):
                    raise ValueError(f"Key '{target}' is currently used by API '{api_type}'. Edit/delete that API configuration first.")
        new = [(k, v) for k, v in records if k != target and v != target]
        if len(new) == len(records): raise ValueError(f"Secret key '{target}' was not found.")
        write_key_records(db, new); cprint(f"Secret key '{target}' removed successfully.")
    else:
        raise ValueError("Usage: api_key <add|remove|list> <key>")


def backup_candidates(db: str) -> list[pathlib.Path]:
    bdir = backup_directory(db, read_backup_config(db))
    files = [p for p in bdir.iterdir() if p.is_file() and p.suffix in (".tar", ".gz", ".enc") and not p.name.endswith((".sha256", ".sig"))]
    # .tar.gz has suffix .gz; .enc is encrypted.
    return sorted(files, key=lambda p: p.stat().st_mtime)


def archive_base(path: pathlib.Path) -> str:
    n = path.name
    for suffix in (".tar.gz.enc", ".tar.enc", ".tar.gz", ".tar"):
        if n.endswith(suffix): return n[:-len(suffix)]
    return path.stem


def key_file(db: str, name: str) -> pathlib.Path:
    return ensure_db_layout(db)["secrets"] / name


def ensure_secret_file(path: pathlib.Path) -> bytes:
    if not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(os.urandom(32)); os.chmod(path, 0o600)
    return path.read_bytes()


def apply_storage_permissions(db: str, cfg: dict[str, dict[str, str]]) -> None:
    raw = cfg_value(cfg, "storage_permissions", "700")
    if not re.fullmatch(r"0?[0-7]{3}", raw): raise ValueError("storage_permissions must be an octal mode such as 700 or 600.")
    mode = int(raw, 8)
    bdir = backup_directory(db, cfg)
    # The directory must retain owner write/execute rights so the manager can
    # create, enumerate and remove archives even when a restrictive file mode is chosen.
    directory_mode = mode | 0o300
    with contextlib.suppress(OSError): os.chmod(bdir, directory_mode)
    for f in bdir.iterdir():
        if f.is_file():
            with contextlib.suppress(OSError): os.chmod(f, mode & 0o666)


def run_cleanup(db: str, cfg: dict[str, dict[str, str]], write_log=None) -> int:
    files = backup_candidates(db)
    max_backups = int(cfg_value(cfg, "max_backups", "10"))
    if max_backups < 1: max_backups = 1
    keep_daily = cfg_value(cfg, "keep_daily", "false").lower() == "true"
    keep_weekly = cfg_value(cfg, "keep_weekly", "false").lower() == "true"
    protected: set[pathlib.Path] = set()
    if keep_daily:
        by_day: dict[str, pathlib.Path] = {}
        for p in files:
            day = dt.datetime.fromtimestamp(p.stat().st_mtime).date().isoformat()
            if day not in by_day or p.stat().st_mtime > by_day[day].stat().st_mtime: by_day[day] = p
        protected.update(by_day.values())
    if keep_weekly:
        by_week: dict[tuple[int, int], pathlib.Path] = {}
        for p in files:
            iso = dt.datetime.fromtimestamp(p.stat().st_mtime).isocalendar()
            key = (iso.year, iso.week)
            if key not in by_week or p.stat().st_mtime > by_week[key].stat().st_mtime: by_week[key] = p
        protected.update(by_week.values())
    keep = set(protected)
    for p in reversed(files):
        if len(keep) >= max(max_backups, len(protected)): break
        keep.add(p)
    removed = 0
    for p in files:
        if p not in keep:
            for side in (p.with_name(p.name + ".sha256"), p.with_name(p.name + ".sig")):
                with contextlib.suppress(FileNotFoundError): side.unlink()
            with contextlib.suppress(OSError): p.unlink(); removed += 1
    if write_log: write_log(f"[BCKUP_DEL] Retention cleanup completed; removed {removed} backup(s).")
    return removed


def create_backup(db: str, name: str | None = None, force: bool = False, automated: bool = False,
                  logger=None) -> pathlib.Path:
    d = ensure_db_layout(db)
    cfg = read_backup_config(db)
    prefix = cfg_value(cfg, "default_backup_name", "auto") or "auto"
    if not name:
        name = f"{prefix}-{dt.datetime.now().strftime('%Y-%m-%d_%H-%M-%S')}"
    valid_backup_name(name)
    compressed = cfg_value(cfg, "auto_compression", "true").lower() == "true"
    encrypt = cfg_value(cfg, "encrypt_backups", "false").lower() == "true"
    verify = cfg_value(cfg, "verify_integrity", "false").lower() == "true"
    sign = cfg_value(cfg, "sign_manifest", "false").lower() == "true"
    suffix = ".tar.gz" if compressed else ".tar"
    if encrypt: suffix += ".enc"
    backup_dir = backup_directory(db, cfg)
    target = backup_dir / (name + suffix)
    if target.exists() and not force: raise FileExistsError(f"Backup '{name}' already exists. Use --force to overwrite it.")
    backup_dir.mkdir(parents=True, exist_ok=True)
    tmp_tar = None
    try:
        fd, tmp_name = tempfile.mkstemp(prefix=".backup-", suffix=".tar.gz" if compressed else ".tar", dir=backup_dir)
        os.close(fd); tmp_tar = pathlib.Path(tmp_name)
        mode = "w:gz" if compressed else "w"
        with tarfile.open(tmp_tar, mode) as tar:
            def archive_filter(info):
                rel = info.name
                if rel == f"{db}/backups" or rel.startswith(f"{db}/backups/"):
                    return None
                if rel.endswith("/secrets/backup_encryption.key") or rel.endswith("/secrets/backup_manifest.key"):
                    return None
                if rel.endswith(".pid") or rel.endswith(".log"):
                    return None
                return info
            tar.add(d["base"], arcname=db, filter=archive_filter)
        if encrypt:
            password_file = key_file(db, "backup_encryption.key")
            ensure_secret_file(password_file)
            enc_tmp = tmp_tar.with_suffix(tmp_tar.suffix + ".enc")
            run = subprocess.run(["openssl", "enc", "-aes-256-cbc", "-salt", "-pbkdf2", "-in", str(tmp_tar),
                                  "-out", str(enc_tmp), "-pass", f"file:{password_file}"], capture_output=True, text=True)
            if run.returncode: raise RuntimeError("Backup encryption failed: " + run.stderr.strip())
            tmp_tar.unlink(); tmp_tar = enc_tmp
        if target.exists(): target.unlink()
        tmp_tar.replace(target); tmp_tar = None
        os.chmod(target, int(cfg_value(cfg, "storage_permissions", "700"), 8))
        digest = hashlib.sha256(target.read_bytes()).hexdigest()
        if verify:
            target.with_name(target.name + ".sha256").write_text(f"{digest}  {target.name}\n", encoding="utf-8")
        if sign:
            secret = ensure_secret_file(key_file(db, "backup_manifest.key"))
            signature = hmac.new(secret, digest.encode(), hashlib.sha256).hexdigest()
            target.with_name(target.name + ".sig").write_text(signature + "\n", encoding="ascii")
        if cfg_value(cfg, "auto_cleanup", "false").lower() == "true":
            run_cleanup(db, cfg, logger)
        apply_storage_permissions(db, cfg)
        message = f"[BACKUP] Backup '{name}' created successfully ({target.name})."
        if logger: logger(message)
        else: cprint(message)
        if cfg_value(cfg, "notify_on_completion", "false").lower() == "true":
            subprocess.run(["notify-send", "Custom DB Manager", f"Backup {name} completed"],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return target
    finally:
        if tmp_tar:
            with contextlib.suppress(FileNotFoundError): tmp_tar.unlink()


def find_backup(db: str, name: str) -> pathlib.Path:
    valid_backup_name(name)
    matches = [p for p in backup_candidates(db) if archive_base(p) == name]
    if not matches: raise FileNotFoundError(f"Backup '{name}' does not exist in database '{db}'.")
    return matches[-1]


def verify_backup_file(db: str, path: pathlib.Path) -> None:
    cfg = read_backup_config(db)
    checksum = path.with_name(path.name + ".sha256")
    signature = path.with_name(path.name + ".sig")
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    if cfg_value(cfg, "verify_integrity", "false").lower() == "true" or checksum.exists():
        if not checksum.exists(): raise RuntimeError("Integrity verification is enabled, but the SHA-256 manifest is missing.")
        expected = checksum.read_text(encoding="utf-8").split()[0]
        if not hmac.compare_digest(digest, expected): raise RuntimeError("Backup integrity check failed (SHA-256 mismatch).")
    if cfg_value(cfg, "sign_manifest", "false").lower() == "true" or signature.exists():
        if not signature.exists(): raise RuntimeError("Backup signature is missing.")
        secret = ensure_secret_file(key_file(db, "backup_manifest.key"))
        expected_sig = hmac.new(secret, digest.encode(), hashlib.sha256).hexdigest()
        if not hmac.compare_digest(signature.read_text().strip(), expected_sig): raise RuntimeError("Backup signature validation failed.")


def decrypt_backup(db: str, path: pathlib.Path, out_path: pathlib.Path) -> pathlib.Path:
    if not path.name.endswith(".enc"):
        shutil.copy2(path, out_path); return out_path
    password_file = key_file(db, "backup_encryption.key")
    if not password_file.exists(): raise RuntimeError("The database backup encryption key is missing; this archive cannot be decrypted.")
    result = subprocess.run(["openssl", "enc", "-d", "-aes-256-cbc", "-pbkdf2", "-in", str(path),
                             "-out", str(out_path), "-pass", f"file:{password_file}"], capture_output=True, text=True)
    if result.returncode: raise RuntimeError("Backup decryption failed: " + result.stderr.strip())
    return out_path


def safe_extract_db(archive: pathlib.Path, temp_dir: pathlib.Path, db: str) -> pathlib.Path:
    with tarfile.open(archive, "r:*") as tar:
        members = tar.getmembers()
        for m in members:
            p = pathlib.PurePosixPath(m.name)
            if p.is_absolute() or ".." in p.parts or not p.parts or p.parts[0] != db:
                raise RuntimeError("Backup archive contains an unsafe or unexpected path.")
        tar.extractall(temp_dir, members=members, filter="data")
    restored = temp_dir / db
    if not restored.is_dir() or not (restored / f"{db}.db").exists():
        raise RuntimeError("Backup archive does not contain a valid database structure.")
    return restored


def running_api_types(db: str) -> list[str]:
    result = []
    for kind in ("public", "secret"):
        if process_alive(db_dir(db) / "api" / kind / "api.pid"): result.append(kind)
    return result


def restore_backup(db: str, name: str, force: bool = False) -> None:
    d = ensure_db_layout(db)
    active_backup_cfg = read_backup_config(db)
    active_backup_store = backup_directory(db, active_backup_cfg)
    active_storage_path = cfg_value(active_backup_cfg, "backup_storage_path", "")
    archive = find_backup(db, name)
    if not force:
        answer = input(f"Warning: Restore backup '{name}' and replace current database '{db}'? (yes/no): ").strip().lower()
        if answer != "yes":
            cprint("Action cancelled.", YELLOW); return
    verify_backup_file(db, archive)
    active_apis = running_api_types(db)
    schedule_was_active = {}
    schedule_values = {}
    for line in d["schedule_cfg"].read_text(encoding="utf-8", errors="replace").splitlines():
        if "=" in line:
            fn, val = line.split("=", 1)
            status, _, interval = val.partition(":")
            schedule_values[fn.strip()] = (status.strip(), interval.strip())
            schedule_was_active[fn.strip()] = process_alive(d["secrets"] / f"backup_{fn.strip()}.pid")
    persistent_keys = {}
    for secret_name in ("backup_encryption.key", "backup_manifest.key"):
        secret_path = d["secrets"] / secret_name
        if secret_path.exists(): persistent_keys[secret_name] = secret_path.read_bytes()
    for kind in ("public", "secret"):
        stop_pid_file(d["api"] / kind / "api.pid")
    for kind in ("backup", "backup_delete"):
        stop_backup_worker(db, kind)
    preserve_local_backups = active_backup_store.resolve() == d["backups"].resolve()
    with tempfile.TemporaryDirectory(prefix="customdb-restore-") as td:
        temp = pathlib.Path(td)
        decoded = temp / "restore.tar"
        decrypt_backup(db, archive, decoded)
        unpack = temp / "unpack"; unpack.mkdir()
        restored = safe_extract_db(decoded, unpack, db)
        preserved_backups = temp / "backups-preserved"
        if preserve_local_backups and d["backups"].exists():
            shutil.move(str(d["backups"]), str(preserved_backups))
        old = temp / "previous-database"
        if d["base"].exists(): shutil.move(str(d["base"]), str(old))
        try:
            shutil.move(str(restored), str(d["base"]))
            if preserved_backups.exists(): shutil.move(str(preserved_backups), str(d["backups"]))
            ensure_db_layout(db)
            # Keep the currently selected secondary-disk destination across restore.
            restored_cfg = read_backup_config(db)
            for section_values in restored_cfg.values():
                if "backup_storage_path" in section_values:
                    section_values["backup_storage_path"] = active_storage_path
            if not any("backup_storage_path" in values for values in restored_cfg.values()):
                restored_cfg.setdefault("General", {})["backup_storage_path"] = active_storage_path
            write_backup_config(d["backup_cfg"], restored_cfg)
            for secret_name, secret_data in persistent_keys.items():
                secret_path = d["secrets"] / secret_name
                secret_path.write_bytes(secret_data); os.chmod(secret_path, 0o600)
        except Exception:
            with contextlib.suppress(Exception):
                if d["base"].exists(): shutil.rmtree(d["base"])
                if old.exists(): shutil.move(str(old), str(d["base"]))
                if preserved_backups.exists(): shutil.move(str(preserved_backups), str(d["backups"]))
            raise
    for kind in active_apis:
        try: api_start(db, kind)
        except Exception as exc: cprint(f"Warning: API ({kind}) was not restarted: {exc}", YELLOW)
    restored_schedule = {}
    for line in d["schedule_cfg"].read_text(encoding="utf-8", errors="replace").splitlines():
        if "=" in line:
            fn, val = line.split("=", 1); status, _, interval = val.partition(":")
            restored_schedule[fn.strip()] = (status.strip(), interval.strip())
    for func, was_active in schedule_was_active.items():
        status, interval = restored_schedule.get(func, ("false", ""))
        if was_active and status == "true" and interval:
            with contextlib.suppress(Exception): start_worker(db, func, interval)
    # Match the CLI's internal clear behavior: redraw its startup banner instead
    # of invoking the operating-system clear utility and leaving a blank screen.
    show_cli_banner()
    cprint(f"All active API processes were stopped, database files were replaced, and backup '{name}' was restored successfully.")


def delete_backup(db: str, name: str) -> None:
    path = find_backup(db, name)
    path.unlink()
    for suffix in (".sha256", ".sig"):
        with contextlib.suppress(FileNotFoundError): path.with_name(path.name + suffix).unlink()
    cprint(f"Backup '{name}' deleted successfully.")


def show_backups(db: str) -> None:
    files = backup_candidates(db)
    print(f"{CYAN}{BOLD}Available Backups for '{db}':{RESET}")
    if not files:
        print("  (No backups found)"); return
    headers = ("BACKUP NAME", "SIZE", "DATE")
    rows = []
    for p in files:
        size = p.stat().st_size
        human = f"{size / (1024*1024):.2f} MB" if size >= 1024*1024 else f"{size / 1024:.1f} KB"
        stamp = dt.datetime.fromtimestamp(p.stat().st_mtime).strftime("%Y-%m-%d %H:%M:%S")
        rows.append((archive_base(p), human, stamp))
    widths = [max(len(headers[i]), *(len(r[i]) for r in rows)) for i in range(3)]
    print("┌" + "┬".join("─" * (w + 2) for w in widths) + "┐")
    print("│ " + " │ ".join(f"{headers[i]:<{widths[i]}}" for i in range(3)) + " │")
    print("├" + "┼".join("─" * (w + 2) for w in widths) + "┤")
    for row in rows:
        print("│ " + " │ ".join(f"{row[i]:<{widths[i]}}" for i in range(3)) + " │")
    print("└" + "┴".join("─" * (w + 2) for w in widths) + "┘")


def backup_configs(db: str, args: list[str]) -> None:
    d = ensure_db_layout(db)
    cfg = read_backup_config(db)
    if not args:
        print(f"{CYAN}{BOLD}Categorized Backup System Configurations ({db}):{RESET}")
        for section, values in cfg.items():
            print(f"\n  {YELLOW}[{section}]{RESET}")
            for k, v in values.items(): print(f"    - {CYAN}{k}{RESET}: {GREEN}{v}{RESET}")
        print("\nUse: backup_configs <key> [value]")
        return
    known_keys = {k for group in cfg.values() for k in group}
    if len(args) == 1:
        if args[0] not in known_keys: raise ValueError(f"Backup configuration key '{args[0]}' does not exist.")
        cprint(f"{args[0]}={cfg_value(cfg, args[0])}", CYAN)
        if args[0] == "backup_storage_path":
            cprint("An empty value uses db_manage/database/<database>/backups; an external path stores files in <path>/<database>.", YELLOW)
        return
    if len(args) != 2: raise ValueError("Usage: backup_configs <cfg> [val]")
    key, value = args
    known = {k for group in cfg.values() for k in group}
    if key not in known: raise ValueError(f"Backup configuration key '{key}' does not exist.")
    old_backup_dir = None
    if key == "backup_storage_path":
        try:
            old_backup_dir = backup_directory(db, cfg)
        except Exception:
            old_backup_dir = None
        value = validate_backup_storage_path(value)
    boolean_keys = {"auto_compression", "verify_integrity", "auto_cleanup", "keep_daily", "keep_weekly",
                    "background_daemon", "notify_on_completion", "encrypt_backups", "sign_manifest"}
    if key in boolean_keys: value = parse_bool(value)
    elif key == "max_backups":
        if not value.isdigit() or int(value) < 1: raise ValueError("max_backups must be an integer >= 1.")
    elif key == "default_backup_name": valid_backup_name(value)
    elif key == "default_interval": parse_interval(value)
    elif key == "storage_permissions":
        if not re.fullmatch(r"0?[0-7]{3}", value): raise ValueError("storage_permissions must be an octal mode such as 700 or 600.")
    for group in cfg.values():
        if key in group: group[key] = value
    new_backup_dir = backup_directory(db, cfg)
    moved_count = 0
    if key == "backup_storage_path" and old_backup_dir is not None:
        moved_count = migrate_backup_files(old_backup_dir, new_backup_dir)
    write_backup_config(d["backup_cfg"], cfg)
    apply_storage_permissions(db, cfg)
    cprint(f"Backup configuration '{key}' updated successfully to '{value}'.")
    if key == "backup_storage_path":
        cprint(f"Backup destination: {new_backup_dir}", CYAN)
        if moved_count: cprint(f"Copied {moved_count} existing backup file(s) to the new destination.")
    if key == "encrypt_backups":
        if value == "true": ensure_secret_file(key_file(db, "backup_encryption.key")); cprint("A private encryption key was created for this database.", YELLOW)
    if key == "sign_manifest" and value == "true": ensure_secret_file(key_file(db, "backup_manifest.key"))


def open_log_terminal(db: str, func: str, log_path: pathlib.Path) -> None:
    title = f"Custom DB Manager - {db} - {func}"
    quoted_log = shlex.quote(str(log_path))
    quoted_db = shlex.quote(db)
    shell_cmd = (
        "printf '\\033[0;36m==================================================\\033[0m\\n'; "
        "printf '\\033[1m        CUSTOM DB MANAGER CLI - Version 1.0     \\033[0m\\n'; "
        "printf '\\033[0;36m==================================================\\033[0m\\n'; "
        "printf \" Type 'help' for commands or 'exit' to quit.\\n\\n\"; "
        "printf ' Backup monitor for database: %s\\n' " + quoted_db + "; "
        "printf ' Closing this window also closes only the log viewer.\\n\\n'; "
        "tail -n 20 -F " + quoted_log
    )
    viewer_pid = dirs(db)["secrets"] / f"backup_{func}_viewer.pid"
    stop_pid_file(viewer_pid)
    token = uuid.uuid4().hex
    env = process_env(token)
    candidates = []
    if shutil.which("gnome-terminal"):
        candidates.append(["gnome-terminal", "--wait", "--title", title, "--", "bash", "-lc", shell_cmd])
    if shutil.which("konsole"):
        candidates.append(["konsole", "--nofork", "--new-tab", "-p", f"tabtitle={title}", "-e", "bash", "-lc", shell_cmd])
    if shutil.which("xterm"):
        candidates.append(["xterm", "-T", title, "-e", "bash", "-lc", shell_cmd])
    if shutil.which("x-terminal-emulator"):
        candidates.append(["x-terminal-emulator", "-e", "bash", "-lc", shell_cmd])
    for cmd in candidates:
        try:
            proc = subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                    stderr=subprocess.DEVNULL, start_new_session=True,
                                    close_fds=True, env=env)
            time.sleep(0.2)
            if proc.poll() is None:
                write_managed_pid(viewer_pid, proc, token, f"backup-viewer:{db}:{func}")
                return
        except Exception:
            continue
    cprint(f"No graphical terminal was found. Backup logs are being saved to: {log_path}", YELLOW)


def start_worker(db: str, func: str, interval: str) -> None:
    d = ensure_db_layout(db)
    secs = parse_interval(interval)
    pid_file = d["secrets"] / f"backup_{func}.pid"
    if process_alive(pid_file):
        cprint(f"Backup function '{func}' is already active (PID {pid_value(pid_file)}).", YELLOW)
        return
    log_path = d["secrets"] / f"backup_{func}.log"
    log_path.parent.mkdir(parents=True, exist_ok=True)
    log_handle = log_path.open("ab", buffering=0)
    token = uuid.uuid4().hex
    cmd = ["bash", str(SHELL_SCRIPT), "--db-manager-internal", "--worker", db, func, str(secs)]
    # Always use a dedicated session/process group. This makes termination
    # deterministic even when background_daemon is false in older configs.
    proc = subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=log_handle, stderr=log_handle,
                            start_new_session=True, cwd=pathlib.Path.cwd(), close_fds=True,
                            env=process_env(token))
    log_handle.close()
    time.sleep(0.25)
    if proc.poll() is not None:
        raise RuntimeError(f"Backup worker failed to start. Check {log_path}.")
    write_managed_pid(pid_file, proc, token, f"backup-worker:{db}:{func}")
    cprint(f"Backup function '{func}' scheduled successfully with interval {interval} (PID: {proc.pid}).")
    open_log_terminal(db, func, log_path)


def backup_schedule(db: str, args: list[str]) -> None:
    d = ensure_db_layout(db)
    if not args:
        print(f"{CYAN}{BOLD}Backup Schedule Functions ({db}):{RESET}")
        for line in d["schedule_cfg"].read_text(encoding="utf-8").splitlines():
            if not line.strip() or "=" not in line: continue
            name, val = line.split("=", 1)
            status, _, interval = val.partition(":")
            pid = d["secrets"] / f"backup_{name}.pid"
            proc = str(pid_value(pid)) if process_alive(pid) else "Stopped"
            viewer = d["secrets"] / f"backup_{name}_viewer.pid"
            viewer_status = "Open" if process_alive(viewer) else "Closed"
            print(f"  - {CYAN}{name}{RESET} -> Status: {YELLOW}{status}{RESET}, Interval: {interval}, Process: {proc}, Log CLI: {viewer_status}")
        return
    if len(args) not in (2, 3): raise ValueError("Usage: backup_schedule <backup|backup_delete> <true|false> [interval]")
    func, status = args[0], parse_bool(args[1])
    if func not in ("backup", "backup_delete"): raise ValueError("Function must be 'backup' or 'backup_delete'.")
    cfg = read_backup_config(db)
    default = cfg_value(cfg, "default_interval", "1h") if func == "backup" else "1d"
    interval = args[2] if len(args) == 3 else default
    parse_interval(interval)
    entries: dict[str, str] = {}
    for line in d["schedule_cfg"].read_text(encoding="utf-8", errors="replace").splitlines():
        if "=" in line:
            k, v = line.split("=", 1); entries[k.strip()] = v.strip()
    entries[func] = f"{status}:{interval}"
    atomic_write_text(d["schedule_cfg"], "".join(f"{k}={v}\n" for k, v in entries.items()), 0o600)
    pid_file = d["secrets"] / f"backup_{func}.pid"
    if status == "true":
        stop_backup_worker(db, func)
        start_worker(db, func, interval)
    else:
        # Disable means stop both the hidden worker and its visible log CLI.
        stop_backup_worker(db, func)
        cprint(f"Backup function '{func}' disabled successfully; its worker and log CLI were closed.")


def worker_log(message: str) -> None:
    print(f"{GREEN}{message}{RESET}", flush=True)


def worker_enabled(db: str, func: str) -> bool:
    path = dirs(db)["secrets"] / "backup_schedule.cfg"
    try:
        for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
            if "=" not in line: continue
            name, value = line.split("=", 1)
            if name.strip() == func:
                status, _, _interval = value.partition(":")
                return status.strip().lower() == "true"
    except OSError:
        return False
    return False


def worker_main(db: str, func: str, interval: int) -> None:
    ensure_db_layout(db)
    worker_pid_file = dirs(db)["secrets"] / f"backup_{func}.pid"
    viewer_pid_file = dirs(db)["secrets"] / f"backup_{func}_viewer.pid"
    stop_event = threading.Event()
    previous_handlers = {}

    def request_stop(_signum, _frame):
        stop_event.set()

    for sig in (signal.SIGTERM, signal.SIGINT):
        with contextlib.suppress(Exception):
            previous_handlers[sig] = signal.signal(sig, request_stop)

    prefix = "BACKUP" if func == "backup" else "BCKUP_DEL"
    worker_log(f"[{prefix}] Worker started for database '{db}' (interval: {interval}s).")
    try:
        next_run = time.monotonic() + interval
        while not stop_event.is_set():
            if not worker_enabled(db, func):
                worker_log(f"[{prefix}] Schedule changed to false; stopping worker and closing its log CLI.")
                stop_pid_file(viewer_pid_file)
                break
            remaining = next_run - time.monotonic()
            if remaining > 0:
                stop_event.wait(min(1.0, remaining))
                continue
            try:
                if func == "backup":
                    stamp = dt.datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
                    prefix_name = cfg_value(read_backup_config(db), "default_backup_name", "auto") or "auto"
                    create_backup(db, f"{prefix_name}-{stamp}", force=False, automated=True, logger=worker_log)
                else:
                    run_cleanup(db, read_backup_config(db), worker_log)
            except Exception as exc:
                worker_log(f"[{prefix}] ERROR: {exc}")
            next_run = time.monotonic() + interval
    finally:
        stop_pid_file(viewer_pid_file)
        remove_managed_pid(worker_pid_file, os.environ.get("DBM_PROCESS_TOKEN"))
        for sig, handler in previous_handlers.items():
            with contextlib.suppress(Exception): signal.signal(sig, handler)


def db_create(args: list[str]) -> None:
    if not args: raise ValueError("Usage: create_database <name>")
    for name in args:
        valid_name(name, "database name")
        target = db_dir(name)
        if target.exists():
            cprint(f"Error: Database '{name}' already exists.", RED); continue
        ensure_db_layout(name)
        cprint(f"Database '{name}' created successfully.")


def db_drop(args: list[str]) -> None:
    if not args: raise ValueError("Usage: drop_database <name>")
    for name in args:
        target = db_dir(name)
        if not target.exists(): cprint(f"Error: Database '{name}' does not exist.", RED); continue
        for kind in ("public", "secret"):
            stop_pid_file(target / "api" / kind / "api.pid")
        for func in ("backup", "backup_delete"):
            stop_backup_worker(name, func)
        shutil.rmtree(target)
        cprint(f"Database '{name}' dropped successfully.")


def db_rename(args: list[str]) -> None:
    if len(args) != 2: raise ValueError("Usage: rename_database <name> <newname>")
    old, new = args
    src, dst = db_dir(old), db_dir(new)
    if not src.exists(): raise FileNotFoundError(f"Database '{old}' does not exist.")
    if dst.exists(): raise FileExistsError(f"Database '{new}' already exists.")
    active_apis = running_api_types(old)
    active_workers = {}
    schedule_values = {}
    schedule_file = src / "secrets" / "backup_schedule.cfg"
    if schedule_file.exists():
        for line in schedule_file.read_text(encoding="utf-8", errors="replace").splitlines():
            if "=" in line:
                fn, value = line.split("=", 1)
                status, _, interval = value.partition(":")
                schedule_values[fn.strip()] = (status.strip(), interval.strip())
                active_workers[fn.strip()] = process_alive(src / "secrets" / f"backup_{fn.strip()}.pid")
    for kind in ("public", "secret"): stop_pid_file(src / "api" / kind / "api.pid")
    for func in ("backup", "backup_delete"): stop_backup_worker(old, func)
    src.rename(dst)
    meta = dst / f"{old}.db"
    if meta.exists():
        data = json.loads(meta.read_text(encoding="utf-8")); data["database"] = new
        atomic_write_text(dst / f"{new}.db", json.dumps(data, indent=2) + "\n", 0o600)
        meta.unlink()
    cprint(f"Database '{old}' renamed to '{new}' successfully.")
    for kind in active_apis:
        try: api_start(new, kind)
        except Exception as exc: cprint(f"Warning: API ({kind}) was not restarted: {exc}", YELLOW)
    for func, was_active in active_workers.items():
        status, interval = schedule_values.get(func, ("false", ""))
        if was_active and status == "true" and interval:
            with contextlib.suppress(Exception): start_worker(new, func, interval)


def system_process(db: str | None) -> None:
    found = False
    if DB_ROOT.exists():
        for base in sorted(p for p in DB_ROOT.iterdir() if p.is_dir()):
            name = base.name
            for kind in ("public", "secret"):
                pf = base / "api" / kind / "api.pid"
                if pf.exists():
                    if process_alive(pf):
                        found = True; print(f"  - API Server ({kind}): Database: {name} -> Running, PID: {pid_value(pf)}")
                    else: remove_managed_pid(pf)
            for func in ("backup", "backup_delete"):
                pf = base / "secrets" / f"backup_{func}.pid"
                if pf.exists():
                    if process_alive(pf):
                        found = True; print(f"  - Backup Process: Function: {func}, Database: {name} -> Running, PID: {pid_value(pf)}")
                    else: remove_managed_pid(pf)
                viewer = base / "secrets" / f"backup_{func}_viewer.pid"
                if viewer.exists():
                    if process_alive(viewer):
                        found = True; print(f"  - Backup Log CLI: Function: {func}, Database: {name} -> Open, PID: {pid_value(viewer)}")
                    else: remove_managed_pid(viewer)
    if not found: print("  (No active managed processes found)")


def system_terminate(force: bool) -> None:
    if not force:
        answer = input("Warning: terminate all managed processes and remove 'db_manage'. Proceed? (yes/no): ").strip().lower()
        if answer != "yes": cprint("Action cancelled.", YELLOW); return
    if DB_ROOT.exists():
        for base in [p for p in DB_ROOT.iterdir() if p.is_dir()]:
            for kind in ("public", "secret"): stop_pid_file(base / "api" / kind / "api.pid")
            for func in ("backup", "backup_delete"): stop_backup_worker(base.name, func)
    shutil.rmtree(ROOT, ignore_errors=True)
    (ROOT / "database").mkdir(parents=True, exist_ok=True)
    (ROOT / "runtime").mkdir(parents=True, exist_ok=True)
    cprint("System terminated successfully. Managed processes were stopped and db_manage was restored.")
    show_cli_banner()


def table_show(db: str, args: list[str]) -> None:
    d = ensure_db_layout(db)
    if args:
        table = valid_name(args[0], "table name")
        cols, records, _ = read_table(db, table)
        rows = [cols] + records
        n = len(cols)
        widths = [max(4, *(len(str(r[i])) for r in rows)) for i in range(n)]
        def rowfmt(row: list[str]) -> str:
            return "│ " + " │ ".join(str(row[i]).ljust(widths[i]) for i in range(n)) + " │"
        print(f"{CYAN}{BOLD}Complete Table View: '{table}'{RESET}")
        print("┌" + "┬".join("─" * (w + 2) for w in widths) + "┐")
        print(rowfmt(cols))
        print("├" + "┼".join("─" * (w + 2) for w in widths) + "┤")
        if records:
            for idx, row in enumerate(records):
                print(rowfmt(row))
                if idx < len(records) - 1:
                    print("├" + "┼".join("─" * (w + 2) for w in widths) + "┤")
        else:
            print(rowfmt([""] * n))
        print("└" + "┴".join("─" * (w + 2) for w in widths) + "┘")
        return
    tables = sorted(p.name for p in d["tables"].iterdir() if p.is_dir())
    if not tables:
        cprint(f"Error: No tables exist in database '{db}'.", RED); return
    width = max(15, len("TABLES"), *(len(x) for x in tables))
    print(f"{CYAN}{BOLD}Tables in database '{db}':{RESET}")
    print("┌" + "─" * (width + 2) + "┐")
    print("│ " + f"{'TABLES':<{width}}" + " │")
    print("├" + "─" * (width + 2) + "┤")
    for name in tables: print("│ " + f"{name:<{width}}" + " │")
    print("└" + "─" * (width + 2) + "┘")

def parse_insert_mapping(cols: list[str], args: list[str]) -> dict[int, str]:
    if not args:
        raise ValueError("No values were provided for insert_into.")
    rest = args[:]
    mapping: dict[int, str] = {}
    if len(rest) == 1 and "|" in rest[0]:
        values = rest[0].split("|")
        start = 1 if cols and cols[0] == "id" else 0
        for i, value in enumerate(values):
            if start + i < len(cols): mapping[start + i] = clean_cell_value(value)
    elif rest[0] in cols:
        if len(rest) % 2:
            raise ValueError('Column/value pairs are incomplete. Quote values containing spaces, e.g. insert_into people name "John Doe".')
        i = 0
        while i < len(rest):
            col, value = rest[i], rest[i + 1]
            if col not in cols: raise ValueError(f"Column '{col}' does not exist.")
            if col == "id": raise ValueError("The primary id column is generated automatically.")
            mapping[cols.index(col)] = clean_cell_value(value)
            i += 2
    else:
        start = 1 if cols and cols[0] == "id" else 0
        for i, value in enumerate(rest):
            if start + i < len(cols): mapping[start + i] = clean_cell_value(value)
    if not mapping:
        raise ValueError("No valid column values were provided.")
    return mapping


def table_insert(db: str, args: list[str]) -> None:
    if len(args) < 2:
        raise ValueError('Usage: insert_into <table> <column> "<value with spaces>" [<column> "<value>"]')
    table = valid_name(args[0], "table name")
    d = ensure_db_layout(db)
    folder = d["tables"] / table
    if not folder.is_dir(): raise FileNotFoundError(f"Table '{table}' does not exist.")
    with table_lock(folder):
        cols, _, _ = _read_table_unlocked(folder)
        mapping = parse_insert_mapping(cols, args[1:])
        row = _append_mapping_unlocked(folder, cols, mapping)
    values_desc = ", ".join(f"{cols[i]}='{row[i]}'" for i in mapping)
    cprint(f"Table '{table}': appended record ID {row[0]} ({values_desc}).")

def table_paths(db: str, table: str) -> tuple[pathlib.Path, pathlib.Path, pathlib.Path]:
    d = ensure_db_layout(db)
    table = valid_name(table, "table name")
    folder = d["tables"] / table
    return folder, folder / "columns", folder / "tables"


def _storage_paths(folder: pathlib.Path) -> tuple[pathlib.Path, pathlib.Path, pathlib.Path]:
    storage = folder / ".storage"
    return storage, storage / "manifest.json", storage / "generations"


def _read_columns_unlocked(folder: pathlib.Path) -> list[str]:
    path = folder / "columns"
    cols = [x.strip() for x in path.read_text(encoding="utf-8", errors="replace").splitlines() if x.strip()] if path.exists() else ["id"]
    return cols or ["id"]


def _legacy_rows_unlocked(folder: pathlib.Path, cols: list[str]) -> list[list[str]]:
    legacy = folder / "tables"
    rows: list[list[str]] = []
    if not legacy.exists(): return rows
    next_id = 1
    for line in legacy.read_text(encoding="utf-8", errors="replace").splitlines():
        if not line.strip(): continue
        # Legacy rows were whitespace-delimited. shlex preserves cells that
        # were quoted by compatible writers (e.g. "New York") while retaining
        # backwards compatibility with older simple, unquoted rows.
        try:
            values = shlex.split(line, comments=False, posix=True)
        except ValueError as exc:
            raise RuntimeError(f"Invalid legacy row in {legacy}: {exc}") from exc
        values.extend([""] * max(0, len(cols) - len(values)))
        row = values[:len(cols)]
        if cols[0] == "id":
            try:
                rid = int(row[0])
                if rid <= 0: raise ValueError
            except (ValueError, TypeError):
                row[0] = str(next_id)
            next_id = max(next_id, int(row[0]) + 1)
        rows.append(row)
    return rows


def _read_manifest_unlocked(folder: pathlib.Path) -> dict[str, Any] | None:
    _, manifest_path, _ = _storage_paths(folder)
    if not manifest_path.is_file(): return None
    try:
        data = json.loads(manifest_path.read_text(encoding="utf-8"))
        if data.get("version") != STORAGE_VERSION or not isinstance(data.get("shards"), dict):
            raise ValueError("Unsupported table storage manifest.")
        return data
    except Exception as exc:
        raise RuntimeError(f"Table storage manifest is corrupt: {manifest_path}: {exc}") from exc


def _load_shard_rows_unlocked(folder: pathlib.Path, manifest: dict[str, Any], cols: list[str]) -> list[list[str]]:
    storage, _, generations = _storage_paths(folder)
    generation_dir = generations / str(manifest["generation"])
    rows_with_ids: list[tuple[int, list[str]]] = []
    for _, filename in sorted(manifest["shards"].items(), key=lambda item: int(item[0])):
        shard_path = generation_dir / filename
        if not shard_path.is_file():
            raise RuntimeError(f"Missing table shard: {shard_path}")
        with shard_path.open("r", encoding="utf-8") as stream:
            for line_no, line in enumerate(stream, 1):
                if not line.strip(): continue
                try:
                    item = json.loads(line)
                    row = [str(v) for v in item["values"]]
                    rid = int(item["id"])
                    if not row: row = [str(rid)]
                    row.extend([""] * max(0, len(cols) - len(row)))
                    row = row[:len(cols)]
                    if cols[0] == "id": row[0] = str(rid)
                    rows_with_ids.append((rid, row))
                except Exception as exc:
                    raise RuntimeError(f"Invalid JSONL record in {shard_path}:{line_no}: {exc}") from exc
    rows_with_ids.sort(key=lambda pair: pair[0])
    return [row for _, row in rows_with_ids]


def _index_enabled_unlocked(folder: pathlib.Path) -> bool:
    marker = folder / ".index_enabled"
    if not marker.exists():
        atomic_write_text(marker, "true\n", 0o600)
        return True
    return marker.read_text(encoding="utf-8", errors="replace").strip().lower() != "false"


def _build_index(cols: list[str], rows: list[list[str]]) -> dict[str, dict[str, list[int]]]:
    index: dict[str, dict[str, list[int]]] = {col: {} for col in cols}
    for row in rows:
        if not row: continue
        try: rid = int(row[0])
        except (ValueError, TypeError): continue
        for i, col in enumerate(cols):
            value = row[i] if i < len(row) else ""
            index[col].setdefault(value, []).append(rid)
    return index


def _commit_rows_unlocked(folder: pathlib.Path, cols: list[str], rows: list[list[str]]) -> None:
    """Write a complete new generation, then atomically publish its manifest.

    Readers see either the previous generation or the complete new generation;
    an interrupted write leaves only an ignored temporary generation behind.
    """
    storage, manifest_path, generations = _storage_paths(folder)
    generations.mkdir(parents=True, exist_ok=True)
    previous = _read_manifest_unlocked(folder)
    generation = uuid.uuid4().hex
    generation_dir = generations / generation
    generation_dir.mkdir(mode=0o700)
    try:
        grouped: dict[int, list[dict[str, Any]]] = {}
        max_id = 0
        seen_ids: set[int] = set()
        for source_row in rows:
            row = [clean_cell_value(v) for v in source_row[:len(cols)]]
            row.extend([""] * max(0, len(cols) - len(row)))
            try: rid = int(row[0])
            except (ValueError, TypeError): raise ValueError("Every stored record must have a numeric primary ID.")
            if rid < 1: raise ValueError("Primary record IDs must be positive.")
            if rid in seen_ids: raise ValueError(f"Duplicate primary record ID detected: {rid}.")
            seen_ids.add(rid)
            max_id = max(max_id, rid)
            block = (rid - 1) // SHARD_SIZE
            grouped.setdefault(block, []).append({"id": rid, "values": row})
        shard_map: dict[str, str] = {}
        for block, items in sorted(grouped.items()):
            filename = f"shard_{block:08d}.jsonl"
            content = "".join(json.dumps(item, ensure_ascii=False, separators=(",", ":")) + "\n" for item in sorted(items, key=lambda x: x["id"]))
            atomic_write_text(generation_dir / filename, content, 0o600)
            shard_map[str(block)] = filename
        index_name = None
        if _index_enabled_unlocked(folder):
            index_name = "index.json"
            atomic_write_json(generation_dir / index_name, _build_index(cols, rows), 0o600)
        manifest = {"version": STORAGE_VERSION, "generation": generation, "shards": shard_map,
                    "columns": list(cols), "index": index_name, "record_count": len(rows),
                    "max_id": max_id, "shard_size": SHARD_SIZE}
        atomic_write_json(manifest_path, manifest, 0o600)
        next_id_file = folder / ".next_id"
        try: next_id = int(next_id_file.read_text().strip())
        except (OSError, ValueError): next_id = max_id + 1
        atomic_write_text(next_id_file, f"{max(next_id, max_id + 1)}\n", 0o600)
        # The manifest is committed. Old generations are now safe to remove.
        for old_dir in generations.iterdir():
            if old_dir.is_dir() and old_dir.name != generation:
                shutil.rmtree(old_dir, ignore_errors=True)
    except Exception:
        shutil.rmtree(generation_dir, ignore_errors=True)
        raise


def _ensure_storage_unlocked(folder: pathlib.Path, cols: list[str]) -> dict[str, Any]:
    manifest = _read_manifest_unlocked(folder)
    if manifest is not None:
        return manifest
    storage, _, generations = _storage_paths(folder)
    storage.mkdir(parents=True, exist_ok=True)
    generations.mkdir(parents=True, exist_ok=True)
    rows = _legacy_rows_unlocked(folder, cols)
    _commit_rows_unlocked(folder, cols, rows)
    manifest = _read_manifest_unlocked(folder)
    if manifest is None: raise RuntimeError("Could not initialize table storage.")
    return manifest


def _read_table_unlocked(folder: pathlib.Path) -> tuple[list[str], list[list[str]], pathlib.Path]:
    if not folder.is_dir(): raise FileNotFoundError(f"Table directory does not exist: {folder}")
    manifest = _read_manifest_unlocked(folder)
    if manifest is not None and isinstance(manifest.get("columns"), list) and manifest["columns"]:
        cols = [str(c) for c in manifest["columns"]]
    else:
        cols = _read_columns_unlocked(folder)
    manifest = _ensure_storage_unlocked(folder, cols)
    # The manifest is authoritative, so an interrupted schema update cannot
    # expose new columns with an old shard generation (or vice versa).
    cols = [str(c) for c in manifest.get("columns", cols)]
    rows = _load_shard_rows_unlocked(folder, manifest, cols)
    return cols, rows, folder / "tables"


def _append_mapping_unlocked(folder: pathlib.Path, cols: list[str], mapping: dict[int, str]) -> list[str]:
    _, rows, _ = _read_table_unlocked(folder)
    next_id_file = folder / ".next_id"
    try: next_id = int(next_id_file.read_text(encoding="utf-8").strip())
    except (OSError, ValueError): next_id = max((int(r[0]) for r in rows if r and r[0].isdigit()), default=0) + 1
    next_id = max(next_id, max((int(r[0]) for r in rows if r and r[0].isdigit()), default=0) + 1)
    row = [""] * len(cols)
    if cols and cols[0] == "id": row[0] = str(next_id)
    for idx, value in mapping.items():
        if idx < 0 or idx >= len(cols): raise ValueError("Invalid column index for insert.")
        if idx == 0 and cols[0] == "id": raise ValueError("The primary id column is generated automatically.")
        row[idx] = clean_cell_value(value)
    # Append-only semantics: never search for or overwrite an empty row slot.
    rows.append(row)
    atomic_write_text(next_id_file, f"{next_id + 1}\n", 0o600)
    _commit_rows_unlocked(folder, cols, rows)
    return row


def append_record(db: str, table: str, mapping: dict[str, Any]) -> list[str]:
    folder, columns_file, _ = table_paths(db, table)
    if not folder.is_dir(): raise FileNotFoundError(f"Table '{table}' does not exist.")
    with table_lock(folder):
        cols, _, _ = _read_table_unlocked(folder)
        col_mapping: dict[int, str] = {}
        for col, value in mapping.items():
            if col not in cols: raise ValueError(f"Column '{col}' does not exist in table '{table}'.")
            idx = cols.index(col)
            if col == "id": raise ValueError("The primary id column is generated automatically.")
            col_mapping[idx] = clean_cell_value(value)
        if not col_mapping: raise ValueError("No valid column values were provided.")
        return _append_mapping_unlocked(folder, cols, col_mapping)


def api_append_record(db: str, table: str, values: Any) -> list[str]:
    """Append an API record under one cross-thread/process critical section.

    The schema read, mapping validation, ID allocation, shard generation and
    manifest publication happen while the same table lock is held. The storage
    generation and manifest are written atomically by _commit_rows_unlocked().
    """
    folder, _, _ = table_paths(db, table)
    if not folder.is_dir():
        raise FileNotFoundError(f"Table '{table}' does not exist.")
    with table_lock(folder):
        cols, _, _ = _read_table_unlocked(folder)
        if isinstance(values, dict):
            mapping = {str(k): v for k, v in values.items()}
        elif isinstance(values, list):
            start = 1 if cols and cols[0] == "id" else 0
            mapping = {cols[start + i]: value for i, value in enumerate(values)
                       if start + i < len(cols)}
        else:
            raw = clean_cell_value(values)
            parts = raw.split("|")
            start = 1 if cols and cols[0] == "id" else 0
            mapping = {cols[start + i]: value for i, value in enumerate(parts)
                       if start + i < len(cols)}

        col_mapping: dict[int, str] = {}
        for column, value in mapping.items():
            if column not in cols:
                raise ValueError(f"Column '{column}' does not exist in table '{table}'.")
            if column == "id":
                raise ValueError("The primary id column is generated automatically.")
            col_mapping[cols.index(column)] = clean_cell_value(value)
        if not col_mapping:
            raise ValueError("No valid column values were provided.")
        return _append_mapping_unlocked(folder, cols, col_mapping)


def api_delete_record(db: str, table: str, target: str) -> int:
    """Delete matching API record(s) with flock + atomic manifest publication."""
    folder, _, _ = table_paths(db, table)
    if not folder.is_dir():
        raise FileNotFoundError(f"Table '{table}' does not exist.")
    with table_lock(folder):
        cols, rows, _ = _read_table_unlocked(folder)
        remaining = [row for row in rows
                     if json.dumps(row, ensure_ascii=False) != target and " ".join(row) != target]
        removed = len(rows) - len(remaining)
        if removed:
            _commit_rows_unlocked(folder, cols, remaining)
        return removed


def read_table(db: str, table: str) -> tuple[list[str], list[list[str]], pathlib.Path]:
    """Read a consistent table snapshot; JSONL cells preserve embedded spaces."""
    folder, _, _ = table_paths(db, table)
    if not folder.is_dir():
        raise FileNotFoundError(f"Table '{table}' does not exist in database '{db}'.")
    with table_lock(folder):
        cols, rows, data_file = _read_table_unlocked(folder)
        rows = [[str(value) for value in row] for row in rows]
        return cols, rows, data_file


def write_table(columns: list[str], rows: list[list[str]], data_file: pathlib.Path) -> None:
    folder = data_file.parent
    with table_lock(folder):
        if not columns: columns = ["id"]
        atomic_write_text(folder / "columns", "".join(c + "\n" for c in columns), 0o600)
        _ensure_storage_unlocked(folder, columns)
        _commit_rows_unlocked(folder, columns, rows)


@contextlib.contextmanager
def edit_table(db: str, table: str):
    folder, _, data_file = table_paths(db, table)
    if not folder.is_dir(): raise FileNotFoundError(f"Table '{table}' does not exist in database '{db}'.")
    with table_lock(folder):
        cols, rows, _ = _read_table_unlocked(folder)
        yield cols, rows, data_file
        atomic_write_text(folder / "columns", "".join(c + "\n" for c in cols), 0o600)
        _commit_rows_unlocked(folder, cols, rows)


def replace_table_rows(db: str, table: str, cols: list[str], rows: list[list[str]]) -> None:
    folder, _, _ = table_paths(db, table)
    with table_lock(folder):
        _ensure_storage_unlocked(folder, cols)
        _commit_rows_unlocked(folder, cols, rows)


def search_rows(db: str, table: str, column: str, value: str,
                cols: list[str] | None = None, rows: list[list[str]] | None = None) -> list[list[str]]:
    folder, _, _ = table_paths(db, table)
    with table_lock(folder):
        current_cols, current_rows, _ = _read_table_unlocked(folder)
        # Always search the same locked snapshot as the index manifest; callers
        # cannot pass a stale row snapshot from before a concurrent update.
        if column not in current_cols: raise ValueError(f"Column '{column}' does not exist in table '{table}'.")
        manifest = _read_manifest_unlocked(folder) or {}
        index_name = manifest.get("index")
        if index_name:
            generation_dir = _storage_paths(folder)[2] / str(manifest["generation"])
            index_path = generation_dir / index_name
            try:
                index = json.loads(index_path.read_text(encoding="utf-8"))
                ids = set(index.get(column, {}).get(value, []))
                return [row for row in current_rows if row and int(row[0]) in ids]
            except (OSError, ValueError, TypeError, json.JSONDecodeError):
                pass
        idx = current_cols.index(column)
        return [row for row in current_rows if idx < len(row) and row[idx] == value]


def search_table(db: str, args: list[str]) -> None:
    if len(args) < 3: raise ValueError('Usage: search <table> <column> "<value with spaces>"')
    table, column = args[0], args[1]
    value = " ".join(args[2:])
    cols, rows = read_table(db, table)[:2]
    matches = search_rows(db, table, column, value, cols, rows)
    print(f"{CYAN}{BOLD}Search results: {table}.{column} = '{value}'{RESET}")
    if not matches:
        print("  (No matching records)")
        return
    for row in matches:
        print("  " + json.dumps(dict(zip(cols, row)), ensure_ascii=False))


def index_command(db: str, args: list[str]) -> None:
    if len(args) != 2: raise ValueError("Usage: index <table> <on|off|rebuild|status>")
    table, action = args[0], args[1].lower()
    folder, _, _ = table_paths(db, table)
    if not folder.is_dir(): raise FileNotFoundError(f"Table '{table}' does not exist.")
    with table_lock(folder):
        cols, rows, _ = _read_table_unlocked(folder)
        marker = folder / ".index_enabled"
        if action == "status":
            enabled = _index_enabled_unlocked(folder)
            manifest = _read_manifest_unlocked(folder) or {}
            print(f"Index for '{table}': {'enabled' if enabled and manifest.get('index') else 'disabled'}")
            return
        if action not in ("on", "off", "rebuild"):
            raise ValueError("Index action must be on, off, rebuild or status.")
        atomic_write_text(marker, ("false" if action == "off" else "true") + "\n", 0o600)
        _commit_rows_unlocked(folder, cols, rows)
        cprint(f"Index for table '{table}' is now {'disabled' if action == 'off' else 'enabled and rebuilt'}.")

def list_databases() -> None:
    items = sorted(p.name for p in DB_ROOT.iterdir() if p.is_dir() and (p / f"{p.name}.db").is_file()) if DB_ROOT.exists() else []
    if not items:
        cprint("Error: No databases exist.", RED)
        return
    print(f"{CYAN}{BOLD}Available databases:{RESET}")
    for name in items:
        print(f"  - {GREEN}{name}{RESET}")


def database_describe(db: str, metadata_only: bool = False) -> None:
    db = valid_name(db, "database name")
    if not (db_dir(db) / f"{db}.db").is_file():
        raise FileNotFoundError(f"Database '{db}' does not exist.")
    d = ensure_db_layout(db)
    meta = d["base"] / f"{db}.db"
    print(f"{CYAN}{BOLD}Database Structure for '{db}':{RESET}")
    if meta.exists():
        try:
            print(json.dumps(json.loads(meta.read_text(encoding="utf-8")), indent=2, ensure_ascii=False))
        except Exception:
            print(meta.read_text(encoding="utf-8", errors="replace"))
    if metadata_only:
        return
    for folder in sorted(p for p in d["tables"].iterdir() if p.is_dir()):
        cols, rows, _ = read_table(db, folder.name)
        print(f"\n{CYAN}{BOLD}Table: {folder.name}{RESET}")
        matrix = [cols] + rows
        widths = [max(4, *(len(row[i]) for row in matrix)) for i in range(len(cols))]
        def fmt(row: list[str]) -> str:
            return "│ " + " │ ".join(row[i].ljust(widths[i]) for i in range(len(cols))) + " │"
        print("┌" + "┬".join("─" * (w + 2) for w in widths) + "┐")
        print(fmt(cols))
        print("├" + "┼".join("─" * (w + 2) for w in widths) + "┤")
        if rows:
            for row in rows:
                print(fmt(row))
        else:
            print(fmt([""] * len(cols)))
        print("└" + "┴".join("─" * (w + 2) for w in widths) + "┘")


def table_create(db: str, names: list[str]) -> None:
    if not names:
        raise ValueError("Usage: create_table <name>")
    d = ensure_db_layout(db)
    with file_lock(d["base"] / ".schema.lock"):
        for name in names:
            folder = d["tables"] / valid_name(name, "table name")
            if folder.exists():
                cprint(f"Error: Table '{name}' already exists.", RED)
                continue
            folder.mkdir(parents=True)
            atomic_write_text(folder / "columns", "id\n", 0o600)
            (folder / "tables").touch()
            atomic_write_text(folder / ".index_enabled", "true\n", 0o600)
            atomic_write_text(folder / ".next_id", "1\n", 0o600)
            cprint(f"Table '{name}' created successfully.")


def table_drop(db: str, names: list[str]) -> None:
    if not names:
        raise ValueError("Usage: drop_table <name>")
    d = ensure_db_layout(db)
    with file_lock(d["base"] / ".schema.lock"):
        for name in names:
            folder = d["tables"] / valid_name(name, "table name")
            if not folder.is_dir():
                cprint(f"Error: Table '{name}' does not exist.", RED)
                continue
            with table_lock(folder):
                shutil.rmtree(folder)
            cprint(f"Table '{name}' dropped successfully.")


def table_rename(db: str, args: list[str]) -> None:
    if len(args) != 2:
        raise ValueError("Usage: rename_table <name> <newname>")
    old, new = args
    d = ensure_db_layout(db)
    src = d["tables"] / valid_name(old, "table name")
    dst = d["tables"] / valid_name(new, "table name")
    with file_lock(d["base"] / ".schema.lock"):
        if not src.is_dir(): raise FileNotFoundError(f"Table '{old}' does not exist.")
        if dst.exists(): raise FileExistsError(f"Table '{new}' already exists.")
        with table_lock(src):
            src.rename(dst)
    cprint(f"Table '{old}' renamed to '{new}' successfully.")
def column_create(db: str, args: list[str]) -> None:
    if len(args) < 2: raise ValueError("Usage: create_column <table> <column> [column ...]")
    table, names = args[0], args[1:]
    with edit_table(db, table) as (cols, rows, _):
        for name in names:
            valid_name(name, "column name")
            if name in cols:
                cprint(f"Error: Column '{name}' already exists in table '{table}'.", RED)
                continue
            cols.append(name)
            for row in rows: row.append("")
            cprint(f"Column '{name}' added to table '{table}'.")

def column_drop(db: str, args: list[str]) -> None:
    if len(args) != 2: raise ValueError("Usage: drop_column <table> <column>")
    table, name = args
    with edit_table(db, table) as (cols, rows, _):
        if name not in cols: raise ValueError(f"Column '{name}' does not exist in table '{table}'.")
        if name == "id": raise ValueError("Cannot drop primary id column.")
        index = cols.index(name)
        cols.pop(index)
        for row in rows:
            if index < len(row): row.pop(index)
    cprint(f"Column '{name}' dropped from table '{table}'.")

def column_show(db: str, table: str) -> None:
    cols, _, _ = read_table(db, table)
    width = max(15, max((len(c) for c in cols), default=0), len("COLUMNS"))
    print("┌" + "─" * (width + 2) + "┐")
    print("│ " + f"{'COLUMNS':<{width}}" + " │")
    print("├" + "─" * (width + 2) + "┤")
    for col in cols: print("│ " + f"{col:<{width}}" + " │")
    print("└" + "─" * (width + 2) + "┘")


def column_rename(db: str, args: list[str]) -> None:
    if len(args) != 3: raise ValueError("Usage: rename_column <table> <column> <newcolumn>")
    table, old, new = args
    valid_name(new, "column name")
    with edit_table(db, table) as (cols, rows, _):
        if old not in cols: raise ValueError(f"Column '{old}' does not exist.")
        if new in cols: raise ValueError(f"Column '{new}' already exists.")
        cols[cols.index(old)] = new
    cprint(f"Column '{old}' renamed to '{new}'.")

def select_tables(db: str, names: list[str]) -> None:
    if not names: raise ValueError("Usage: select_from <table>")
    for name in names:
        table_show(db, [name])


def update_rows(db: str, args: list[str]) -> None:
    if len(args) != 4: raise ValueError('Usage: update <table> <column> "<value>" "<newvalue>"')
    table, col, old, new = args
    old = clean_cell_value(old)
    new = clean_cell_value(new)
    with edit_table(db, table) as (cols, rows, _):
        if col not in cols: raise ValueError(f"Column '{col}' does not exist.")
        idx = cols.index(col)
        count = 0
        for row in rows:
            if row[idx] == old:
                row[idx] = new
                count += 1
    cprint(f"Updated {count} record(s).")

def delete_rows(db: str, args: list[str]) -> None:
    if len(args) != 1: raise ValueError("Usage: delete_from <table>")
    table = args[0]
    with edit_table(db, table) as (cols, rows, _):
        count = len(rows)
        rows.clear()
    cprint(f"All {count} record(s) deleted from table '{table}'.")

def delete_record_rows(db: str, args: list[str]) -> None:
    if len(args) < 2: raise ValueError("Usage: delete_record <table> <column> <value> OR delete_record <table> <record>")
    table = args[0]
    with edit_table(db, table) as (cols, rows, _):
        if len(args) >= 3 and args[1] in cols:
            col, target = args[1], " ".join(args[2:])
            idx = cols.index(col)
            remaining = [row for row in rows if row[idx] != target]
            removed = len(rows) - len(remaining)
            if not removed: raise FileNotFoundError(f"Record not found in column '{col}'.")
        else:
            target = " ".join(args[1:])
            remaining = [row for row in rows if " ".join(row) != target and json.dumps(row, ensure_ascii=False) != target]
            removed = len(rows) - len(remaining)
            if not removed: raise FileNotFoundError(f"Record '{target}' not found.")
        rows[:] = remaining
    cprint(f"{removed} record(s) deleted from table '{table}'.")

def api_permissions_command(db: str, args: list[str]) -> None:
    d = ensure_db_layout(db)
    path = d["api"] / "public" / "permissions.cfg"
    defaults = {"show_tables": "false", "dump_db": "false", "select_from": "false", "insert_into": "false",
                "create_table": "false", "drop_table": "false", "delete_from": "false", "delete_record": "false",
                "create_column": "false", "drop_column": "false", "show_columns": "false", "rename_column": "false",
                "update": "false", "rename_table": "false"}
    current = defaults.copy(); current.update(read_kv(path))
    if not args:
        print(f"{CYAN}{BOLD}Public API Permissions for '{db}':{RESET}")
        for key, val in current.items(): print(f"  - {CYAN}{key}{RESET}: {YELLOW}{val}{RESET}")
        return
    if len(args) != 2: raise ValueError("Usage: api_permissions <permission> <true|false>")
    name, value = args
    if name not in defaults: raise ValueError(f"Permission '{name}' does not exist.")
    current[name] = parse_bool(value)
    write_kv(path, current, 0o600)
    cprint(f"Permission '{name}' updated successfully to '{value}'.")


def dispatch(db: str, command: str, raw_args: str) -> int:
    """Return 0 when handled, 2 when the original Bash CLI should handle it."""
    migrate_legacy_storage()
    command = command.strip()
    args = parse_args(raw_args)
    try:
        if command == "create_database":
            parts = [parse_args(part)[0] for part in raw_args.split("&") if parse_args(part)] if "&" in raw_args else args
            db_create(parts); return 0
        if command == "drop_database":
            parts = [parse_args(part)[0] for part in raw_args.split("&") if parse_args(part)] if "&" in raw_args else args
            db_drop(parts); return 0
        if command == "use":
            if len(args) != 1: raise ValueError("Usage: use <name>")
            name = valid_name(args[0], "database name")
            if not (db_dir(name) / f"{name}.db").is_file():
                raise FileNotFoundError(f"Database '{name}' does not exist.")
            ensure_db_layout(name)
            cprint(f"Switched to database: {name}")
            return 0
        if command == "rename_database":
            rename_args = [parse_args(part)[0] for part in raw_args.split("&") if parse_args(part)] if "&" in raw_args else args
            db_rename(rename_args); return 0
        if command == "system_process":
            if args and args[0] == "kill":
                if len(args) != 2: raise ValueError("Usage: system_process kill <process|pid>")
                target = args[1]
                killed = False
                if DB_ROOT.exists():
                    for base in [p for p in DB_ROOT.iterdir() if p.is_dir()]:
                        db_name = base.name
                        for api_type in ("public", "secret"):
                            pf = base / "api" / api_type / "api.pid"
                            matches = (target == db_name or target == api_type or target == f"{db_name}-{api_type}"
                                       or (target.isdigit() and pid_value(pf) == int(target)))
                            if matches and pf.exists():
                                killed = stop_pid_file(pf) or killed
                        for func in ("backup", "backup_delete"):
                            pf = base / "secrets" / f"backup_{func}.pid"
                            viewer_pf = base / "secrets" / f"backup_{func}_viewer.pid"
                            matches = (target == db_name or target in (func, f"backup_{func}")
                                       or (target.isdigit() and (pid_value(pf) == int(target) or pid_value(viewer_pf) == int(target))))
                            if matches:
                                killed = stop_backup_worker(db_name, func) or killed
                if not killed:
                    raise FileNotFoundError(f"Managed process '{target}' not found or could not be terminated. Arbitrary system PIDs are not accepted.")
                cprint(f"Managed process '{target}' and its child processes were terminated successfully.")
            else:
                system_process(db)
            return 0
        if command == "system_terminate": system_terminate("--force" in args); return 0
        if command == "api_key":
            if db == "none": raise ValueError("No active database. Use 'use <name>' first.")
            api_key_command(db, args); return 0
        if command == "api_key_add":
            if db == "none": raise ValueError("No active database. Use 'use <name>' first.")
            api_key_command(db, ["add"] + args); return 0
        if command == "api_key_remove":
            if db == "none": raise ValueError("No active database. Use 'use <name>' first.")
            api_key_command(db, ["remove"] + args); return 0
        if command == "api_key_list":
            if db == "none": raise ValueError("No active database. Use 'use <name>' first.")
            api_key_command(db, ["list"]); return 0
        if command in ("api_setup", "api_edit", "api_start", "api_stop", "api_delete", "api_status", "api_request"):
            if db == "none": raise ValueError("No active database. Use 'use <name>' first.")
            if command == "api_request": api_request(db, args); return 0
            api_type = args[0] if args else "public"
            if api_type not in ("public", "secret"): raise ValueError("API type must be 'public' or 'secret'.")
            if command == "api_setup": api_setup(db, api_type)
            elif command == "api_edit": api_edit(db, api_type)
            elif command == "api_start": api_start(db, api_type)
            elif command == "api_stop":
                pid_path = api_cfg_path(db, api_type).parent / "api.pid"
                if not process_alive(pid_path):
                    stop_pid_file(pid_path)
                    cprint(f"API ({api_type}) is not currently running.", YELLOW)
                else:
                    stop_pid_file(pid_path); cprint(f"API ({api_type}) stopped successfully.")
            elif command == "api_delete":
                p = api_cfg_path(db, api_type).parent
                if not (p / "api.cfg").exists(): raise FileNotFoundError(f"API ({api_type}) does not exist.")
                stop_pid_file(p / "api.pid")
                if p.exists(): shutil.rmtree(p)
                cprint(f"API ({api_type}) deleted successfully.")
            elif command == "api_status": api_status(db, api_type)
            return 0
        if command == "backup":
            if db == "none": raise ValueError("No active database. Use 'use <name>' first.")
            force = "--force" in args
            names = [x for x in args if x != "--force"]
            if len(names) > 1: raise ValueError("Backup name cannot contain spaces. Usage: backup <name> [--force]")
            backup_name = names[0] if names else None
            if backup_name:
                valid_backup_name(backup_name)
                cfg = read_backup_config(db)
                suffix = ".tar.gz" if cfg_value(cfg, "auto_compression", "true").lower() == "true" else ".tar"
                if cfg_value(cfg, "encrypt_backups", "false").lower() == "true": suffix += ".enc"
                existing = backup_directory(db, cfg) / (backup_name + suffix)
                if existing.exists() and not force:
                    answer = input(f"Warning: Backup '{backup_name}' already exists and will be overwritten. Proceed? (yes/no): ").strip().lower()
                    if answer != "yes": cprint("Action cancelled.", YELLOW); return 0
                    force = True
            create_backup(db, backup_name, force=force); return 0
        if command == "backups":
            if db == "none": raise ValueError("No active database. Use 'use <name>' first.")
            show_backups(db); return 0
        if command == "backup_restore":
            if db == "none": raise ValueError("No active database. Use 'use <name>' first.")
            force = "--force" in args; names = [x for x in args if x != "--force"]
            if len(names) != 1: raise ValueError("Usage: backup_restore <name> [--force]")
            restore_backup(db, names[0], force); return 0
        if command == "backup_delete":
            if db == "none": raise ValueError("No active database. Use 'use <name>' first.")
            force = "--force" in args; names = [x for x in args if x != "--force"]
            if len(names) != 1: raise ValueError("Usage: backup_delete <name> [--force]")
            if not force:
                ans = input(f"Delete backup '{names[0]}'? (yes/no): ").strip().lower()
                if ans != "yes": cprint("Action cancelled.", YELLOW); return 0
            delete_backup(db, names[0]); return 0
        if command == "backup_schedule":
            if db == "none": raise ValueError("No active database. Use 'use <name>' first.")
            backup_schedule(db, args); return 0
        if command == "backup_configs":
            if db == "none": raise ValueError("No active database. Use 'use <name>' first.")
            backup_configs(db, args); return 0
        if command == "show_databases":
            list_databases(); return 0
        if command in ("describe", "dump_db"):
            targets = args if command == "describe" and args else ([db] if not args else [args[0]])
            if not targets or targets == ["none"]: raise ValueError("Database name required. Usage: describe <name>")
            for target in targets:
                database_describe(target, metadata_only=(command == "describe"))
            return 0
        if command == "api_permissions":
            if db == "none": raise ValueError("No active database. Use 'use <name>' first.")
            api_permissions_command(db, args); return 0
        if command == "show_tables":
            if db == "none": raise ValueError("No active database. Use 'use <name>' first.")
            table_show(db, args); return 0
        if command == "select_from":
            if db == "none": raise ValueError("No active database. Use 'use <name>' first.")
            select_tables(db, args); return 0
        if command == "search":
            if db == "none": raise ValueError("No active database. Use 'use <name>' first.")
            search_table(db, args); return 0
        if command == "index":
            if db == "none": raise ValueError("No active database. Use 'use <name>' first.")
            index_command(db, args); return 0
        if command == "insert_into":
            if db == "none": raise ValueError("No active database. Use 'use <name>' first.")
            groups = [part.strip() for part in raw_args.split("&") if part.strip()]
            if not groups: raise ValueError('Usage: insert_into <table> <column> "<value with spaces>" [<column> "<value>"]')
            for group in groups:
                table_insert(db, parse_args(group))
            return 0
        if command == "create_table":
            if db == "none": raise ValueError("No active database. Use 'use <name>' first.")
            parts = [parse_args(part)[0] for part in raw_args.split("&") if parse_args(part)] if "&" in raw_args else args
            table_create(db, parts); return 0
        if command == "drop_table":
            if db == "none": raise ValueError("No active database. Use 'use <name>' first.")
            parts = [parse_args(part)[0] for part in raw_args.split("&") if parse_args(part)] if "&" in raw_args else args
            table_drop(db, parts); return 0
        if command == "rename_table":
            if db == "none": raise ValueError("No active database. Use 'use <name>' first.")
            table_rename(db, args); return 0
        if command == "create_column":
            if db == "none": raise ValueError("No active database. Use 'use <name>' first.")
            column_create(db, args); return 0
        if command == "drop_column":
            if db == "none": raise ValueError("No active database. Use 'use <name>' first.")
            column_drop(db, args); return 0
        if command == "show_columns":
            if db == "none": raise ValueError("No active database. Use 'use <name>' first.")
            if len(args) != 1: raise ValueError("Usage: show_columns <table>")
            column_show(db, args[0]); return 0
        if command == "rename_column":
            if db == "none": raise ValueError("No active database. Use 'use <name>' first.")
            column_rename(db, args); return 0
        if command == "update":
            if db == "none": raise ValueError("No active database. Use 'use <name>' first.")
            update_rows(db, args); return 0
        if command == "delete_from":
            if db == "none": raise ValueError("No active database. Use 'use <name>' first.")
            if not args: raise ValueError("Usage: delete_from <table>")
            for table_name in args:
                delete_rows(db, [table_name])
            return 0
        if command == "delete_record":
            if db == "none": raise ValueError("No active database. Use 'use <name>' first.")
            groups = [parse_args(part) for part in raw_args.split("&") if parse_args(part)] if "&" in raw_args else [args]
            for group in groups:
                delete_record_rows(db, group)
            return 0
    except KeyboardInterrupt:
        cprint("Operation cancelled.", YELLOW); return 0
    except Exception as exc:
        cprint(f"Error: {exc}", RED); return 0
    return 2
    
def main() -> int:
    if len(sys.argv) >= 2 and sys.argv[1] == "--serve":
        server_main(sys.argv[2], sys.argv[3]); return 0
    if len(sys.argv) >= 2 and sys.argv[1] == "--worker":
        worker_main(sys.argv[2], sys.argv[3], int(sys.argv[4])); return 0
    if len(sys.argv) < 4: return 2
    return dispatch(sys.argv[1], sys.argv[2], sys.argv[3])


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(130)

#__DBM_PYTHON_END__
__DB_MANAGER_PYTHON_PAYLOAD__
