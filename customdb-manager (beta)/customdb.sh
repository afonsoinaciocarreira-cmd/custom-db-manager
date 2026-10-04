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

mkdir -p db_manage/database db_manage/secrets
[ -e "db_manage/secrets/secrets.env" ] || touch "db_manage/secrets/secrets.env"
[ -e "db_manage/secrets/database.cfg" ] || touch "db_manage/secrets/database.cfg"
[ -e "db_manage/secrets/api.cfg" ] || touch "db_manage/secrets/api.cfg"

show_banner() {
    clear
    printf '%b' "${CYAN}==================================================${NC}\n"
    printf '%b' "${BOLD}        CUSTOM DB MANAGER CLI - Version beta     ${NC}\n"
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

PORT = int(os.environ.get("API_PORT", 8080))
SECRET_KEY = os.environ.get("API_SECRET", "default_secret")
DB_NAME = os.environ.get("DB_NAME", "db")
PROTOCOL = os.environ.get("API_PROTOCOL", "http")
CERT_FILE = os.environ.get("API_CERT", "")
KEY_FILE = os.environ.get("API_KEY", "")

DB_BASE_DIR = os.path.join("db_manage", "database")
DB_PATH = os.path.join(DB_BASE_DIR, DB_NAME)
TABLES_DIR = os.path.join(DB_PATH, "tables")

class DBAPIHandler(http.server.BaseHTTPRequestHandler):
    def _check_auth(self):
        client_key = self.headers.get("X-Secret-Key")
        parsed_path = urllib.parse.urlparse(self.path)
        query_params = urllib.parse.parse_qs(parsed_path.query)
        query_key = query_params.get("key", [None])[0]
        
        if client_key == SECRET_KEY or query_key == SECRET_KEY:
            return True
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
        if not self._check_auth():
            self._send_response(401, {"status": "error", "error": "Unauthorized: Invalid or missing X-Secret-Key header or ?key= parameter"})
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
        response_data = {"status": "success", "database": DB_NAME, "method": method, "endpoint": path, "protocol": PROTOCOL}
        status_code = 200

        try:
            os.makedirs(TABLES_DIR, exist_ok=True)

            if path in ["/", "/status"]:
                tables = [f[:-4] for f in os.listdir(TABLES_DIR) if f.endswith(".tbl")] if os.path.exists(TABLES_DIR) else []
                response_data.update({
                    "message": f"Real database API server ({PROTOCOL.upper()}) is running and fully operational.",
                    "tables": tables
                })
                accept_header = self.headers.get("Accept", "")
                if "text/html" in accept_header or path == "/":
                    self._send_html_response(status_code, response_data)
                    return

            elif path == "/show_databases":
                dbs = []
                if os.path.exists(DB_BASE_DIR):
                    for d in os.listdir(DB_BASE_DIR):
                        if os.path.isdir(os.path.join(DB_BASE_DIR, d)) and os.path.exists(os.path.join(DB_BASE_DIR, d, f"{d}.db")):
                            dbs.append(d)
                response_data["databases"] = dbs

            elif path == "/show_tables":
                tables = [f[:-4] for f in os.listdir(TABLES_DIR) if f.endswith(".tbl")] if os.path.exists(TABLES_DIR) else []
                response_data["tables"] = tables

            elif path.startswith("/describe/"):
                target_db = path.split("/")[-1]
                db_file = os.path.join(DB_BASE_DIR, target_db, f"{target_db}.db")
                if not os.path.exists(db_file):
                    status_code = 404
                    raise ValueError(f"Error: Database '{target_db}' does not exist.")
                with open(db_file, "r") as f:
                    content = f.read()
                response_data["target_database"] = target_db
                response_data["structure"] = json.loads(content) if content.startswith("{") else content

            elif path.startswith("/select_from/") or path.startswith("/select/"):
                tbl_name = path.split("/")[-1]
                tbl_file = os.path.join(TABLES_DIR, f"{tbl_name}.tbl")
                if not os.path.exists(tbl_file):
                    status_code = 404
                    raise ValueError(f"Error: Table '{tbl_name}' does not exist in database '{DB_NAME}'.")
                with open(tbl_file, "r") as f:
                    records = [line.strip() for line in f if line.strip()]
                response_data["table"] = tbl_name
                response_data["records"] = records

            elif path.startswith("/insert_into/") or path.startswith("/insert/"):
                tbl_name = path.split("/")[-1]
                tbl_file = os.path.join(TABLES_DIR, f"{tbl_name}.tbl")
                if not os.path.exists(tbl_file):
                    status_code = 404
                    raise ValueError(f"Error: Table '{tbl_name}' does not exist in database '{DB_NAME}'.")
                
                data_to_insert = params.get("data") or params.get("record") or body_data.get("raw_body")
                if not data_to_insert:
                    status_code = 400
                    raise ValueError(f"Error: Missing data to insert. Provide 'data' parameter.")
                
                with open(tbl_file, "a") as f:
                    f.write(str(data_to_insert).strip() + "\n")
                response_data["message"] = f"Data successfully inserted into table '{tbl_name}'."
                response_data["inserted_data"] = str(data_to_insert).strip()

            elif path.startswith("/create_table/"):
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
                tbl_name = path.split("/")[-1]
                tbl_file = os.path.join(TABLES_DIR, f"{tbl_name}.tbl")
                if not os.path.exists(tbl_file):
                    status_code = 404
                    raise ValueError(f"Error: Table '{tbl_name}' does not exist.")
                os.remove(tbl_file)
                response_data["message"] = f"Table '{tbl_name}' dropped successfully."

            elif path.startswith("/delete_from/"):
                tbl_name = path.split("/")[-1]
                tbl_file = os.path.join(TABLES_DIR, f"{tbl_name}.tbl")
                if not os.path.exists(tbl_file):
                    status_code = 404
                    raise ValueError(f"Error: Table '{tbl_name}' does not exist.")
                with open(tbl_file, "w") as f:
                    pass
                response_data["message"] = f"All records deleted from table '{tbl_name}'."

            elif path.startswith("/delete_record/"):
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
                    for line in f_in:
                        if line.strip() == target_val:
                            found = True
                        else:
                            f_out.write(line)
                os.replace(tmp_file, tbl_file)
                
                if found:
                    response_data["message"] = f"Record '{target_val}' deleted from table '{tbl_name}'."
                else:
                    status_code = 404
                    raise ValueError(f"Error: Record '{target_val}' not found in table '{tbl_name}'.")

            else:
                response_data["message"] = f"Endpoint '{path}' reached and executed successfully."

        except Exception as e:
            if status_code == 200:
                status_code = 400
            response_data = {
                "status": "error",
                "database": DB_NAME,
                "endpoint": path,
                "error": str(e)
            }

        self._send_response(status_code, response_data)

    def _send_response(self, code, data):
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
    <title>Database API Dashboard - {DB_NAME} ({PROTOCOL.upper()})</title>
    <style>
        body {{ font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background: #0f172a; color: #f8fafc; margin: 0; padding: 30px; }}
        .container {{ max-width: 850px; margin: 0 auto; background: #1e293b; padding: 40px; border-radius: 12px; box-shadow: 0 8px 30px rgba(0,0,0,0.6); border: 1px solid #334155; }}
        h1 {{ color: #38bdf8; border-bottom: 2px solid #334155; padding-bottom: 12px; margin-top: 0; display: flex; justify-content: space-between; align-items: center; }}
        .badge {{ background: #0284c7; color: white; padding: 6px 14px; border-radius: 20px; font-size: 14px; font-weight: bold; }}
        pre {{ background: #0f172a; padding: 20px; border-radius: 8px; overflow-x: auto; color: #38bdf8; border: 1px solid #334155; font-size: 14px; }}
        ul {{ list-style-type: none; padding: 0; }}
        li {{ background: #334155; margin: 8px 0; padding: 12px 16px; border-radius: 6px; display: flex; align-items: center; font-weight: 500; }}
        .status-box {{ background: #064e3b; border: 1px solid #059669; color: #34d399; padding: 12px 16px; border-radius: 6px; margin-bottom: 20px; font-weight: 600; }}
    </style>
</head>
<body>
    <div class="container">
        <h1>Database Server Dashboard <span>{DB_NAME}</span></h1>
        <div class="status-box">✓ Real API Server ({PROTOCOL.upper()}) is Active & Responding Live</div>
        <p><strong>Protocol:</strong> <code>{PROTOCOL.upper()}</code></p>
        <p><strong>Endpoint:</strong> <code>{data.get('endpoint', '/')}</code></p>
        <p><strong>Method:</strong> <code>{data.get('method', 'GET')}</code></p>
        
        <h3>Active Database Tables:</h3>
        <ul>
            {"".join([f"<li>📁 &nbsp; {t}</li>" for t in data.get('tables', [])]) if data.get('tables') else "<li>(No tables found in this database)</li>"}
        </ul>

        <h3>Real Server Response Output (JSON):</h3>
        <pre>{json.dumps(data, indent=2)}</pre>
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

show_banner

while true; do
    printf '%b' "${CYAN}$HOST${NC}@${BLUE}$CURRENT_DB${NC} -> "
    read -r line
    [ -z "$line" ] && continue

    set -- $line
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
            printf '%b' "   ${CYAN}api_status${NC}               ${GRAY}- Check API server status${NC}\n"
            printf '%b' "   ${CYAN}api_start${NC}                ${GRAY}- Start the real API server (HTTP/HTTPS)${NC}\n"
            printf '%b' "   ${CYAN}api_stop [--force]${NC}       ${GRAY}- Stop the API server${NC}\n"
            printf '%b' "   ${CYAN}api_delete${NC}               ${GRAY}- Delete/remove API files and config${NC}\n"
            printf '%b' "   ${CYAN}api_request <command>${NC}    ${GRAY}- Run ANY CLI command via API endpoint${NC}\n"
            printf '%b' "   ${CYAN}api_setup${NC}                ${GRAY}- Setup API with protocol & secret key${NC}\n"
            printf '%b' "   ${CYAN}api_edit${NC}                 ${GRAY}- Edit API configuration${NC}\n"
            printf '%b' "   ${CYAN}api_key_list${NC}             ${GRAY}- List all configured API secret keys${NC}\n"
            printf '%b' "   ${CYAN}api_key_add <key>${NC}        ${GRAY}- Add a secret key for API access${NC}\n"
            printf '%b' "   ${CYAN}api_key_remove <key>${NC}     ${GRAY}- Remove a secret key${NC}\n\n"
            printf '%b' " ${YELLOW}[ 📂 DATABASE MANAGEMENT ]${NC}\n"
            printf '%b' "   ${CYAN}create_database <name>${NC}   ${GRAY}- Create a new database${NC}\n"
            printf '%b' "   ${CYAN}drop_database <name>${NC}     ${GRAY}- Delete an existing database${NC}\n"
            printf '%b' "   ${CYAN}use <name>${NC}               ${GRAY}- Select/switch active database${NC}\n"
            printf '%b' "   ${CYAN}show_databases${NC}           ${GRAY}- List all databases${NC}\n"
            printf '%b' "   ${CYAN}describe <name>${NC}          ${GRAY}- Show database structure${NC}\n"
            printf '%b' "   ${CYAN}dump_db${NC}                  ${GRAY}- Show full DB in universal grid format${NC}\n\n"
            printf '%b' " ${YELLOW}[ 🗄 TABLE MANAGEMENT ]${NC}\n"
            printf '%b' "   ${CYAN}create_table <name>${NC}      ${GRAY}- Create a new table${NC}\n"
            printf '%b' "   ${CYAN}drop_table <name>${NC}        ${GRAY}- Delete an existing table${NC}\n"
            printf '%b' "   ${CYAN}show_tables${NC}              ${GRAY}- List tables in active database${NC}\n\n"
            printf '%b' " ${YELLOW}[ ⚡ DATA OPERATIONS ]${NC}\n"
            printf '%b' "   ${CYAN}insert_into <tbl> <data>${NC} ${GRAY}- Insert data into a table${NC}\n"
            printf '%b' "   ${CYAN}select_from <tbl>${NC}        ${GRAY}- Query data from a table${NC}\n"
            printf '%b' "   ${CYAN}update <tbl> <data>${NC}      ${GRAY}- Update existing records${NC}\n"
            printf '%b' "   ${CYAN}delete_from <tbl>${NC}        ${GRAY}- Delete all records from a table${NC}\n"
            printf '%b' "   ${CYAN}delete_record <tbl> <val>${NC} ${GRAY}- Delete a specific record from table${NC}\n\n"
            printf '%b' " ${YELLOW}[ 🛠 SYSTEM ]${NC}\n"
            printf '%b' "   ${CYAN}clear${NC}                    ${GRAY}- Clear screen and reload banner${NC}\n"
            printf '%b' "   ${CYAN}help${NC}                     ${GRAY}- Show this help menu${NC}\n"
            printf '%b' "   ${CYAN}exit / quit${NC}              ${GRAY}- Exit the application${NC}\n\n"
            printf '%b' "${CYAN}==================================================${NC}\n\n"
            ;;
        "clear")
            show_banner
            ;;
        "use")
            if [ -z "$args" ]; then
                printf '%b' "${RED}Error: Database name required. Usage: use <name>${NC}\n"
            elif [ -d "db_manage/database/$args" ] && [ -e "db_manage/database/$args/$args.db" ]; then
                CURRENT_DB="$args"
                printf '%b' "${GREEN}Switched to database: $CURRENT_DB${NC}\n"
            else
                printf '%b' "${RED}Error: Database '$args' does not exist.${NC}\n"
            fi
            echo ""
            ;;
        "create_database")
            if [ -z "$args" ]; then
                printf '%b' "${RED}Error: Database name required. Usage: create_database <name>${NC}\n"
            elif [ -d "db_manage/database/$args" ]; then
                printf '%b' "${RED}Error: Database '$args' already exists.${NC}\n"
            else
                mkdir -p "db_manage/database/$args/tables" "db_manage/database/$args/api"
                echo "{\"database\": \"$args\", \"tables\": {}}" > "db_manage/database/$args/$args.db"
                generate_server_script "db_manage/database/$args/api/server.py"
                printf '%b' "${GREEN}Database '$args' created successfully with tables and api structures.${NC}\n"
            fi
            echo ""
            ;;
        "drop_database")
            if [ -z "$args" ]; then
                printf '%b' "${RED}Error: Database name required. Usage: drop_database <name>${NC}\n"
            elif [ -d "db_manage/database/$args" ]; then
                pid_file="db_manage/database/$args/api/api.pid"
                if [ -f "$pid_file" ]; then
                    pid=$(cat "$pid_file" 2>/dev/null)
                    [ -n "$pid" ] && kill "$pid" 2>/dev/null
                fi
                rm -rf "db_manage/database/$args"
                if [ "$CURRENT_DB" = "$args" ]; then
                    CURRENT_DB="none"
                fi
                printf '%b' "${GREEN}Database '$args' dropped successfully.${NC}\n"
            else
                printf '%b' "${RED}Error: Database '$args' does not exist.${NC}\n"
            fi
            echo ""
            ;;
        "describe")
            if [ -z "$args" ]; then
                printf '%b' "${RED}Error: Database name required. Usage: describe <name>${NC}\n"
            elif [ -e "db_manage/database/$args/$args.db" ]; then
                printf '%b' "${BOLD}Database Structure for '$args':${NC}\n"
                cat "db_manage/database/$args/$args.db"
                echo ""
            else
                printf '%b' "${RED}Error: Database '$args' does not exist.${NC}\n"
            fi
            echo ""
            ;;
        "dump_db")
            if [ "$CURRENT_DB" = "none" ]; then
                printf '%b' "${RED}Error: No active database. Use 'use <name>' first.${NC}\n"
            else
                printf '%b' "${CYAN}==================================================${NC}\n"
                printf '%b' "${BOLD}     UNIVERSAL DATABASE DUMP: $CURRENT_DB${NC}\n"
                printf '%b' "${CYAN}==================================================${NC}\n"
                printf '%b' "${YELLOW}[Metadata Header]${NC}\n"
                if [ -e "db_manage/database/${CURRENT_DB}/${CURRENT_DB}.db" ]; then
                    cat "db_manage/database/${CURRENT_DB}/${CURRENT_DB}.db"
                fi
                printf '%b' "\n${YELLOW}[Relational Tables & Data Records (Grid Format)]${NC}\n"
                
                tbl_dir="db_manage/database/${CURRENT_DB}/tables"
                if [ -d "$tbl_dir" ]; then
                    headers=""
                    files=""
                    for tbl in "$tbl_dir"/*.tbl; do
                        [ -e "$tbl" ] || continue
                        tblname=$(basename "$tbl" .tbl)
                        if [ -z "$headers" ]; then
                            headers="$tblname"
                            files="$tbl"
                        else
                            headers="$headers | $tblname"
                            files="$files $tbl"
                        fi
                    done

                    if [ -n "$headers" ]; then
                        printf '%b\n' "${BOLD}$headers${NC}"
                        printf '%s\n' "--------------------------------------------------"
                        eval "paste $files" | awk -F'\t' '
                        {
                            line = $1
                            for (i=2; i<=NF; i++) {
                                line = line " | " $i
                            }
                            print line
                        }'
                        printf '%s\n' "--------------------------------------------------"
                    else
                        printf '%s\n' "  (No tables found)"
                    fi
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
            elif [ -e "db_manage/database/${CURRENT_DB}/tables/$args.tbl" ]; then
                printf '%b' "${RED}Error: Table '$args' already exists.${NC}\n"
            else
                touch "db_manage/database/${CURRENT_DB}/tables/$args.tbl"
                printf '%b' "${GREEN}Table '$args' created successfully in database '$CURRENT_DB'.${NC}\n"
            fi
            echo ""
            ;;
        "drop_table")
            if [ "$CURRENT_DB" = "none" ]; then
                printf '%b' "${RED}Error: No active database. Use 'use <name>' first.${NC}\n"
            elif [ -z "$args" ]; then
                printf '%b' "${RED}Error: Table name required. Usage: drop_table <name>${NC}\n"
            elif [ -e "db_manage/database/${CURRENT_DB}/tables/$args.tbl" ]; then
                rm "db_manage/database/${CURRENT_DB}/tables/$args.tbl"
                printf '%b' "${GREEN}Table '$args' dropped successfully from database '$CURRENT_DB'.${NC}\n"
            else
                printf '%b' "${RED}Error: Table '$args' does not exist.${NC}\n"
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
                printf '%b' "${BOLD}Available databases:${NC}\n"
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
                tbl_count=0
                if [ -d "db_manage/database/${CURRENT_DB}/tables" ]; then
                    for tbl in db_manage/database/${CURRENT_DB}/tables/*.tbl; do
                        [ -e "$tbl" ] && tbl_count=$(expr "$tbl_count" + 1)
                    done
                fi

                if [ "$tbl_count" -eq 0 ]; then
                    printf '%b' "${RED}Error: No tables exist in database '$CURRENT_DB'.${NC}\n"
                else
                    printf '%b' "${BOLD}Tables in database '$CURRENT_DB':${NC} "
                    first=1
                    for tbl in db_manage/database/${CURRENT_DB}/tables/*.tbl; do
                        [ -e "$tbl" ] || continue
                        tblname=$(basename "$tbl" .tbl)
                        if [ "$first" -eq 1 ]; then
                            printf '%b' "${GREEN}$tblname${NC}"
                            first=0
                        else
                            printf '%b' " | ${GREEN}$tblname${NC}"
                        fi
                    done
                    echo ""
                fi
            fi
            echo ""
            ;;
        "insert_into")
            if [ "$CURRENT_DB" = "none" ]; then
                printf '%b' "${RED}Error: No active database. Use 'use <name>' first.${NC}\n"
            else
                set -- $args
                tblname="$1"
                shift
                data="$*"
                if [ -z "$tblname" ]; then
                    printf '%b' "${RED}Error: Table name required. Usage: insert_into <table_name> <data>${NC}\n"
                elif [ ! -e "db_manage/database/${CURRENT_DB}/tables/$tblname.tbl" ]; then
                    printf '%b' "${RED}Error: Table '$tblname' does not exist.${NC}\n"
                elif [ -z "$data" ]; then
                    printf '%b' "${RED}Error: Data required to insert.${NC}\n"
                else
                    echo "$data" >> "db_manage/database/${CURRENT_DB}/tables/$tblname.tbl"
                    printf '%b' "${GREEN}Data inserted successfully into '$tblname'.${NC}\n"
                fi
            fi
            echo ""
            ;;
        "select_from")
            if [ "$CURRENT_DB" = "none" ]; then
                printf '%b' "${RED}Error: No active database. Use 'use <name>' first.${NC}\n"
            else
                if [ -z "$args" ]; then
                    printf '%b' "${RED}Error: Table name required. Usage: select_from <table_name>${NC}\n"
                elif [ -e "db_manage/database/${CURRENT_DB}/tables/$args.tbl" ]; then
                    printf '%b' "${BOLD}Records from table '$args':${NC}\n"
                    cat "db_manage/database/${CURRENT_DB}/tables/$args.tbl"
                else
                    printf '%b' "${RED}Error: Table '$args' does not exist.${NC}\n"
                fi
            fi
            echo ""
            ;;
        "update")
            if [ "$CURRENT_DB" = "none" ]; then
                printf '%b' "${RED}Error: No active database. Use 'use <name>' first.${NC}\n"
            else
                set -- $args
                tblname="$1"
                shift
                data="$*"
                if [ -z "$tblname" ]; then
                    printf '%b' "${RED}Error: Table name required. Usage: update <table_name> <data>${NC}\n"
                elif [ ! -e "db_manage/database/${CURRENT_DB}/tables/$tblname.tbl" ]; then
                    printf '%b' "${RED}Error: Table '$tblname' does not exist.${NC}\n"
                elif [ -z "$data" ]; then
                    printf '%b' "${RED}Error: Update data required.${NC}\n"
                else
                    echo "$data" > "db_manage/database/${CURRENT_DB}/tables/$tblname.tbl"
                    printf '%b' "${GREEN}Table '$tblname' updated successfully.${NC}\n"
                fi
            fi
            echo ""
            ;;
        "delete_from")
            if [ "$CURRENT_DB" = "none" ]; then
                printf '%b' "${RED}Error: No active database. Use 'use <name>' first.${NC}\n"
            else
                if [ -z "$args" ]; then
                    printf '%b' "${RED}Error: Table name required. Usage: delete_from <table_name>${NC}\n"
                elif [ -e "db_manage/database/${CURRENT_DB}/tables/$args.tbl" ]; then
                    rm "db_manage/database/${CURRENT_DB}/tables/$args.tbl"
                    touch "db_manage/database/${CURRENT_DB}/tables/$args.tbl"
                    printf '%b' "${GREEN}All records deleted from table '$args'.${NC}\n"
                else
                    printf '%b' "${RED}Error: Table '$args' does not exist.${NC}\n"
                fi
            fi
            echo ""
            ;;
        "delete_record")
            if [ "$CURRENT_DB" = "none" ]; then
                printf '%b' "${RED}Error: No active database. Use 'use <name>' first.${NC}\n"
            else
                set -- $args
                tblname="$1"
                shift
                target="$*"
                if [ -z "$tblname" ]; then
                    printf '%b' "${RED}Error: Table name required. Usage: delete_record <table_name> <value>${NC}\n"
                elif [ ! -e "db_manage/database/${CURRENT_DB}/tables/$tblname.tbl" ]; then
                    printf '%b' "${RED}Error: Table '$tblname' does not exist.${NC}\n"
                elif [ -z "$target" ]; then
                    printf '%b' "${RED}Error: Record value required. Usage: delete_record <table_name> <value>${NC}\n"
                else
                    tmp_file="db_manage/database/${CURRENT_DB}/tables/$tblname.tmp"
                    found=0
                    while IFS= read -r row || [ -n "$row" ]; do
                        if [ "$row" = "$target" ]; then
                            found=1
                        else
                            echo "$row" >> "$tmp_file"
                        fi
                    done < "db_manage/database/${CURRENT_DB}/tables/$tblname.tbl"
                    
                    if [ -f "$tmp_file" ]; then
                        mv "$tmp_file" "db_manage/database/${CURRENT_DB}/tables/$tblname.tbl"
                    else
                        true > "db_manage/database/${CURRENT_DB}/tables/$tblname.tbl"
                    fi

                    if [ "$found" -eq 1 ]; then
                        printf '%b' "${GREEN}Record '$target' deleted successfully from table '$tblname'.${NC}\n"
                    else
                        printf '%b' "${RED}Error: Record '$target' not found in table '$tblname'.${NC}\n"
                    fi
                fi
            fi
            echo ""
            ;;
        "api_key_list")
            printf '%b' "${BOLD}Configured API Secret Keys:${NC}\n"
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
                printf '%b' "  (No secret keys found in database.cfg)\n"
            fi
            echo ""
            ;;
        "api_setup")
            if [ "$CURRENT_DB" = "none" ]; then
                printf '%b' "${RED}Error: No active database. Use 'use <name>' first.${NC}\n"
            else
                show_banner
                printf '%b' "${BOLD}==================================================${NC}\n"
                printf '%b' "${BOLD}          API SETUP FOR: $CURRENT_DB              ${NC}\n"
                printf '%b' "${BOLD}==================================================${NC}\n\n"
                
                printf '%b' "Enter API Name: "
                read -r api_name
                printf '%b' "Enter Protocol (http or https) [http]: "
                read -r api_protocol
                [ -z "$api_protocol" ] && api_protocol="http"
                printf '%b' "Enter API Address (e.g., localhost or 0.0.0.0): "
                read -r api_address
                printf '%b' "Enter API Port (e.g., 8080): "
                read -r api_port

                printf '%b' "\n${YELLOW}Available Secret Keys:${NC}\n"
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
                    printf '%b' "  (No secret keys found in database.cfg)\n"
                fi

                resolved_secret=""
                while true; do
                    printf '%b' "\nEnter Secret Key or key name to use (leave empty for default): "
                    read -r selected_secret
                    
                    if [ -z "$selected_secret" ]; then
                        resolved_secret="default_secret"
                        break
                    fi

                    found_key=0
                    if [ -f "db_manage/secrets/database.cfg" ]; then
                        val_from_cfg=$(grep "^$selected_secret=" "db_manage/secrets/database.cfg" | cut -d'=' -f2)
                        if [ -n "$val_from_cfg" ]; then
                            resolved_secret="$val_from_cfg"
                            found_key=1
                        else
                            while IFS='=' read -r k v || [ -n "$k" ]; do
                                case "$k" in
                                    secret_key*)
                                        if [ "$v" = "$selected_secret" ]; then
                                            resolved_secret="$v"
                                            found_key=1
                                            break
                                        fi
                                        ;;
                                esac
                            done < "db_manage/secrets/database.cfg"
                        fi
                    fi

                    if [ "$found_key" -eq 1 ]; then
                        break
                    else
                        printf '%b' "${RED}Error: Secret key '$selected_secret' does not exist. Please enter a valid key name or value.${NC}\n"
                    fi
                done

                api_dir="db_manage/database/${CURRENT_DB}/api"
                mkdir -p "$api_dir"
                
                cat << EOF > "$api_dir/api.cfg"
Name=$api_name
Protocol=$api_protocol
Address=$api_address
Port=$api_port
SecretKey=$resolved_secret
EOF
                generate_server_script "$api_dir/server.py"
                
                api_proto_upper=$(echo "$api_protocol" | tr '[:lower:]' '[:upper:]')
                printf '%b' "\n${GREEN}API setup completed successfully for database '$CURRENT_DB' with protocol [$api_proto_upper].${NC}\n"
            fi
            echo ""
            ;;
        "api_edit")
            if [ "$CURRENT_DB" = "none" ]; then
                printf '%b' "${RED}Error: No active database. Use 'use <name>' first.${NC}\n"
            else
                show_banner
                printf '%b' "${BOLD}==================================================${NC}\n"
                printf '%b' "${BOLD}         EDIT API CONFIGURATION: $CURRENT_DB      ${NC}\n"
                printf '%b' "${BOLD}==================================================${NC}\n\n"
                printf '%b' "Options that can be changed: ${CYAN}Name | Protocol | Address | Port | SecretKey${NC}\n\n"

                api_dir="db_manage/database/${CURRENT_DB}/api"
                api_cfg="$api_dir/api.cfg"

                curr_name=""
                curr_proto="http"
                curr_addr=""
                curr_port=""
                curr_secret=""
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

                printf '%b' "Enter new Name [$curr_name]: "
                read -r new_name
                [ -n "$new_name" ] && curr_name="$new_name"

                printf '%b' "Enter new Protocol (http/https) [$curr_proto]: "
                read -r new_proto
                [ -n "$new_proto" ] && curr_proto="$new_proto"

                printf '%b' "Enter new Address [$curr_addr]: "
                read -r new_addr
                [ -n "$new_addr" ] && curr_addr="$new_addr"

                printf '%b' "Enter new Port [$curr_port]: "
                read -r new_port
                [ -n "$new_port" ] && curr_port="$new_port"

                printf '%b' "\n${YELLOW}Available Secret Keys:${NC}\n"
                if [ -f "db_manage/secrets/database.cfg" ]; then
                    while IFS='=' read -r k v || [ -n "$k" ]; do
                        case "$k" in
                            secret_key*)
                                printf '%b' "  - ${CYAN}$k${NC}: $v\n"
                                ;;
                        esac
                    done < "db_manage/secrets/database.cfg"
                fi

                while true; do
                    printf '%b' "\nEnter new Secret Key or key name [$curr_secret] (leave empty to keep current): "
                    read -r new_secret
                    
                    [ -z "$new_secret" ] && break

                    found_key=0
                    resolved_secret=""
                    if [ -f "db_manage/secrets/database.cfg" ]; then
                        val_from_cfg=$(grep "^$new_secret=" "db_manage/secrets/database.cfg" | cut -d'=' -f2)
                        if [ -n "$val_from_cfg" ]; then
                            resolved_secret="$val_from_cfg"
                            found_key=1
                        else
                            while IFS='=' read -r k v || [ -n "$k" ]; do
                                case "$k" in
                                    secret_key*)
                                        if [ "$v" = "$new_secret" ]; then
                                            resolved_secret="$v"
                                            found_key=1
                                            break
                                        fi
                                        ;;
                                esac
                            done < "db_manage/secrets/database.cfg"
                        fi
                    fi

                    if [ "$found_key" -eq 1 ]; then
                        curr_secret="$resolved_secret"
                        break
                    else
                        printf '%b' "${RED}Error: Secret key '$new_secret' does not exist. Please enter a valid key name or value.${NC}\n"
                    fi
                done

                mkdir -p "$api_dir"
                cat << EOF > "$api_cfg"
Name=$curr_name
Protocol=$curr_proto
Address=$curr_addr
Port=$curr_port
SecretKey=$curr_secret
EOF
                generate_server_script "$api_dir/server.py"
                printf '%b' "\n${GREEN}API configuration updated successfully!${NC}\n"
            fi
            echo ""
            ;;
        "api_start")
            if [ "$CURRENT_DB" = "none" ]; then
                printf '%b' "${RED}Error: No active database. Use 'use <name>' first.${NC}\n"
            else
                api_dir="db_manage/database/${CURRENT_DB}/api"
                api_cfg="$api_dir/api.cfg"
                pid_file="$api_dir/api.pid"
                server_script="$api_dir/server.py"

                if [ ! -f "$api_cfg" ]; then
                    printf '%b' "${RED}Error: API is not configured. Run 'api_setup' first.${NC}\n"
                elif [ -f "$pid_file" ] && kill -0 "$(cat "$pid_file" 2>/dev/null)" 2>/dev/null; then
                    printf '%b' "${YELLOW}API for '$CURRENT_DB' is already running (PID: $(cat "$pid_file")).${NC}\n"
                else
                    [ ! -f "$server_script" ] && generate_server_script "$server_script"

                    api_name_val=$(grep "^Name=" "$api_cfg" 2>/dev/null | cut -d'=' -f2)
                    api_proto_val=$(grep "^Protocol=" "$api_cfg" 2>/dev/null | cut -d'=' -f2)
                    api_port_val=$(grep "^Port=" "$api_cfg" 2>/dev/null | cut -d'=' -f2)
                    api_secret_val=$(grep "^SecretKey=" "$api_cfg" 2>/dev/null | cut -d'=' -f2)
                    
                    [ -z "$api_name_val" ] && api_name_val="$CURRENT_DB-api"
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

                    API_PORT="$port" API_SECRET="${api_secret_val:-default_secret}" DB_NAME="$CURRENT_DB" API_PROTOCOL="$proto" API_CERT="$cert_arg" API_KEY="$key_arg" python3 "$server_script" > "$api_dir/server.log" 2>&1 &
                    server_pid=$!
                    echo "$server_pid" > "$pid_file"

                    proto_upper=$(echo "$proto" | tr '[:lower:]' '[:upper:]')
                    printf '%b' "${GREEN}API server '${api_name_val}' started successfully via ${proto_upper} on port ${port} (PID: ${server_pid})!${NC}\n"
                fi
            fi
            echo ""
            ;;
        "api_stop")
            if [ "$CURRENT_DB" = "none" ]; then
                printf '%b' "${RED}Error: No active database. Use 'use <name>' first.${NC}\n"
            else
                api_dir="db_manage/database/${CURRENT_DB}/api"
                api_cfg="$api_dir/api.cfg"
                pid_file="$api_dir/api.pid"

                if [ ! -f "$pid_file" ]; then
                    printf '%b' "${YELLOW}API for '$CURRENT_DB' is not currently running.${NC}\n"
                else
                    pid=$(cat "$pid_file" 2>/dev/null)
                    api_name_val=$(grep "^Name=" "$api_cfg" 2>/dev/null | cut -d'=' -f2)
                    [ -z "$api_name_val" ] && api_name_val="$CURRENT_DB"

                    force_flag=0
                    for arg in $args; do
                        [ "$arg" = "--force" ] && force_flag=1
                    done

                    proceed=1
                    if [ "$force_flag" -eq 0 ]; then
                        printf '%b' "Are you sure you want to stop API '${api_name_val}'? (y/n): "
                        read -r confirm
                        case "$confirm" in
                            [yY] | [yY][eE][sS]) proceed=1 ;;
                            *) proceed=0 ;;
                        esac
                    fi

                    if [ "$proceed" -eq 1 ]; then
                        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
                            kill "$pid" 2>/dev/null || kill -9 "$pid" 2>/dev/null
                        fi
                        rm -f "$pid_file"
                        printf '%b' "${GREEN}API server '${api_name_val}' stopped successfully.${NC}\n"
                    else
                        printf '%b' "${YELLOW}Operation cancelled.${NC}\n"
                    fi
                fi
            fi
            echo ""
            ;;
        "api_delete")
            if [ "$CURRENT_DB" = "none" ]; then
                printf '%b' "${RED}Error: No active database. Use 'use <name>' first.${NC}\n"
            else
                api_dir="db_manage/database/${CURRENT_DB}/api"
                pid_file="$api_dir/api.pid"

                if [ ! -d "$api_dir" ]; then
                    printf '%b' "${YELLOW}API configuration for database '$CURRENT_DB' does not exist.${NC}\n"
                else
                    if [ -f "$pid_file" ]; then
                        pid=$(cat "$pid_file" 2>/dev/null)
                        [ -n "$pid" ] && kill "$pid" 2>/dev/null
                    fi
                    rm -rf "$api_dir"
                    printf '%b' "${GREEN}API configuration and files for database '$CURRENT_DB' were deleted successfully.${NC}\n"
                fi
            fi
            echo ""
            ;;
        "api_status")
            if [ "$CURRENT_DB" = "none" ]; then
                printf '%b' "${RED}Error: No active database. Use 'use <name>' first.${NC}\n"
            else
                api_dir="db_manage/database/${CURRENT_DB}/api"
                api_cfg="$api_dir/api.cfg"
                pid_file="$api_dir/api.pid"

                if [ ! -f "$api_cfg" ]; then
                    printf '%b' "${RED}Error: API is not configured. Run 'api_setup' first.${NC}\n"
                else
                    api_name_val=$(grep "^Name=" "$api_cfg" 2>/dev/null | cut -d'=' -f2)
                    api_proto_val=$(grep "^Protocol=" "$api_cfg" 2>/dev/null | cut -d'=' -f2)
                    api_addr_val=$(grep "^Address=" "$api_cfg" 2>/dev/null | cut -d'=' -f2)
                    api_port_val=$(grep "^Port=" "$api_cfg" 2>/dev/null | cut -d'=' -f2)
                    
                    printf '%b' "${CYAN}==================================================${NC}\n"
                    printf '%b' "${BOLD}         API STATUS: ${api_name_val:-$CURRENT_DB}       ${NC}\n"
                    printf '%b' "${CYAN}==================================================${NC}\n"
                    printf '%b' " Database: ${GREEN}$CURRENT_DB${NC}\n"
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

                    if [ "$is_running" -eq 0 ]; then
                        printf '%b' " Status:   ${RED}STOPPED${NC}\n"
                    fi
                    printf '%b' "${CYAN}==================================================${NC}\n"
                fi
            fi
            echo ""
            ;;
        "api_request")
            if [ "$CURRENT_DB" = "none" ]; then
                printf '%b' "${RED}Error: No active database. Use 'use <name>' first.${NC}\n"
            elif [ -z "$args" ]; then
                printf '%b' "${RED}Error: Command required. Usage: api_request <command> [args]${NC}\n"
            else
                api_dir="db_manage/database/${CURRENT_DB}/api"
                api_cfg="$api_dir/api.cfg"
                pid_file="$api_dir/api.pid"

                if [ ! -f "$api_cfg" ]; then
                    printf '%b' "${RED}Error: API is not configured. Run 'api_setup' first.${NC}\n"
                elif [ ! -f "$pid_file" ] || ! kill -0 "$(cat "$pid_file" 2>/dev/null)" 2>/dev/null; then
                    printf '%b' "${RED}Error: API server is not running. Start it with 'api_start' first.${NC}\n"
                else
                    api_proto_val=$(grep "^Protocol=" "$api_cfg" 2>/dev/null | cut -d'=' -f2)
                    api_addr_val=$(grep "^Address=" "$api_cfg" 2>/dev/null | cut -d'=' -f2)
                    api_port_val=$(grep "^Port=" "$api_cfg" 2>/dev/null | cut -d'=' -f2)
                    api_secret_val=$(grep "^SecretKey=" "$api_cfg" 2>/dev/null | cut -d'=' -f2)
                    
                    proto="${api_proto_val:-http}"
                    addr="${api_addr_val:-localhost}"
                    port="${api_port_val:-8080}"
                    
                    # Traduzir o comando CLI inserido para o respetivo endpoint e método HTTP
                    set -- $args
                    sub_cmd="$1"
                    shift
                    sub_args="$*"
                    
                    endpoint=""
                    http_method="GET"
                    json_body=""

                    case "$sub_cmd" in
                        "show_databases")
                            endpoint="/show_databases"
                            ;;
                        "show_tables")
                            endpoint="/show_tables"
                            ;;
                        "api_status")
                            endpoint="/status"
                            ;;
                        "describe")
                            endpoint="/describe/$sub_args"
                            ;;
                        "create_table")
                            http_method="POST"
                            endpoint="/create_table/$sub_args"
                            ;;
                        "drop_table")
                            http_method="DELETE"
                            endpoint="/drop_table/$sub_args"
                            ;;
                        "select_from")
                            endpoint="/select_from/$sub_args"
                            ;;
                        "insert_into")
                            http_method="POST"
                            set -- $sub_args
                            tbl="$1"
                            shift
                            data="$*"
                            endpoint="/insert_into/$tbl"
                            json_body="{\"data\": \"$data\"}"
                            ;;
                        "delete_from")
                            http_method="DELETE"
                            endpoint="/delete_from/$sub_args"
                            ;;
                        "delete_record")
                            http_method="DELETE"
                            set -- $sub_args
                            tbl="$1"
                            shift
                            val="$*"
                            encoded_val=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$val")
                            endpoint="/delete_record/$tbl/$encoded_val"
                            ;;
                        *)
                            endpoint="/$sub_cmd"
                            [ -n "$sub_args" ] && endpoint="/$sub_cmd/$sub_args"
                            ;;
                    esac

                    url="$proto://$addr:$port$endpoint"
                    printf '%b' "${YELLOW}Executing via API [$http_method $url]...${NC}\n"
                    
                    if command -v curl >/dev/null 2>&1; then
                        curl_opts="-s"
                        [ "$proto" = "https" ] && curl_opts="-s -k" # -k ignora certificados autoassinados por conveniência
                        
                        if [ -n "$json_body" ]; then
                            curl $curl_opts -X "$http_method" -H "X-Secret-Key: $api_secret_val" -H "Content-Type: application/json" -d "$json_body" "$url"
                        else
                            curl $curl_opts -X "$http_method" -H "X-Secret-Key: $api_secret_val" "$url"
                        fi
                        echo ""
                    else
                        printf '%b' "${RED}Error: 'curl' is required to send API requests in this environment.${NC}\n"
                    fi
                fi
            fi
            echo ""
            ;;
        "api_key_add")
            if [ -z "$args" ]; then
                printf '%b' "${RED}Error: Key required. Usage: api_key_add <key>${NC}\n"
            else
                count=0
                if [ -f "db_manage/secrets/database.cfg" ]; then
                    raw_count=$(grep -c "^secret_key[0-9]" "db_manage/secrets/database.cfg" 2>/dev/null)
                    [ -n "$raw_count" ] && count="$raw_count"
                fi
                next_idx=$(expr "$count" + 1)
                echo "secret_key$next_idx=$args" >> "db_manage/secrets/database.cfg"
                printf '%b' "${GREEN}Secret key added successfully as secret_key$next_idx.${NC}\n"
            fi
            echo ""
            ;;
        "api_key_remove")
            if [ -z "$args" ]; then
                printf '%b' "${RED}Error: Key or index required. Usage: api_key_remove <key>${NC}\n"
            else
                if [ -f "db_manage/secrets/database.cfg" ]; then
                    temp_file="db_manage/secrets/database.cfg.tmp"
                    touch "$temp_file"
                    found=0
                    i=1
                    while IFS= read -r line || [ -n "$line" ]; do
                        case "$line" in
                            secret_key[0-9]*=*)
                                val="${line#*=}"
                                if [ "$val" = "$args" ] || [ "$line" = "$args" ]; then
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
                        printf '%b' "${GREEN}Secret key '$args' removed and configuration re-indexed successfully.${NC}\n"
                    else
                        printf '%b' "${RED}Error: Key '$args' not found.${NC}\n"
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
