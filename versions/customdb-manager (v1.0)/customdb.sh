#!/bin/sh

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

mkdir -p db_manage/database db_manage/secrets backups
[ -e "db_manage/secrets/secrets.env" ] || touch "db_manage/secrets/secrets.env"
[ -e "db_manage/secrets/database.cfg" ] || touch "db_manage/secrets/database.cfg"
[ -e "db_manage/secrets/api.cfg" ] || touch "db_manage/secrets/api.cfg"

show_banner() {
    clear
    printf '%b' "${CYAN}==================================================${NC}\n"
    printf '%b' "${BOLD}        CUSTOM DB MANAGER CLI - Version 1.0     ${NC}\n"
    printf '%b' "${CYAN}==================================================${NC}\n"
    printf '%b' " Type '${YELLOW}help${NC}' for commands or '${RED}exit${NC}' to quit.\n\n"
}

generate_server_script() {
    server_script="$1"
    cat << 'EOF' > "$server_script"
import http.server
import json
import os
import urllib.parse
import ssl
import time
from collections import defaultdict

PORT = int(os.environ.get("API_PORT", 8080))
SECRET_KEY = os.environ.get("API_SECRET", "default_secret")
DB_NAME = os.environ.get("DB_NAME", "db")
PROTOCOL = os.environ.get("API_PROTOCOL", "http")
API_TYPE = os.environ.get("API_TYPE", "public")
CERT_FILE = os.environ.get("API_CERT", "")
KEY_FILE = os.environ.get("API_KEY", "")

DB_BASE_DIR = os.path.join("db_manage", "database")
DB_PATH = os.path.join(DB_BASE_DIR, DB_NAME)
TABLES_DIR = os.path.join(DB_PATH, "tables")
API_DIR = os.path.join(DB_PATH, "api", API_TYPE)
PERM_FILE = os.path.join(API_DIR, "permissions.cfg")

REQUEST_TIMESTAMPS = defaultdict(list)

class DBAPIHandler(http.server.BaseHTTPRequestHandler):
    def _check_auth(self):
        client_key = self.headers.get("X-Secret-Key")
        parsed_path = urllib.parse.urlparse(self.path)
        query_params = urllib.parse.parse_qs(parsed_path.query)
        query_key = query_params.get("key", [None])[0]
        
        if client_key == SECRET_KEY or query_key == SECRET_KEY:
            return True
        return False

    def _check_permission(self, perm_name):
        if API_TYPE == "secret":
            return True
        if not os.path.exists(PERM_FILE):
            return False
        with open(PERM_FILE, "r") as f:
            for line in f:
                parts = line.strip().split("=")
                if len(parts) == 2 and parts[0] == perm_name:
                    return parts[1].lower() == "true"
        return False

    def do_GET(self):
        self._handle_request("GET")

    def do_POST(self):
        self._handle_request("POST")

    def do_PUT(self):
        self._handle_request("PUT")

    def do_DELETE(self):
        self._handle_request("DELETE")

    def _handle_request(self, method):
        if API_TYPE == "public":
            client_ip = self.client_address[0]
            current_time = time.time()
            REQUEST_TIMESTAMPS[client_ip] = [t for t in REQUEST_TIMESTAMPS[client_ip] if current_time - t < 5.0]
            if len(REQUEST_TIMESTAMPS[client_ip]) >= 10:
                self._send_response(429, {
                    "status": "error",
                    "database": DB_NAME,
                    "api_type": API_TYPE,
                    "endpoint": urllib.parse.urlparse(self.path).path,
                    "error": "Limite de requisições excedido. Por favor, tente novamente mais tarde."
                })
                return
            REQUEST_TIMESTAMPS[client_ip].append(current_time)

        if API_TYPE == "secret" and not self._check_auth():
            self._send_response(401, {"status": "error", "error": "Unauthorized"})
            return

        parsed_path = urllib.parse.urlparse(self.path)
        path = parsed_path.path
        query_params = {k: v[0] if len(v) == 1 else v for k, v in urllib.parse.parse_qs(parsed_path.query).items()}

        body_data = {}
        if method in ["POST", "PUT", "PATCH"]:
            content_length = int(self.headers.get('Content-Length', 0))
            if content_length > 0:
                body_bytes = self.rfile.read(content_length)
                try:
                    body_data = json.loads(body_bytes.decode('utf-8'))
                except Exception:
                    body_data = {"raw_body": body_bytes.decode('utf-8', errors='ignore')}

        params = {**query_params, **body_data}
        response_data = {"status": "success", "database": DB_NAME, "api_type": API_TYPE, "method": method, "endpoint": path, "protocol": PROTOCOL}
        status_code = 200

        try:
            os.makedirs(TABLES_DIR, exist_ok=True)

            if path.startswith("/api_") or path in ["/show_databases", "/create_database", "/drop_database", "/use"] or path.startswith("/create_database/") or path.startswith("/drop_database/"):
                status_code = 403
                raise ValueError(f"Error: API restriction - Endpoint '{path}' is strictly prohibited.")

            if path in ["/", "/status"]:
                tables = [f[:-4] for f in os.listdir(TABLES_DIR) if f.endswith(".tbl")] if os.path.exists(TABLES_DIR) else []
                response_data.update({
                    "message": f"Real database API server is running.",
                    "tables": tables
                })
                accept_header = self.headers.get("Accept", "")
                if "text/html" in accept_header or path == "/":
                    self._send_html_response(status_code, response_data)
                    return

            elif path == "/dump_db":
                if not self._check_permission("dump_db"):
                    status_code = 403
                    raise ValueError("Error: Permission denied for 'dump_db'.")
                metadata = ""
                db_file = os.path.join(DB_PATH, f"{DB_NAME}.db")
                if os.path.exists(db_file):
                    with open(db_file, "r") as f:
                        metadata = f.read()
                tables = [f[:-4] for f in os.listdir(TABLES_DIR) if f.endswith(".tbl")] if os.path.exists(TABLES_DIR) else []
                response_data.update({
                    "message": f"Universal database dump for '{DB_NAME}'.",
                    "metadata": json.loads(metadata) if metadata.startswith("{") else metadata,
                    "tables": tables
                })

            elif path == "/show_tables":
                if not self._check_permission("show_tables"):
                    status_code = 403
                    raise ValueError("Error: Permission denied for 'show_tables'.")
                tables = [f[:-4] for f in os.listdir(TABLES_DIR) if f.endswith(".tbl")] if os.path.exists(TABLES_DIR) else []
                response_data["tables"] = tables

            elif path.startswith("/select_from/") or path.startswith("/select/"):
                if not self._check_permission("select_from"):
                    status_code = 403
                    raise ValueError("Error: Permission denied for 'select_from'.")
                tbl_name = path.split("/")[-1]
                tbl_file = os.path.join(TABLES_DIR, f"{tbl_name}.tbl")
                if not os.path.exists(tbl_file):
                    status_code = 404
                    raise ValueError(f"Error: Table '{tbl_name}' does not exist.")
                with open(tbl_file, "r") as f:
                    records = [line.strip() for line in f if line.strip()]
                response_data["table"] = tbl_name
                response_data["records"] = records

            elif path.startswith("/insert_into/") or path.startswith("/insert/"):
                if not self._check_permission("insert_into"):
                    status_code = 403
                    raise ValueError("Error: Permission denied for 'insert_into'.")
                tbl_name = path.split("/")[-1]
                tbl_file = os.path.join(TABLES_DIR, f"{tbl_name}.tbl")
                if not os.path.exists(tbl_file):
                    status_code = 404
                    raise ValueError(f"Error: Table '{tbl_name}' does not exist.")
                
                data_to_insert = params.get("data") or params.get("record") or body_data.get("raw_body")
                if not data_to_insert:
                    status_code = 400
                    raise ValueError("Error: Missing data to insert.")
                
                with open(tbl_file, "a") as f:
                    f.write(str(data_to_insert).strip() + "\n")
                response_data["message"] = f"Data successfully inserted into table '{tbl_name}'."
                response_data["inserted_data"] = str(data_to_insert).strip()

            elif path.startswith("/create_table/"):
                if not self._check_permission("create_table"):
                    status_code = 403
                    raise ValueError("Error: Permission denied for 'create_table'.")
                tbl_name = path.split("/")[-1]
                if not tbl_name or tbl_name == "create_table":
                    status_code = 400
                    raise ValueError("Error: Table name is required.")
                tbl_file = os.path.join(TABLES_DIR, f"{tbl_name}.tbl")
                if os.path.exists(tbl_file):
                    status_code = 409
                    raise ValueError(f"Error: Table '{tbl_name}' already exists.")
                with open(tbl_file, "w") as f:
                    pass
                response_data["message"] = f"Table '{tbl_name}' created successfully."

            elif path.startswith("/drop_table/"):
                if not self._check_permission("drop_table"):
                    status_code = 403
                    raise ValueError("Error: Permission denied for 'drop_table'.")
                tbl_name = path.split("/")[-1]
                tbl_file = os.path.join(TABLES_DIR, f"{tbl_name}.tbl")
                if not os.path.exists(tbl_file):
                    status_code = 404
                    raise ValueError(f"Error: Table '{tbl_name}' does not exist.")
                os.remove(tbl_file)
                response_data["message"] = f"Table '{tbl_name}' dropped successfully."

            elif path.startswith("/delete_from/"):
                if not self._check_permission("delete_from"):
                    status_code = 403
                    raise ValueError("Error: Permission denied for 'delete_from'.")
                tbl_name = path.split("/")[-1]
                tbl_file = os.path.join(TABLES_DIR, f"{tbl_name}.tbl")
                if not os.path.exists(tbl_file):
                    status_code = 404
                    raise ValueError(f"Error: Table '{tbl_name}' does not exist.")
                header = ""
                with open(tbl_file, "r") as f_in:
                    lines = f_in.readlines()
                    if lines:
                        header = lines[0]
                with open(tbl_file, "w") as f_out:
                    if header:
                        f_out.write(header)
                response_data["message"] = f"All records deleted from table '{tbl_name}'."

            elif path.startswith("/delete_record/"):
                if not self._check_permission("delete_record"):
                    status_code = 403
                    raise ValueError("Error: Permission denied for 'delete_record'.")
                parts = path.strip("/").split("/")
                if len(parts) < 3:
                    status_code = 400
                    raise ValueError("Error: Usage format /delete_record/<table_name>/<value>")
                tbl_name = parts[1]
                target_val = urllib.parse.unquote("/".join(parts[2:]))
                tbl_file = os.path.join(TABLES_DIR, f"{tbl_name}.tbl")
                if not os.path.exists(tbl_file):
                    status_code = 404
                    raise ValueError(f"Error: Table '{tbl_name}' does not exist.")
                
                tmp_file = tbl_file + ".tmp"
                found = False
                with open(tbl_file, "r") as f_in, open(tmp_file, "w") as f_out:
                    first = True
                    for line in f_in:
                        if first:
                            f_out.write(line)
                            first = False
                            continue
                        if line.strip() == target_val:
                            found = True
                        else:
                            f_out.write(line)
                os.replace(tmp_file, tbl_file)
                
                if found:
                    response_data["message"] = f"Record deleted from table '{tbl_name}'."
                else:
                    status_code = 404
                    raise ValueError(f"Error: Record not found in table '{tbl_name}'.")

            else:
                response_data["message"] = f"Endpoint '{path}' reached and executed successfully."

        except Exception as e:
            if status_code == 200:
                status_code = 400
            response_data = {
                "status": "error",
                "database": DB_NAME,
                "api_type": API_TYPE,
                "endpoint": path,
                "error": str(e)
            }

        self._send_response(status_code, response_data)

    def _send_response(self, code, data):
        if isinstance(data, dict):
            if "message" in data:
                data["message"] = f"{data['message']} - Powered by Afonso Carreira.Inc"
            else:
                data["message"] = "Powered by Afonso Carreira.Inc"
        body = json.dumps(data, indent=2).encode('utf-8')
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_html_response(self, code, data):
        html_content = f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Database API Dashboard</title>
    <style>
        body {{ font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background: #0f172a; color: #f8fafc; margin: 0; padding: 30px; }}
        .container {{ max-width: 850px; margin: 0 auto; background: #1e293b; padding: 40px; border-radius: 12px; box-shadow: 0 8px 30px rgba(0,0,0,0.6); border: 1px solid #334155; }}
        h1 {{ color: #38bdf8; border-bottom: 2px solid #334155; padding-bottom: 12px; margin-top: 0; display: flex; justify-content: space-between; align-items: center; }}
        pre {{ background: #0f172a; padding: 20px; border-radius: 8px; overflow-x: auto; color: #38bdf8; border: 1px solid #334155; font-size: 14px; }}
        ul {{ list-style-type: none; padding: 0; }}
        li {{ background: #334155; margin: 8px 0; padding: 12px 16px; border-radius: 6px; display: flex; align-items: center; font-weight: 500; }}
        .status-box {{ background: #064e3b; border: 1px solid #059669; color: #34d399; padding: 12px 16px; border-radius: 6px; margin-bottom: 20px; font-weight: 600; }}
        .footer {{ margin-top: 20px; text-align: center; color: #38bdf8; font-weight: bold; }}
    </style>
</head>
<body>
    <div class="container">
        <h1>Database Server Dashboard <span>{DB_NAME}</span></h1>
        <div class="status-box">✓ Real API Server Active & Responding Live</div>
        <p><strong>API Type:</strong> <code>{API_TYPE.upper()}</code></p>
        <p><strong>Protocol:</strong> <code>{PROTOCOL.upper()}</code></p>
        <h3>Active Database Tables:</h3>
        <ul>
            {"".join([f"<li>📁 &nbsp; {t}</li>" for t in data.get('tables', [])]) if data.get('tables') else "<li>(No tables found)</li>"}
        </ul>
        <h3>Real Server Response Output (JSON):</h3>
        <pre>{json.dumps(data, indent=2)}</pre>
        <div class="footer">Powered by Afonso Carreira.Inc</div>
    </div>
</body>
</html>
"""
        body = html_content.encode('utf-8')
        self.send_response(code)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        pass

if __name__ == "__main__":
    server = http.server.HTTPServer(("0.0.0.0", PORT), DBAPIHandler)
    if PROTOCOL.lower() == "https" and CERT_FILE and KEY_FILE:
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(certfile=CERT_FILE, keyfile=KEY_FILE)
        server.socket = context.wrap_socket(server.socket, server_side=True)
    server.serve_forever()
EOF
}

init_permissions_file() {
    perm_file="$1"
    if [ ! -f "$perm_file" ]; then
        cat << EOF > "$perm_file"
show_tables=false
dump_db=false
select_from=false
insert_into=false
create_table=false
drop_table=false
delete_from=false
delete_record=false
create_column=false
show_columns=false
rename_column=false
update=false
rename_table=false
EOF
    fi
}

print_professional_table() {
    tbl_file="$1"
    python3 -c '
import sys, os
tbl_file = sys.argv[1]
if not os.path.exists(tbl_file):
    print("Error: Table file not found.")
    sys.exit(1)
with open(tbl_file, "r") as f:
    lines = [line.strip() for line in f if line.strip()]
if not lines:
    print("  (Table is empty)")
    sys.exit(0)
rows = [[c.strip() for c in line.split("|")] for line in lines]
max_cols = max(len(r) for r in rows)
for r in rows:
    while len(r) < max_cols:
        r.append("")
col_widths = [max(len(row[i]) for row in rows) for i in range(max_cols)]
col_widths = [max(w, 4) for w in col_widths]
def print_row(row, widths, is_header=False):
    formatted = []
    for i, val in enumerate(row):
        padded = val.ljust(widths[i])
        if is_header:
            cell_str = f"\033[1;32m{padded}\033[0m"
        else:
            cell_str = padded
        formatted.append(cell_str)
    return "│ " + " │ ".join(formatted) + " │"
def print_separator(widths, left, mid, right, fill):
    return left + fill.join(fill * (w + 2) for w in widths) + right
print(print_separator(col_widths, "┌", "┬", "┐", "─"))
print(print_row(rows[0], col_widths, is_header=True))
print(print_separator(col_widths, "├", "┼", "┤", "─"))
for row in rows[1:]:
    print(print_row(row, col_widths, is_header=False))
print(print_separator(col_widths, "└", "┴", "┘", "─"))
' "$tbl_file"
}

print_professional_columns() {
    tbl_file="$1"
    python3 -c '
import sys, os
tbl_file = sys.argv[1]
with open(tbl_file, "r") as f:
    header = f.readline().strip()
if not header:
    print("  (No columns found)")
    sys.exit(0)
cols = [c.strip() for c in header.split("|")]
max_len = max(len(c) for c in cols)
max_len = max(max_len, 15)
title_plain = "COLUMNS"
title_colored = f"\033[1;36m{title_plain:<{max_len}}\033[0m"
print("┌" + "─" * (max_len + 4) + "┐")
print(f"│ {title_colored} │")
print("├" + "─" * (max_len + 4) + "┤")
for c in cols:
    c_padded = f"{c:<{max_len}}"
    print(f"│ {c_padded} │")
print("└" + "─" * (max_len + 4) + "┘")
' "$tbl_file"
}

confirm_action() {
    force_flag="$1"
    action_desc="$2"
    if [ "$force_flag" = "--force" ]; then
        return 0
    fi
    printf '%b' "${YELLOW}Warning: $action_desc. Do you want to proceed? (yes/no): ${NC}"
    read -r ans
    if [ "$ans" = "yes" ]; then
        return 0
    else
        printf '%b' "${RED}Action cancelled.${NC}\n"
        return 1
    fi
}

parse_interval() {
    val="$1"
    num=$(echo "$val" | sed 's/[^0-9]*//g')
    unit=$(echo "$val" | sed 's/[0-9]*//g')
    [ -z "$num" ] && num="300"
    case "$unit" in
        sec) secs="$num" ;;
        min) secs=$(expr "$num" \* 60) ;;
        h) secs=$(expr "$num" \* 3600) ;;
        d) secs=$(expr "$num" \* 86400) ;;
        w) secs=$(expr "$num" \* 604800) ;;
        y) secs=$(expr "$num" \* 31536000) ;;
        *) secs="$num" ;;
    esac
    echo "$secs"
}

show_banner

while true; do
    printf '%b' "${CYAN}$HOST${NC}@${BLUE}$CURRENT_DB${NC} -> "
    read -r line
    [ -z "$line" ] && continue

    OLD_IFS="$IFS"
    IFS='|'
    set -- $line
    IFS="$OLD_IFS"

    for cmd_item in "$@"; do
        cmd_item=$(echo "$cmd_item" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [ -z "$cmd_item" ] && continue

        set -- $cmd_item
        command="$1"
        shift
        args="$*"

        case "$command" in
            "exit" | "quit")
                printf '%b' "${GREEN}Exiting. Goodbye!${NC}\n"
                exit 0
                ;;
            "help")
                printf '%b' "\n${CYAN}==================================================${NC}\n"
                printf '%b' "${BOLD}            DATABASE COMMANDS (HELP)              ${NC}\n"
                printf '%b' "${CYAN}==================================================${NC}\n\n"
                printf '%b' " ${YELLOW}[ 🌐 API INTERACTION ]${NC}\n"
                printf '%b' "   ${CYAN}api_status <public|secret>${NC}        ${GRAY}- Check API server status${NC}\n"
                printf '%b' "   ${CYAN}api_start <public|secret>${NC}         ${GRAY}- Start API server${NC}\n"
                printf '%b' "   ${CYAN}api_stop <public|secret> [--force]${NC} ${GRAY}- Stop API server${NC}\n"
                printf '%b' "   ${CYAN}api_delete <public|secret>${NC}        ${GRAY}- Delete API files${NC}\n"
                printf '%b' "   ${CYAN}api_request <public|secret> <cmd>${NC} ${GRAY}- Run CLI command via API${NC}\n"
                printf '%b' "   ${CYAN}api_setup <public|secret>${NC}         ${GRAY}- Setup API configuration${NC}\n"
                printf '%b' "   ${CYAN}api_edit <public|secret>${NC}          ${GRAY}- Edit API configuration${NC}\n"
                printf '%b' "   ${CYAN}api_permissions <perm> <true|false>${NC} ${GRAY}- Manage permissions${NC}\n"
                printf '%b' "   ${CYAN}api_key_list${NC}                      ${GRAY}- List API secret keys${NC}\n"
                printf '%b' "   ${CYAN}api_key_add <key>${NC}                 ${GRAY}- Add a secret key${NC}\n"
                printf '%b' "   ${CYAN}api_key_remove <key>${NC}              ${GRAY}- Remove a secret key${NC}\n\n"
                printf '%b' " ${YELLOW}[ 📂 DATABASE MANAGEMENT ]${NC}\n"
                printf '%b' "   ${CYAN}create_database <name>${NC}            ${GRAY}- Create a new database${NC}\n"
                printf '%b' "   ${CYAN}drop_database <name>${NC}              ${GRAY}- Delete a database${NC}\n"
                printf '%b' "   ${CYAN}rename_database <name> <newname>${NC}  ${GRAY}- Rename a database${NC}\n"
                printf '%b' "   ${CYAN}use <name>${NC}                        ${GRAY}- Select active database${NC}\n"
                printf '%b' "   ${CYAN}show_databases${NC}                    ${GRAY}- List all databases${NC}\n"
                printf '%b' "   ${CYAN}describe <name>${NC}                   ${GRAY}- Show database structure${NC}\n"
                printf '%b' "   ${CYAN}dump_db${NC}                           ${GRAY}- Show full DB dump${NC}\n\n"
                printf '%b' " ${YELLOW}[ 🗄 TABLE MANAGEMENT ]${NC}\n"
                printf '%b' "   ${CYAN}create_table <name>${NC}               ${GRAY}- Create a new table${NC}\n"
                printf '%b' "   ${CYAN}drop_table <name>${NC}                 ${GRAY}- Delete a table${NC}\n"
                printf '%b' "   ${CYAN}rename_table <name> <newname>${NC}     ${GRAY}- Rename a table${NC}\n"
                printf '%b' "   ${CYAN}show_tables <tbl>${NC}                 ${GRAY}- List tables or show specific table${NC}\n"
                printf '%b' "   ${CYAN}create_column <tbl> <col>${NC}         ${GRAY}- Add a column${NC}\n"
                printf '%b' "   ${CYAN}show_columns <tbl>${NC}                ${GRAY}- List columns in a table${NC}\n"
                printf '%b' "   ${CYAN}rename_column <tbl> <col> <newcol>${NC} ${GRAY}- Rename a column${NC}\n\n"
                printf '%b' " ${YELLOW}[ ⚡ DATA OPERATIONS ]${NC}\n"
                printf '%b' "   ${CYAN}insert_into <tbl> <col> <data>${NC}  ${GRAY}- Insert data (row or column)${NC}\n"
                printf '%b' "   ${CYAN}select_from <tbl>${NC}                 ${GRAY}- Query data from a table${NC}\n"
                printf '%b' "   ${CYAN}update <tbl> <col> <val> <newval>${NC} ${GRAY}- Update records${NC}\n"
                printf '%b' "   ${CYAN}delete_from <tbl>${NC}                 ${GRAY}- Delete all records${NC}\n"
                printf '%b' "   ${CYAN}delete_record <tbl> <col> <val>${NC} ${GRAY}- Delete specific record${NC}\n\n"
                printf '%b' " ${YELLOW}[ 📦 BACKUP MANAGEMENT ]${NC}\n"
                printf '%b' "   ${CYAN}backup <name> [--force]${NC}           ${GRAY}- Create a file structure backup${NC}\n"
                printf '%b' "   ${CYAN}backups${NC}                           ${GRAY}- List all backups professionally${NC}\n"
                printf '%b' "   ${CYAN}backup-restore <name> [--force]${NC}   ${GRAY}- Restore from backup${NC}\n"
                printf '%b' "   ${CYAN}backup_auto <true|false> <val>${NC}    ${GRAY}- Automate backups (e.g. 10min, 1h)${NC}\n\n"
                printf '%b' " ${YELLOW}[ 🛠 SYSTEM ]${NC}\n"
                printf '%b' "   ${CYAN}clear${NC}                             ${GRAY}- Clear screen${NC}\n"
                printf '%b' "   ${CYAN}help${NC}                              ${GRAY}- Show help menu${NC}\n"
                printf '%b' "   ${CYAN}exit / quit${NC}                       ${GRAY}- Exit application${NC}\n\n"
                printf '%b' "${CYAN}==================================================${NC}\n\n"
                ;;
            "clear")
                show_banner
                ;;
            "backup")
                set -- $args
                bname="$1"
                force_arg="$2"
                [ "$bname" = "--force" ] && { force_arg="--force"; bname=""; }
                [ -z "$bname" ] && bname="$(date +%Y-%m-%d_%H-%M-%S)"
                
                bfile="backups/$bname.tar.gz"
                if [ -e "$bfile" ]; then
                    if ! confirm_action "$force_arg" "Backup '$bname' already exists and will be overwritten"; then
                        echo ""
                        continue
                    fi
                fi
                
                mkdir -p backups
                tar -czf "$bfile" db_manage 2>/dev/null
                printf '%b' "${GREEN}Backup '$bname' created successfully in 'backups/'.${NC}\n"
                echo ""
                ;;
            "backups")
                printf '%b' "${CYAN}${BOLD}Available Backups:${NC}\n"
                python3 -c '
import os, glob
b_dir = "backups"
if not os.path.exists(b_dir):
    print("  (No backups found)")
else:
    files = sorted(glob.glob(os.path.join(b_dir, "*.tar.gz")), key=os.path.getmtime)
    if not files:
        print("  (No backups found)")
    else:
        names = [os.path.basename(f)[:-7] for f in files]
        max_len = max(len(n) for n in names) if names else 10
        max_len = max(max_len, 20)
        title_plain = "BACKUP NAME"
        title_colored = f"\033[1;36m{title_plain:<{max_len}}\033[0m"
        print("┌" + "─" * (max_len + 4) + "┐")
        print(f"│ {title_colored} │")
        print("├" + "─" * (max_len + 4) + "┤")
        for n in names:
            n_padded = f"{n:<{max_len}}"
            print(f"│ {n_padded} │")
        print("└" + "─" * (max_len + 4) + "┘")
'
                echo ""
                ;;
            "backup-restore")
                set -- $args
                bname="$1"
                force_arg="$2"
                if [ -z "$bname" ]; then
                    printf '%b' "${RED}Error: Backup name required. Usage: backup-restore <backup-name> [--force]${NC}\n"
                else
                    bfile="backups/$bname.tar.gz"
                    if [ ! -e "$bfile" ]; then
                        printf '%b' "${RED}Error: Backup '$bname' does not exist.${NC}\n"
                    else
                        if ! confirm_action "$force_arg" "Restore backup '$bname' (this will overwrite current data)"; then
                            echo ""
                            continue
                        fi
                        tar -xzf "$bfile" 2>/dev/null
                        printf '%b' "${GREEN}Backup '$bname' restored successfully.${NC}\n"
                    fi
                fi
                echo ""
                ;;
            "backup_auto")
                set -- $args
                status="$1"
                val="$2"
                if [ -z "$status" ]; then
                    printf '%b' "${RED}Error: Usage: backup_auto <true/false> <value>${NC}\n"
                elif [ "$status" = "true" ]; then
                    [ -z "$val" ] && val="1h"
                    secs=$(parse_interval "$val")
                    [ -f "db_manage/secrets/backup_auto.pid" ] && kill "$(cat db_manage/secrets/backup_auto.pid)" 2>/dev/null
                    (
                        while true; do
                            sleep "$secs"
                            bname="auto-$(date +%Y-%m-%d_%H-%M-%S)"
                            mkdir -p backups
                            tar -czf "backups/$bname.tar.gz" db_manage 2>/dev/null
                            echo "$(date): Auto backup '$bname' created successfully." >> "db_manage/secrets/backup_auto.log"
                        done
                    ) &
                    echo $! > "db_manage/secrets/backup_auto.pid"
                    printf '%b' "${GREEN}Automatic backup enabled successfully with interval $val.${NC}\n"
                elif [ "$status" = "false" ]; then
                    [ -f "db_manage/secrets/backup_auto.pid" ] && kill "$(cat db_manage/secrets/backup_auto.pid)" 2>/dev/null
                    rm -f "db_manage/secrets/backup_auto.pid"
                    printf '%b' "${GREEN}Automatic backup disabled successfully.${NC}\n"
                else
                    printf '%b' "${RED}Error: First argument must be 'true' or 'false'.${NC}\n"
                fi
                echo ""
                ;;
            "use")
                OLD_IFS="$IFS"
                IFS='&'
                set -- $args
                IFS="$OLD_IFS"
                db_name=$(echo "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                if [ -z "$db_name" ]; then
                    printf '%b' "${RED}Error: Database name required. Usage: use <name>${NC}\n"
                elif [ -d "db_manage/database/$db_name" ] && [ -e "db_manage/database/$db_name/$db_name.db" ]; then
                    CURRENT_DB="$db_name"
                    printf '%b' "${GREEN}Switched to database: $CURRENT_DB${NC}\n"
                else
                    printf '%b' "${RED}Error: Database '$db_name' does not exist.${NC}\n"
                fi
                echo ""
                ;;
            "create_database")
                if [ -z "$args" ]; then
                    printf '%b' "${RED}Error: Database name required. Usage: create_database <name>${NC}\n"
                else
                    OLD_IFS="$IFS"
                    IFS='&'
                    set -- $args
                    IFS="$OLD_IFS"
                    for db in "$@"; do
                        db=$(echo "$db" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                        [ -z "$db" ] && continue
                        if [ -d "db_manage/database/$db" ]; then
                            printf '%b' "${RED}Error: Database '$db' already exists.${NC}\n"
                        else
                            mkdir -p "db_manage/database/$db/tables" "db_manage/database/$db/api/public" "db_manage/database/$db/api/secret"
                            echo "{\"database\": \"$db\", \"tables\": {}}" > "db_manage/database/$db/$db.db"
                            generate_server_script "db_manage/database/$db/api/public/server.py"
                            generate_server_script "db_manage/database/$db/api/secret/server.py"
                            init_permissions_file "db_manage/database/$db/api/public/permissions.cfg"
                            printf '%b' "${GREEN}Database '$db' created successfully.${NC}\n"
                        fi
                    done
                fi
                echo ""
                ;;
            "drop_database")
                if [ -z "$args" ]; then
                    printf '%b' "${RED}Error: Database name required. Usage: drop_database <name>${NC}\n"
                else
                    OLD_IFS="$IFS"
                    IFS='&'
                    set -- $args
                    IFS="$OLD_IFS"
                    for db in "$@"; do
                        db=$(echo "$db" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                        [ -z "$db" ] && continue
                        if [ -d "db_manage/database/$db" ]; then
                            for api_type in public secret; do
                                pid_file="db_manage/database/$db/api/$api_type/api.pid"
                                if [ -f "$pid_file" ]; then
                                    pid=$(cat "$pid_file" 2>/dev/null)
                                    [ -n "$pid" ] && kill "$pid" 2>/dev/null
                                fi
                            done
                            rm -rf "db_manage/database/$db"
                            if [ "$CURRENT_DB" = "$db" ]; then
                                CURRENT_DB="none"
                            fi
                            printf '%b' "${GREEN}Database '$db' dropped successfully.${NC}\n"
                        else
                            printf '%b' "${RED}Error: Database '$db' does not exist.${NC}\n"
                        fi
                    done
                fi
                echo ""
                ;;
            "rename_database")
                OLD_IFS="$IFS"
                IFS='&'
                set -- $args
                IFS="$OLD_IFS"
                old_name="$1"
                new_name="$2"
                if [ -z "$old_name" ] || [ -z "$new_name" ]; then
                    printf '%b' "${RED}Error: Usage: rename_database <name> <newname>${NC}\n"
                elif [ ! -d "db_manage/database/$old_name" ]; then
                    printf '%b' "${RED}Error: Database '$old_name' does not exist.${NC}\n"
                elif [ -d "db_manage/database/$new_name" ]; then
                    printf '%b' "${RED}Error: Database '$new_name' already exists.${NC}\n"
                else
                    mv "db_manage/database/$old_name" "db_manage/database/$new_name"
                    if [ -e "db_manage/database/$new_name/$old_name.db" ]; then
                        mv "db_manage/database/$new_name/$old_name.db" "db_manage/database/$new_name/$new_name.db"
                        python3 -c "import json, os; path='db_manage/database/$new_name/$new_name.db'; data=json.load(open(path)); data['database']='$new_name'; json.dump(data, open(path, 'w'))"
                    fi
                    if [ "$CURRENT_DB" = "$old_name" ]; then
                        CURRENT_DB="$new_name"
                    fi
                    printf '%b' "${GREEN}Database '$old_name' renamed to '$new_name' successfully.${NC}\n"
                fi
                echo ""
                ;;
            "describe")
                if [ -z "$args" ]; then
                    printf '%b' "${RED}Error: Database name required. Usage: describe <name>${NC}\n"
                else
                    OLD_IFS="$IFS"
                    IFS='&'
                    set -- $args
                    IFS="$OLD_IFS"
                    for db in "$@"; do
                        db=$(echo "$db" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                        [ -z "$db" ] && continue
                        if [ -e "db_manage/database/$db/$db.db" ]; then
                            printf '%b' "${CYAN}${BOLD}Database Structure for '$db':${NC}\n"
                            cat "db_manage/database/$db/$db.db"
                            echo ""
                        else
                            printf '%b' "${RED}Error: Database '$db' does not exist.${NC}\n"
                        fi
                    done
                fi
                echo ""
                ;;
            "dump_db")
                if [ "$CURRENT_DB" = "none" ]; then
                    printf '%b' "${RED}Error: No active database. Use 'use <name>' first.${NC}\n"
                else
                    printf '%b' "${CYAN}==================================================${NC}\n"
                    printf '%b' "${CYAN}${BOLD}     UNIVERSAL DATABASE DUMP: $CURRENT_DB${NC}\n"
                    printf '%b' "${CYAN}==================================================${NC}\n"
                    printf '%b' "${YELLOW}[Metadata Header]${NC}\n"
                    if [ -e "db_manage/database/${CURRENT_DB}/${CURRENT_DB}.db" ]; then
                        cat "db_manage/database/${CURRENT_DB}/${CURRENT_DB}.db"
                    fi
                    printf '%b' "\n${YELLOW}[Relational Tables & Data Records]${NC}\n"
                    
                    tbl_dir="db_manage/database/${CURRENT_DB}/tables"
                    if [ -d "$tbl_dir" ]; then
                        for tbl in "$tbl_dir"/*.tbl; do
                            [ -e "$tbl" ] || continue
                            tblname=$(basename "$tbl" .tbl)
                            printf '%b' "\n${CYAN}${BOLD}Table: $tblname${NC}\n"
                            print_professional_table "$tbl"
                        done
                    else
                        printf '%s\n' "  (No tables found)"
                    fi
                    printf '%b' "${CYAN}==================================================${NC}\n"
                fi
                echo ""
                ;;
            "create_table")
                if [ "$CURRENT_DB" = "none" ]; then
                    printf '%b' "${RED}Error: No active database. Use 'use <name>' first.${NC}\n"
                elif [ -z "$args" ]; then
                    printf '%b' "${RED}Error: Table name required. Usage: create_table <name>${NC}\n"
                else
                    OLD_IFS="$IFS"
                    IFS='&'
                    set -- $args
                    IFS="$OLD_IFS"
                    for tbl in "$@"; do
                        tbl=$(echo "$tbl" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                        [ -z "$tbl" ] && continue
                        if [ -e "db_manage/database/${CURRENT_DB}/tables/$tbl.tbl" ]; then
                            printf '%b' "${RED}Error: Table '$tbl' already exists.${NC}\n"
                        else
                            touch "db_manage/database/${CURRENT_DB}/tables/$tbl.tbl"
                            printf '%b' "${GREEN}Table '$tbl' created successfully.${NC}\n"
                        fi
                    done
                fi
                echo ""
                ;;
            "drop_table")
                if [ "$CURRENT_DB" = "none" ]; then
                    printf '%b' "${RED}Error: No active database. Use 'use <name>' first.${NC}\n"
                elif [ -z "$args" ]; then
                    printf '%b' "${RED}Error: Table name required. Usage: drop_table <name>${NC}\n"
                else
                    OLD_IFS="$IFS"
                    IFS='&'
                    set -- $args
                    IFS="$OLD_IFS"
                    for tbl in "$@"; do
                        tbl=$(echo "$tbl" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                        [ -z "$tbl" ] && continue
                        if [ -e "db_manage/database/${CURRENT_DB}/tables/$tbl.tbl" ]; then
                            rm "db_manage/database/${CURRENT_DB}/tables/$tbl.tbl"
                            printf '%b' "${GREEN}Table '$tbl' dropped successfully.${NC}\n"
                        else
                            printf '%b' "${RED}Error: Table '$tbl' does not exist.${NC}\n"
                        fi
                    done
                fi
                echo ""
                ;;
            "rename_table")
                if [ "$CURRENT_DB" = "none" ]; then
                    printf '%b' "${RED}Error: No active database. Use 'use <name>' first.${NC}\n"
                else
                    OLD_IFS="$IFS"
                    IFS='&'
                    set -- $args
                    IFS="$OLD_IFS"
                    old_tbl="$1"
                    new_tbl="$2"
                    if [ -z "$old_tbl" ] || [ -z "$new_tbl" ]; then
                        printf '%b' "${RED}Error: Usage: rename_table <name> <newname>${NC}\n"
                    elif [ ! -e "db_manage/database/${CURRENT_DB}/tables/$old_tbl.tbl" ]; then
                        printf '%b' "${RED}Error: Table '$old_tbl' does not exist.${NC}\n"
                    elif [ -e "db_manage/database/${CURRENT_DB}/tables/$new_tbl.tbl" ]; then
                        printf '%b' "${RED}Error: Table '$new_tbl' already exists.${NC}\n"
                    else
                        mv "db_manage/database/${CURRENT_DB}/tables/$old_tbl.tbl" "db_manage/database/${CURRENT_DB}/tables/$new_tbl.tbl"
                        printf '%b' "${GREEN}Table '$old_tbl' renamed to '$new_tbl' successfully.${NC}\n"
                    fi
                fi
                echo ""
                ;;
            "create_column")
                if [ "$CURRENT_DB" = "none" ]; then
                    printf '%b' "${RED}Error: No active database. Use 'use <name>' first.${NC}\n"
                elif [ -z "$args" ]; then
                    printf '%b' "${RED}Error: Usage: create_column <tbl> <col>${NC}\n"
                else
                    set -- $args
                    tbl_name="$1"
                    shift
                    if [ -z "$tbl_name" ] || [ $# -eq 0 ]; then
                        printf '%b' "${RED}Error: Usage: create_column <tbl> <col>${NC}\n"
                    elif [ ! -e "db_manage/database/${CURRENT_DB}/tables/$tbl_name.tbl" ]; then
                        printf '%b' "${RED}Error: Table '$tbl_name' does not exist.${NC}\n"
                    else
                        tbl_file="db_manage/database/${CURRENT_DB}/tables/$tbl_name.tbl"
                        for col_name in "$@"; do
                            col_name=$(echo "$col_name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                            [ -z "$col_name" ] && continue
                            if [ ! -s "$tbl_file" ]; then
                                echo "$col_name" > "$tbl_file"
                                printf '%b' "${GREEN}Column '$col_name' added to table '$tbl_name'.${NC}\n"
                            else
                                tmp_file="$tbl_file.tmp"
                                rm -f "$tmp_file"
                                first_line=1
                                while IFS= read -r line || [ -n "$line" ]; do
                                    if [ "$first_line" -eq 1 ]; then
                                        echo "$line | $col_name" >> "$tmp_file"
                                        first_line=0
                                    else
                                        echo "$line | " >> "$tmp_file"
                                    fi
                                done < "$tbl_file"
                                mv "$tmp_file" "$tbl_file"
                                printf '%b' "${GREEN}Column '$col_name' added to table '$tbl_name'.${NC}\n"
                            fi
                        done
                    fi
                fi
                echo ""
                ;;
            "show_columns")
                if [ "$CURRENT_DB" = "none" ]; then
                    printf '%b' "${RED}Error: No active database. Use 'use <name>' first.${NC}\n"
                else
                    OLD_IFS="$IFS"
                    IFS='&'
                    set -- $args
                    IFS="$OLD_IFS"
                    tbl_name="$1"
                    if [ -z "$tbl_name" ]; then
                        printf '%b' "${RED}Error: Usage: show_columns <tbl>${NC}\n"
                    elif [ ! -e "db_manage/database/${CURRENT_DB}/tables/$tbl_name.tbl" ]; then
                        printf '%b' "${RED}Error: Table '$tbl_name' does not exist.${NC}\n"
                    else
                        tbl_file="db_manage/database/${CURRENT_DB}/tables/$tbl_name.tbl"
                        if [ ! -s "$tbl_file" ]; then
                            printf '%b' "${RED}Error: Table '$tbl_name' has no columns.${NC}\n"
                        else
                            printf '%b' "${CYAN}${BOLD}Columns in table '$tbl_name':${NC}\n"
                            print_professional_columns "$tbl_file"
                        fi
                    fi
                fi
                echo ""
                ;;
            "rename_column")
                if [ "$CURRENT_DB" = "none" ]; then
                    printf '%b' "${RED}Error: No active database. Use 'use <name>' first.${NC}\n"
                else
                    OLD_IFS="$IFS"
                    IFS='&'
                    set -- $args
                    IFS="$OLD_IFS"
                    tbl_name="$1"
                    old_col="$2"
                    new_col="$3"
                    if [ -z "$tbl_name" ] || [ -z "$old_col" ] || [ -z "$new_col" ]; then
                        printf '%b' "${RED}Error: Usage: rename_column <tbl> <col> <newcol>${NC}\n"
                    elif [ ! -e "db_manage/database/${CURRENT_DB}/tables/$tbl_name.tbl" ]; then
                        printf '%b' "${RED}Error: Table '$tbl_name' does not exist.${NC}\n"
                    else
                        tbl_file="db_manage/database/${CURRENT_DB}/tables/$tbl_name.tbl"
                        header=$(head -n 1 "$tbl_file")
                        found=0
                        new_header=""
                        OLD_IFS2="$IFS"
                        IFS='|'
                        set -- $header
                        IFS="$OLD_IFS2"
                        for col in "$@"; do
                            col=$(echo "$col" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                            if [ "$col" = "$old_col" ]; then
                                col="$new_col"
                                found=1
                            fi
                            if [ -z "$new_header" ]; then
                                new_header="$col"
                            else
                                new_header="$new_header | $col"
                            fi
                        done
                        
                        if [ "$found" -eq 1 ]; then
                            tmp_file="$tbl_file.tmp"
                            echo "$new_header" > "$tmp_file"
                            tail -n +2 "$tbl_file" >> "$tmp_file"
                            mv "$tmp_file" "$tbl_file"
                            printf '%b' "${GREEN}Column '$old_col' renamed to '$new_col'.${NC}\n"
                        else
                            printf '%b' "${RED}Error: Column '$old_col' not found.${NC}\n"
                        fi
                    fi
                fi
                echo ""
                ;;
            "show_databases")
                db_count=0
                if [ -d "db_manage/database" ]; then
                    for db_dir in db_manage/database/*; do
                        [ -d "$db_dir" ] || continue
                        dbname=$(basename "$db_dir")
                        [ -e "$db_dir/$dbname.db" ] && db_count=$(expr "$db_count" + 1)
                    done
                fi

                if [ "$db_count" -eq 0 ]; then
                    printf '%b' "${RED}Error: No databases exist.${NC}\n"
                else
                    printf '%b' "${CYAN}${BOLD}Available databases:${NC}\n"
                    for db_dir in db_manage/database/*; do
                        [ -d "$db_dir" ] || continue
                        dbname=$(basename "$db_dir")
                        [ -e "$db_dir/$dbname.db" ] && printf '%b' "  - ${GREEN}$dbname${NC}\n"
                    done
                fi
                echo ""
                ;;
            "show_tables")
                if [ "$CURRENT_DB" = "none" ]; then
                    printf '%b' "${RED}Error: No active database. Use 'use <name>' first.${NC}\n"
                else
                    OLD_IFS="$IFS"
                    IFS='&'
                    set -- $args
                    IFS="$OLD_IFS"
                    target_tbl="$1"
                    
                    if [ -n "$target_tbl" ]; then
                        target_tbl=$(echo "$target_tbl" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                        tbl_file="db_manage/database/${CURRENT_DB}/tables/$target_tbl.tbl"
                        if [ -e "$tbl_file" ]; then
                            printf '%b' "${CYAN}${BOLD}Complete Table View: '$target_tbl'${NC}\n"
                            print_professional_table "$tbl_file"
                        else
                            printf '%b' "${RED}Error: Table '$target_tbl' does not exist in database '$CURRENT_DB'.${NC}\n"
                        fi
                    else
                        tbl_count=0
                        if [ -d "db_manage/database/${CURRENT_DB}/tables" ]; then
                            for tbl in db_manage/database/${CURRENT_DB}/tables/*.tbl; do
                                [ -e "$tbl" ] && tbl_count=$(expr "$tbl_count" + 1)
                            done
                        fi

                        if [ "$tbl_count" -eq 0 ]; then
                            printf '%b' "${RED}Error: No tables exist in database '$CURRENT_DB'.${NC}\n"
                        else
                            printf '%b' "${CYAN}${BOLD}Tables in database '$CURRENT_DB':${NC}\n"
                            python3 -c '
import glob, os, sys
db = sys.argv[1]
tbls = [os.path.basename(f)[:-4] for f in glob.glob(f"db_manage/database/{db}/tables/*.tbl")]
max_len = max(len(t) for t in tbls) if tbls else 10
max_len = max(max_len, 15)
title_plain = "TABLES"
title_colored = f"\033[1;36m{title_plain:<{max_len}}\033[0m"
print("┌" + "─" * (max_len + 4) + "┐")
print(f"│ {title_colored} │")
print("├" + "─" * (max_len + 4) + "┤")
for t in tbls:
    t_padded = f"{t:<{max_len}}"
    print(f"│ {t_padded} │")
print("└" + "─" * (max_len + 4) + "┘")
' "$CURRENT_DB"
                        fi
                    fi
                fi
                echo ""
                ;;
            "insert_into")
                if [ "$CURRENT_DB" = "none" ]; then
                    printf '%b' "${RED}Error: No active database. Use 'use <name>' first.${NC}\n"
                else
                    OLD_IFS="$IFS"
                    IFS='&'
                    set -- $args
                    IFS="$OLD_IFS"
                    
                    for item in "$@"; do
                        item=$(echo "$item" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                        [ -z "$item" ] && continue
                        
                        set -- $item
                        tblname="$1"
                        shift
                        param1="$1"
                        shift
                        rest_params="$*"
                        
                        if [ -z "$tblname" ]; then
                            printf '%b' "${RED}Error: Table name required.${NC}\n"
                            continue
                        fi
                        
                        tbl_file="db_manage/database/${CURRENT_DB}/tables/$tblname.tbl"
                        if [ ! -e "$tbl_file" ]; then
                            printf '%b' "${RED}Error: Table '$tblname' does not exist.${NC}\n"
                            continue
                        fi
                        
                        if [ -n "$rest_params" ]; then
                            col_name="$param1"
                            val="$rest_params"
                            header=$(head -n 1 "$tbl_file")
                            col_idx=-1
                            curr_idx=1
                            OLD_IFS2="$IFS"
                            IFS='|'
                            set -- $header
                            IFS="$OLD_IFS2"
                            for col in "$@"; do
                                col=$(echo "$col" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                                if [ "$col" = "$col_name" ]; then
                                    col_idx="$curr_idx"
                                    break
                                fi
                                curr_idx=$(expr "$curr_idx" + 1)
                            done
                            
                            if [ "$col_idx" -eq -1 ]; then
                                printf '%b' "${RED}Error: Column '$col_name' does not exist.${NC}\n"
                            else
                                total_cols=1
                                if [ -s "$tbl_file" ]; then
                                    total_cols=$(head -n 1 "$tbl_file" | awk -F'|' '{print NF}')
                                fi
                                new_row=""
                                i=1
                                while [ "$i" -le "$total_cols" ]; do
                                    cell=""
                                    [ "$i" -eq "$col_idx" ] && cell="$val"
                                    if [ -z "$new_row" ]; then
                                        new_row="$cell"
                                    else
                                        new_row="$new_row | $cell"
                                    fi
                                    i=$(expr "$i" + 1)
                                done
                                echo "$new_row" >> "$tbl_file"
                                printf '%b' "${GREEN}Data inserted into column '$col_name' of '$tblname'.${NC}\n"
                            fi
                        else
                            data="$param1"
                            if [ -z "$data" ]; then
                                printf '%b' "${RED}Error: Data required.${NC}\n"
                            else
                                echo "$data" >> "$tbl_file"
                                printf '%b' "${GREEN}Data inserted into '$tblname'.${NC}\n"
                            fi
                        fi
                    done
                fi
                echo ""
                ;;
            "select_from")
                if [ "$CURRENT_DB" = "none" ]; then
                    printf '%b' "${RED}Error: No active database. Use 'use <name>' first.${NC}\n"
                elif [ -z "$args" ]; then
                    printf '%b' "${RED}Error: Table name required. Usage: select_from <table_name>${NC}\n"
                else
                    OLD_IFS="$IFS"
                    IFS='&'
                    set -- $args
                    IFS="$OLD_IFS"
                    for tbl in "$@"; do
                        tbl=$(echo "$tbl" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                        [ -z "$tbl" ] && continue
                        tbl_file="db_manage/database/${CURRENT_DB}/tables/$tbl.tbl"
                        if [ -e "$tbl_file" ]; then
                            printf '%b' "${CYAN}${BOLD}Records from table '$tbl':${NC}\n"
                            print_professional_table "$tbl_file"
                        else
                            printf '%b' "${RED}Error: Table '$tbl' does not exist.${NC}\n"
                        fi
                    done
                fi
                echo ""
                ;;
            "update")
                if [ "$CURRENT_DB" = "none" ]; then
                    printf '%b' "${RED}Error: No active database. Use 'use <name>' first.${NC}\n"
                else
                    OLD_IFS="$IFS"
                    IFS='&'
                    set -- $args
                    IFS="$OLD_IFS"
                    tbl_name="$1"
                    col_name="$2"
                    content="$3"
                    newcontent="$4"
                    if [ -z "$tbl_name" ] || [ -z "$col_name" ] || [ -z "$content" ] || [ -z "$newcontent" ]; then
                        printf '%b' "${RED}Error: Usage: update <tbl> <col> <content> <newcontent>${NC}\n"
                    elif [ ! -e "db_manage/database/${CURRENT_DB}/tables/$tbl_name.tbl" ]; then
                        printf '%b' "${RED}Error: Table '$tbl_name' does not exist.${NC}\n"
                    else
                        tbl_file="db_manage/database/${CURRENT_DB}/tables/$tbl_name.tbl"
                        header=$(head -n 1 "$tbl_file")
                        col_idx=-1
                        curr_idx=1
                        OLD_IFS2="$IFS"
                        IFS='|'
                        set -- $header
                        IFS="$OLD_IFS2"
                        for col in "$@"; do
                            col=$(echo "$col" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                            if [ "$col" = "$col_name" ]; then
                                col_idx="$curr_idx"
                                break
                            fi
                            curr_idx=$(expr "$curr_idx" + 1)
                        done
                        
                        if [ "$col_idx" -eq -1 ]; then
                            printf '%b' "${RED}Error: Column '$col_name' does not exist.${NC}\n"
                        else
                            tmp_file="$tbl_file.tmp"
                            updated_count=0
                            first_line=1
                            while IFS= read -r line || [ -n "$line" ]; do
                                if [ "$first_line" -eq 1 ]; then
                                    echo "$line" > "$tmp_file"
                                    first_line=0
                                else
                                    row_line="$line"
                                    row_idx=1
                                    new_row=""
                                    OLD_IFS2="$IFS"
                                    IFS='|'
                                    set -- $row_line
                                    IFS="$OLD_IFS2"
                                    for val in "$@"; do
                                        val_trimmed=$(echo "$val" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                                        if [ "$row_idx" -eq "$col_idx" ] && [ "$val_trimmed" = "$content" ]; then
                                            val=" $newcontent "
                                            updated_count=$(expr "$updated_count" + 1)
                                        fi
                                        if [ -z "$new_row" ]; then
                                            new_row="$val"
                                        else
                                            new_row="$new_row | $val"
                                        fi
                                        row_idx=$(expr "$row_idx" + 1)
                                    done
                                    echo "$new_row" >> "$tmp_file"
                                fi
                            done < "$tbl_file"
                            mv "$tmp_file" "$tbl_file"
                            printf '%b' "${GREEN}Updated $updated_count record(s).${NC}\n"
                        fi
                    fi
                fi
                echo ""
                ;;
            "delete_from")
                if [ "$CURRENT_DB" = "none" ]; then
                    printf '%b' "${RED}Error: No active database. Use 'use <name>' first.${NC}\n"
                elif [ -z "$args" ]; then
                    printf '%b' "${RED}Error: Table name required. Usage: delete_from <tbl>${NC}\n"
                else
                    OLD_IFS="$IFS"
                    IFS='&'
                    set -- $args
                    IFS="$OLD_IFS"
                    for tbl in "$@"; do
                        tbl=$(echo "$tbl" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                        [ -z "$tbl" ] && continue
                        tbl_file="db_manage/database/${CURRENT_DB}/tables/$tbl.tbl"
                        if [ -e "$tbl_file" ]; then
                            header=$(head -n 1 "$tbl_file")
                            echo "$header" > "$tbl_file"
                            printf '%b' "${GREEN}All records deleted from table '$tbl'.${NC}\n"
                        else
                            printf '%b' "${RED}Error: Table '$tbl' does not exist.${NC}\n"
                        fi
                    done
                fi
                echo ""
                ;;
            "delete_record")
                if [ "$CURRENT_DB" = "none" ]; then
                    printf '%b' "${RED}Error: No active database. Use 'use <name>' first.${NC}\n"
                else
                    OLD_IFS="$IFS"
                    IFS='&'
                    set -- $args
                    IFS="$OLD_IFS"
                    
                    for item in "$@"; do
                        item=$(echo "$item" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                        [ -z "$item" ] && continue
                        
                        set -- $item
                        tblname="$1"
                        shift
                        param1="$1"
                        shift
                        rest_params="$*"
                        
                        if [ -z "$tblname" ]; then
                            printf '%b' "${RED}Error: Table name required.${NC}\n"
                            continue
                        fi
                        
                        tbl_file="db_manage/database/${CURRENT_DB}/tables/$tblname.tbl"
                        if [ ! -e "$tbl_file" ]; then
                            printf '%b' "${RED}Error: Table '$tblname' does not exist.${NC}\n"
                            continue
                        fi
                        
                        if [ -n "$rest_params" ]; then
                            col_name="$param1"
                            target_val="$rest_params"
                            header=$(head -n 1 "$tbl_file")
                            col_idx=-1
                            curr_idx=1
                            OLD_IFS2="$IFS"
                            IFS='|'
                            set -- $header
                            IFS="$OLD_IFS2"
                            for col in "$@"; do
                                col=$(echo "$col" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                                if [ "$col" = "$col_name" ]; then
                                    col_idx="$curr_idx"
                                    break
                                fi
                                curr_idx=$(expr "$curr_idx" + 1)
                            done
                            
                            if [ "$col_idx" -eq -1 ]; then
                                printf '%b' "${RED}Error: Column '$col_name' does not exist.${NC}\n"
                            else
                                tmp_file="$tbl_file.tmp"
                                found=0
                                first=1
                                while IFS= read -r row || [ -n "$row" ]; do
                                    if [ "$first" -eq 1 ]; then
                                        echo "$row" > "$tmp_file"
                                        first=0
                                        continue
                                    fi
                                    row_idx=1
                                    match=0
                                    OLD_IFS2="$IFS"
                                    IFS='|'
                                    set -- $row
                                    IFS="$OLD_IFS2"
                                    for val in "$@"; do
                                        val_trimmed=$(echo "$val" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                                        if [ "$row_idx" -eq "$col_idx" ] && [ "$val_trimmed" = "$target_val" ]; then
                                            match=1
                                            break
                                        fi
                                        row_idx=$(expr "$row_idx" + 1)
                                    done
                                    
                                    if [ "$match" -eq 1 ]; then
                                        found=1
                                    else
                                        echo "$row" >> "$tmp_file"
                                    fi
                                done < "$tbl_file"
                                
                                [ -f "$tmp_file" ] && mv "$tmp_file" "$tbl_file"
                                
                                if [ "$found" -eq 1 ]; then
                                    printf '%b' "${GREEN}Record where '$col_name' = '$target_val' deleted successfully.${NC}\n"
                                else
                                    printf '%b' "${RED}Error: Record not found in column '$col_name'.${NC}\n"
                                fi
                            fi
                        else
                            target="$param1"
                            if [ -z "$target" ]; then
                                printf '%b' "${RED}Error: Value required.${NC}\n"
                            else
                                tmp_file="$tbl_file.tmp"
                                found=0
                                first=1
                                while IFS= read -r row || [ -n "$row" ]; do
                                    if [ "$first" -eq 1 ]; then
                                        echo "$row" > "$tmp_file"
                                        first=0
                                        continue
                                    fi
                                    if [ "$row" = "$target" ]; then
                                        found=1
                                    else
                                        echo "$row" >> "$tmp_file"
                                    fi
                                done < "$tbl_file"
                                
                                [ -f "$tmp_file" ] && mv "$tmp_file" "$tbl_file"

                                if [ "$found" -eq 1 ]; then
                                    printf '%b' "${GREEN}Record '$target' deleted successfully.${NC}\n"
                                else
                                    printf '%b' "${RED}Error: Record '$target' not found.${NC}\n"
                                fi
                            fi
                        fi
                    done
                fi
                echo ""
                ;;
            "api_permissions")
                if [ "$CURRENT_DB" = "none" ]; then
                    printf '%b' "${RED}Error: No active database. Use 'use <name>' first.${NC}\n"
                else
                    perm_file="db_manage/database/${CURRENT_DB}/api/public/permissions.cfg"
                    init_permissions_file "$perm_file"

                    set -- $args
                    p_name="$1"
                    p_val="$2"

                    if [ -z "$p_name" ]; then
                        printf '%b' "${CYAN}${BOLD}Public API Permissions for '$CURRENT_DB':${NC}\n"
                        while IFS='=' read -r k v || [ -n "$k" ]; do
                            [ -n "$k" ] && printf '%b' "  - ${CYAN}$k${NC}: ${YELLOW}$v${NC}\n"
                        done < "$perm_file"
                    elif [ -n "$p_name" ] && [ -z "$p_val" ]; then
                        printf '%b' "${RED}Error: Missing permission value. Usage: api_permissions <permission_name> <true|false>${NC}\n"
                    elif [ "$p_val" != "true" ] && [ "$p_val" != "false" ]; then
                        printf '%b' "${RED}Error: Invalid value '$p_val'. Permission value must be explicitly set to 'true' or 'false'.${NC}\n"
                    else
                        temp_f="$perm_file.tmp"
                        found_p=0
                        while IFS='=' read -r k v || [ -n "$k" ]; do
                            if [ "$k" = "$p_name" ]; then
                                echo "$k=$p_val" >> "$temp_f"
                                found_p=1
                            else
                                [ -n "$k" ] && echo "$k=$v" >> "$temp_f"
                            fi
                        done < "$perm_file"
                        mv "$temp_f" "$perm_file"

                        if [ "$found_p" -eq 1 ]; then
                            printf '%b' "${GREEN}Permission '$p_name' updated successfully to '$p_val'.${NC}\n"
                        else
                            printf '%b' "${RED}Error: Permission '$p_name' does not exist in the configuration file.${NC}\n"
                        fi
                    fi
                fi
                echo ""
                ;;
            "api_key_list")
                printf '%b' "${CYAN}${BOLD}Configured API Secret Keys:${NC}\n"
                has_keys=0
                if [ -f "db_manage/secrets/database.cfg" ]; then
                    while IFS='=' read -r k v || [ -n "$k" ]; do
                        case "$k" in
                            secret_key*)
                                printf '%b' "  - ${CYAN}$k${NC}: $v\n"
                                has_keys=1
                                ;;
                        esac
                    done < "db_manage/secrets/database.cfg"
                fi
                if [ "$has_keys" -eq 0 ]; then
                    printf '%b' "  (No secret keys found)\n"
                fi
                echo ""
                ;;
            "api_setup")
                if [ "$CURRENT_DB" = "none" ]; then
                    printf '%b' "${RED}Error: No active database. Use 'use <name>' first.${NC}\n"
                else
                    OLD_IFS="$IFS"
                    IFS='&'
                    set -- $args
                    IFS="$OLD_IFS"
                    api_type="$1"
                    [ -z "$api_type" ] && api_type="public"
                    if [ "$api_type" != "public" ] && [ "$api_type" != "secret" ]; then
                        printf '%b' "${RED}Error: Invalid API type.${NC}\n"
                        echo ""
                        continue
                    fi
                    api_type_upper=$(echo "$api_type" | tr '[:lower:]' '[:upper:]')

                    show_banner
                    printf '%b' "${CYAN}${BOLD}==================================================${NC}\n"
                    printf '%b' "${CYAN}${BOLD}      API SETUP (${api_type_upper}) FOR: $CURRENT_DB      ${NC}\n"
                    printf '%b' "${CYAN}${BOLD}==================================================${NC}\n\n"
                    
                    printf '%b' "Enter API Name: "
                    read -r api_name
                    printf '%b' "Enter Protocol (http or https) [http]: "
                    read -r api_protocol
                    [ -z "$api_protocol" ] && api_protocol="http"
                    printf '%b' "Enter API Address: "
                    read -r api_address
                    printf '%b' "Enter API Port: "
                    read -r api_port

                    printf '%b' "\n${YELLOW}Available Secret Keys:${NC}\n"
                    has_k=0
                    if [ -f "db_manage/secrets/database.cfg" ]; then
                        while IFS='=' read -r k v || [ -n "$k" ]; do
                            case "$k" in
                                secret_key*)
                                    printf '%b' "  - ${CYAN}$k${NC}: $v\n"
                                    has_k=1
                                    ;;
                            esac
                        done < "db_manage/secrets/database.cfg"
                    fi
                    if [ "$has_k" -eq 0 ]; then
                        printf '%b' "  (No secret keys found)\n"
                    fi

                    printf '%b' "\nEnter Secret Key to use [default_secret]: "
                    read -r resolved_secret
                    [ -z "$resolved_secret" ] && resolved_secret="default_secret"

                    api_dir="db_manage/database/${CURRENT_DB}/api/$api_type"
                    mkdir -p "$api_dir"
                    
                    cat << EOF > "$api_dir/api.cfg"
Name=$api_name
Protocol=$api_protocol
Address=$api_address
Port=$api_port
SecretKey=$resolved_secret
EOF
                    generate_server_script "$api_dir/server.py"
                    [ "$api_type" = "public" ] && init_permissions_file "$api_dir/permissions.cfg"
                    printf '%b' "\n${GREEN}API setup completed successfully.${NC}\n"
                fi
                echo ""
                ;;
            "api_edit")
                if [ "$CURRENT_DB" = "none" ]; then
                    printf '%b' "${RED}Error: No active database. Use 'use <name>' first.${NC}\n"
                else
                    OLD_IFS="$IFS"
                    IFS='&'
                    set -- $args
                    IFS="$OLD_IFS"
                    api_type="$1"
                    [ -z "$api_type" ] && api_type="public"
                    if [ "$api_type" != "public" ] && [ "$api_type" != "secret" ]; then
                        printf '%b' "${RED}Error: Invalid API type.${NC}\n"
                        echo ""
                        continue
                    fi

                    api_dir="db_manage/database/${CURRENT_DB}/api/$api_type"
                    api_cfg="$api_dir/api.cfg"

                    curr_name=""
                    curr_proto="http"
                    curr_addr=""
                    curr_port=""
                    curr_secret="default_secret"
                    if [ -f "$api_cfg" ]; then
                        while IFS='=' read -r key val || [ -n "$key" ]; do
                            case "$key" in
                                Name) curr_name="$val" ;;
                                Protocol) curr_proto="$val" ;;
                                Address) curr_addr="$val" ;;
                                Port) curr_port="$val" ;;
                                SecretKey) curr_secret="$val" ;;
                            esac
                        done < "$api_cfg"
                    fi

                    show_banner
                    printf '%b' "Enter new Name [$curr_name]: "
                    read -r new_name
                    [ -n "$new_name" ] && curr_name="$new_name"

                    printf '%b' "Enter new Protocol [$curr_proto]: "
                    read -r new_proto
                    [ -n "$new_proto" ] && curr_proto="$new_proto"

                    printf '%b' "Enter new Address [$curr_addr]: "
                    read -r new_addr
                    [ -n "$new_addr" ] && curr_addr="$new_addr"

                    printf '%b' "Enter new Port [$curr_port]: "
                    read -r new_port
                    [ -n "$new_port" ] && curr_port="$new_port"

                    printf '%b' "\n${YELLOW}Available Secret Keys:${NC}\n"
                    has_k=0
                    if [ -f "db_manage/secrets/database.cfg" ]; then
                        while IFS='=' read -r k v || [ -n "$k" ]; do
                            case "$k" in
                                secret_key*)
                                    printf '%b' "  - ${CYAN}$k${NC}: $v\n"
                                    has_k=1
                                    ;;
                            esac
                        done < "db_manage/secrets/database.cfg"
                    fi
                    if [ "$has_k" -eq 0 ]; then
                        printf '%b' "  (No secret keys found)\n"
                    fi

                    printf '%b' "\nEnter new Secret Key [$curr_secret]: "
                    read -r new_secret
                    [ -n "$new_secret" ] && curr_secret="$new_secret"

                    mkdir -p "$api_dir"
                    cat << EOF > "$api_cfg"
Name=$curr_name
Protocol=$curr_proto
Address=$curr_addr
Port=$curr_port
SecretKey=$curr_secret
EOF
                    generate_server_script "$api_dir/server.py"
                    [ "$api_type" = "public" ] && init_permissions_file "$api_dir/permissions.cfg"
                    printf '%b' "\n${GREEN}API configuration updated successfully!${NC}\n"
                fi
                echo ""
                ;;
            "api_start")
                if [ "$CURRENT_DB" = "none" ]; then
                    printf '%b' "${RED}Error: No active database. Use 'use <name>' first.${NC}\n"
                else
                    OLD_IFS="$IFS"
                    IFS='&'
                    set -- $args
                    IFS="$OLD_IFS"
                    api_type="$1"
                    [ -z "$api_type" ] && api_type="public"
                    if [ "$api_type" != "public" ] && [ "$api_type" != "secret" ]; then
                        printf '%b' "${RED}Error: Invalid API type.${NC}\n"
                        echo ""
                        continue
                    fi

                    api_dir="db_manage/database/${CURRENT_DB}/api/$api_type"
                    api_cfg="$api_dir/api.cfg"
                    pid_file="$api_dir/api.pid"
                    server_script="$api_dir/server.py"

                    if [ ! -f "$api_cfg" ]; then
                        printf '%b' "${RED}Error: API is not configured.${NC}\n"
                    elif [ -f "$pid_file" ] && kill -0 "$(cat "$pid_file" 2>/dev/null)" 2>/dev/null; then
                        printf '%b' "${YELLOW}API is already running.${NC}\n"
                    else
                        [ ! -f "$server_script" ] && generate_server_script "$server_script"
                        [ "$api_type" = "public" ] && init_permissions_file "$api_dir/permissions.cfg"

                        api_name_val=$(grep "^Name=" "$api_cfg" 2>/dev/null | cut -d'=' -f2)
                        api_proto_val=$(grep "^Protocol=" "$api_cfg" 2>/dev/null | cut -d'=' -f2)
                        api_port_val=$(grep "^Port=" "$api_cfg" 2>/dev/null | cut -d'=' -f2)
                        api_secret_val=$(grep "^SecretKey=" "$api_cfg" 2>/dev/null | cut -d'=' -f2)
                        
                        proto="${api_proto_val:-http}"
                        port="${api_port_val:-8080}"

                        cert_arg=""
                        key_arg=""
                        if [ "$proto" = "https" ]; then
                            if [ ! -f "$api_dir/server.pem" ]; then
                                openssl req -x509 -newkey rsa:2048 -keyout "$api_dir/server.key" -out "$api_dir/server.crt" -days 365 -nodes -subj "/CN=localhost" 2>/dev/null
                                cat "$api_dir/server.crt" "$api_dir/server.key" > "$api_dir/server.pem"
                            fi
                            cert_arg="$api_dir/server.pem"
                            key_arg="$api_dir/server.key"
                        fi

                        API_PORT="$port" API_SECRET="${api_secret_val:-default_secret}" DB_NAME="$CURRENT_DB" API_PROTOCOL="$proto" API_TYPE="$api_type" API_CERT="$cert_arg" API_KEY="$key_arg" python3 "$server_script" > "$api_dir/server.log" 2>&1 &
                        server_pid=$!
                        echo "$server_pid" > "$pid_file"

                        printf '%b' "${GREEN}API server started successfully on port ${port} (PID: ${server_pid})!${NC}\n"
                    fi
                fi
                echo ""
                ;;
            "api_stop")
                if [ "$CURRENT_DB" = "none" ]; then
                    printf '%b' "${RED}Error: No active database. Use 'use <name>' first.${NC}\n"
                else
                    OLD_IFS="$IFS"
                    IFS='&'
                    set -- $args
                    IFS="$OLD_IFS"
                    api_type="$1"
                    shift
                    [ -z "$api_type" ] && api_type="public"
                    
                    api_dir="db_manage/database/${CURRENT_DB}/api/$api_type"
                    pid_file="$api_dir/api.pid"

                    if [ ! -f "$pid_file" ]; then
                        printf '%b' "${YELLOW}API is not currently running.${NC}\n"
                    else
                        pid=$(cat "$pid_file" 2>/dev/null)
                        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
                            kill "$pid" 2>/dev/null || kill -9 "$pid" 2>/dev/null
                        fi
                        rm -f "$pid_file"
                        printf '%b' "${GREEN}API server stopped successfully.${NC}\n"
                    fi
                fi
                echo ""
                ;;
            "api_delete")
                if [ "$CURRENT_DB" = "none" ]; then
                    printf '%b' "${RED}Error: No active database. Use 'use <name>' first.${NC}\n"
                else
                    OLD_IFS="$IFS"
                    IFS='&'
                    set -- $args
                    IFS="$OLD_IFS"
                    api_type="$1"
                    [ -z "$api_type" ] && api_type="public"

                    api_dir="db_manage/database/${CURRENT_DB}/api/$api_type"
                    pid_file="$api_dir/api.pid"

                    if [ -d "$api_dir" ]; then
                        if [ -f "$pid_file" ]; then
                            pid=$(cat "$pid_file" 2>/dev/null)
                            [ -n "$pid" ] && kill "$pid" 2>/dev/null
                        fi
                        rm -rf "$api_dir"
                        printf '%b' "${GREEN}API configuration deleted successfully.${NC}\n"
                    else
                        printf '%b' "${YELLOW}API configuration does not exist.${NC}\n"
                    fi
                fi
                echo ""
                ;;
            "api_status")
                if [ "$CURRENT_DB" = "none" ]; then
                    printf '%b' "${RED}Error: No active database. Use 'use <name>' first.${NC}\n"
                else
                    OLD_IFS="$IFS"
                    IFS='&'
                    set -- $args
                    IFS="$OLD_IFS"
                    api_type="$1"
                    [ -z "$api_type" ] && api_type="public"

                    api_dir="db_manage/database/${CURRENT_DB}/api/$api_type"
                    api_cfg="$api_dir/api.cfg"
                    pid_file="$api_dir/api.pid"

                    if [ ! -f "$api_cfg" ]; then
                        printf '%b' "${RED}Error: API is not configured.${NC}\n"
                    else
                        api_name_val=$(grep "^Name=" "$api_cfg" 2>/dev/null | cut -d'=' -f2)
                        api_proto_val=$(grep "^Protocol=" "$api_cfg" 2>/dev/null | cut -d'=' -f2)
                        api_addr_val=$(grep "^Address=" "$api_cfg" 2>/dev/null | cut -d'=' -f2)
                        api_port_val=$(grep "^Port=" "$api_cfg" 2>/dev/null | cut -d'=' -f2)
                        api_type_upper=$(echo "$api_type" | tr '[:lower:]' '[:upper:]')
                        
                        printf '%b' "${CYAN}==================================================${NC}\n"
                        printf '%b' "${CYAN}${BOLD}     API STATUS: ${api_name_val:-$CURRENT_DB}       ${NC}\n"
                        printf '%b' "${CYAN}==================================================${NC}\n"
                        printf '%b' " Database: ${GREEN}$CURRENT_DB${NC}\n"
                        printf '%b' " Type:     ${BLUE}$api_type_upper${NC}\n"
                        printf '%b' " Protocol: ${YELLOW}${api_proto_val:-http}${NC}\n"
                        printf '%b' " Address:  ${CYAN}${api_addr_val:-localhost}${NC}\n"
                        printf '%b' " Port:     ${CYAN}${api_port_val:-8080}${NC}\n"
                        
                        is_running=0
                        if [ -f "$pid_file" ]; then
                            pid=$(cat "$pid_file" 2>/dev/null)
                            if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
                                is_running=1
                                printf '%b' " Status:   ${GREEN}RUNNING${NC} (PID: ${pid})\n"
                            else
                                rm -f "$pid_file"
                            fi
                        fi
                        [ "$is_running" -eq 0 ] && printf '%b' " Status:   ${RED}STOPPED${NC}\n"
                        printf '%b' "${CYAN}==================================================${NC}\n"
                    fi
                fi
                echo ""
                ;;
            "api_request")
                if [ "$CURRENT_DB" = "none" ]; then
                    printf '%b' "${RED}Error: No active database. Use 'use <name>' first.${NC}\n"
                elif [ -z "$args" ]; then
                    printf '%b' "${RED}Error: Command required.${NC}\n"
                else
                    OLD_IFS="$IFS"
                    IFS='&'
                    set -- $args
                    IFS="$OLD_IFS"
                    api_type="$1"
                    if [ "$api_type" = "public" ] || [ "$api_type" = "secret" ]; then
                        shift
                    else
                        api_type="public"
                    fi

                    api_dir="db_manage/database/${CURRENT_DB}/api/$api_type"
                    api_cfg="$api_dir/api.cfg"
                    pid_file="$api_dir/api.pid"

                    if [ ! -f "$api_cfg" ]; then
                        printf '%b' "${RED}Error: API is not configured.${NC}\n"
                    elif [ ! -f "$pid_file" ] || ! kill -0 "$(cat "$pid_file" 2>/dev/null)" 2>/dev/null; then
                        printf '%b' "${RED}Error: API server is not running.${NC}\n"
                    else
                        api_proto_val=$(grep "^Protocol=" "$api_cfg" 2>/dev/null | cut -d'=' -f2)
                        api_addr_val=$(grep "^Address=" "$api_cfg" 2>/dev/null | cut -d'=' -f2)
                        api_port_val=$(grep "^Port=" "$api_cfg" 2>/dev/null | cut -d'=' -f2)
                        api_secret_val=$(grep "^SecretKey=" "$api_cfg" 2>/dev/null | cut -d'=' -f2)
                        
                        proto="${api_proto_val:-http}"
                        addr="${api_addr_val:-localhost}"
                        port="${api_port_val:-8080}"
                        
                        sub_cmd="$1"
                        shift
                        sub_args="$*"
                        
                        endpoint="/$sub_cmd"
                        [ -n "$sub_args" ] && endpoint="/$sub_cmd/$sub_args"
                        url="$proto://$addr:$port$endpoint"
                        
                        if command -v curl >/dev/null 2>&1; then
                            curl_opts="-s"
                            [ "$proto" = "https" ] && curl_opts="-s -k"
                            if [ "$api_type" = "secret" ]; then
                                curl $curl_opts -H "X-Secret-Key: $api_secret_val" "$url"
                            else
                                curl $curl_opts "$url"
                            fi
                            echo ""
                        else
                            printf '%b' "${RED}Error: 'curl' is required.${NC}\n"
                        fi
                    fi
                fi
                echo ""
                ;;
            "api_key_add")
                OLD_IFS="$IFS"
                IFS='&'
                set -- $args
                IFS="$OLD_IFS"
                key_val="$1"
                if [ -z "$key_val" ]; then
                    printf '%b' "${RED}Error: Key required.${NC}\n"
                else
                    count=0
                    if [ -f "db_manage/secrets/database.cfg" ]; then
                        raw_count=$(grep -c "^secret_key[0-9]" "db_manage/secrets/database.cfg" 2>/dev/null)
                        [ -n "$raw_count" ] && count="$raw_count"
                    fi
                    next_idx=$(expr "$count" + 1)
                    echo "secret_key$next_idx=$key_val" >> "db_manage/secrets/database.cfg"
                    printf '%b' "${GREEN}Secret key added successfully as secret_key$next_idx.${NC}\n"
                fi
                echo ""
                ;;
            "api_key_remove")
                OLD_IFS="$IFS"
                IFS='&'
                set -- $args
                IFS="$OLD_IFS"
                key_val="$1"
                if [ -z "$key_val" ]; then
                    printf '%b' "${RED}Error: Key required.${NC}\n"
                else
                    if [ -f "db_manage/secrets/database.cfg" ]; then
                        temp_file="db_manage/secrets/database.cfg.tmp"
                        touch "$temp_file"
                        found=0
                        i=1
                        while IFS= read -r line || [ -n "$line" ]; do
                            case "$line" in
                                secret_key[0-9]*=*)
                                    val=$(echo "$line" | cut -d'=' -f2)
                                    if [ "$val" = "$key_val" ] || [ "$line" = "$key_val" ]; then
                                        found=1
                                    else
                                        echo "secret_key$i=$val" >> "$temp_file"
                                        i=$(expr "$i" + 1)
                                    fi
                                    ;;
                                *)
                                    [ -n "$line" ] && echo "$line" >> "$temp_file"
                                    ;;
                            esac
                        done < "db_manage/secrets/database.cfg"
                        mv "$temp_file" "db_manage/secrets/database.cfg"
                        if [ "$found" -eq 1 ]; then
                            printf '%b' "${GREEN}Secret key removed successfully.${NC}\n"
                        else
                            printf '%b' "${RED}Error: Key not found.${NC}\n"
                        fi
                    else
                        printf '%b' "${RED}Error: Configuration file does not exist.${NC}\n"
                    fi
                fi
                echo ""
                ;;
            *)
                printf '%b' "${RED}Unknown command: '$command'. Type 'help' for assistance.${NC}\n"
                echo ""
                ;;
        esac
    done
done
