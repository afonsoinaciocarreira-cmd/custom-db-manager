# 🚀 Custom DB Manager CLI & API (BETA)

A lightweight database management system written in Shell Script (`/bin/sh`), featuring support for **multiple file-based relational databases**, an **API Key security system**, and an **integrated Python HTTP/HTTPS server** equipped with dynamic RESTful endpoints and an interactive Web control panel.

---

## 📂 Directory Structure

The system automatically organizes files and secrets in the following structure:

<img width="473" height="33" alt="image" src="https://github.com/user-attachments/assets/413d725d-78db-40fb-bd84-6d8278b31308" />
<img width="249" height="26" alt="image" src="https://github.com/user-attachments/assets/a2091f44-8741-4430-8be4-efd2d6e83777" />
<img width="485" height="34" alt="image" src="https://github.com/user-attachments/assets/45a044c2-43e4-4270-b708-8290f2a36b15" />

.  
├── **`mainDir/`**  
├── **`customdb.sh`**                \# Main CLI script

└── **`db\_manage/`**

├── **`database/`**# Databases directory

│   └── **`\\\<db\\\_name\\\>/`**

│       ├── **`\\\<db\\\_name\\\>`**.db  \\\# Metadata and database schema

│       ├── **`tables/`**     \\\# Corresponding .tbl table files

│       └── **`api/`**        \\\# API configuration, logs, and server files (server.py, api.cfg, api.pid)

└── **`secrets/`**

   └── **`database.cfg`**    \\\# Global secret keys configuration file (Secret Keys)
   
---

## 🛠️ CLI Commands & Functional Description
<img width="414" height="132" alt="image" src="https://github.com/user-attachments/assets/d15b1fbd-0af4-499a-9277-2f3291988e63" />

---
<img width="562" height="769" alt="image" src="https://github.com/user-attachments/assets/9a174d25-d468-4cac-9de9-34d53e0104b2" />

---
### 📂 Database Management

* **`create_database <name>`**: Creates a new database, generating the table structure, metadata, and the internal API server script.  
* **`use <name>`**: Selects and sets the active database for subsequent operations.  
* **`show_databases`**: Lists all databases created in the system.  
* **`describe <name>`**: Displays structural metadata and configuration contents for a specific database.  
* **`drop_database <name>`**: Completely deletes a database, automatically stopping its API server if running.  
* **`dump_db`**: Displays a universal grid export of all data and tables in the active database.

### 🗄️ Table Management

* **`create_table <name>`**: Creates a new table within the active database.  
* **`show_tables`**: Lists all tables existing in the selected database.  
* **`drop_table <name>`**: Permanently removes a table and its records from the active database.

### ⚡ Data Operations

* **`insert_into <table> <data>`**: Inserts a new row/record into the specified table.  
* **`select_from <table>`**: Queries and prints all records stored in a table.  
* **`update <table> <data>`**: Updates/overwrites data inside a table.  
* **`delete_from <table>`**: Clears all records from a table (keeping its structure).  
* **`delete_record <table> <value>`**: Deletes a specific record matching the exact value within a table.

### 🌐 API Management & Control

* **`api_setup`**: Interactively configures the API server for the active database (Name, Protocol `http`/`https`, Address, Port, and Secret Key).  
* **`api_edit`**: Edits existing API configurations for the active database.  
* **`api_start`**: Starts the HTTP or HTTPS server in the background (if configured as `https`, automatically generates self-signed SSL certificates if needed).  
* **`api_stop [--force]`**: Stops the active database's API server.  
* **`api_delete`**: Completely removes all API files, logs, and configurations associated with the active database.  
* **`api_status`**: Shows the current API status (running/stopped state, port, address, and protocol).  
* **`api_request <command>`**: Executes any CLI command directly through the API endpoint, simulating an external request and displaying the JSON result.

### 🔑 Secret Keys Management

* **`api_key_list`**: Lists all global access secret keys configured in the system.  
* **`api_key_add <key>`**: Adds a new authentication secret key.  
* **`api_key_remove <key/index>`**: Removes a secret key and re-indexes the configuration file.

### 🛠️ System

* **`clear`**: Clears the screen and reloads the main banner.  
* **`help`**: Displays the interactive help menu.  
* **`exit` / `quit`**: Exits the CLI application.

---

## 🌐 RESTful API Documentation

The automatically generated API for each database supports both **HTTP** and **HTTPS** protocols.

### 🔐 Authentication

All requests made to the API require secret key validation. You can provide it in two ways:

1. Via HTTP Header: `X-Secret-Key: <your_key>`  
2. Via Query Parameter: `?key=<your_key>`

---

## 💻 How to Use the API in Any Programming Language

Below are practical examples of how to consume API endpoints (e.g., querying table data) across various programming languages. *(Replace `http://localhost:8080` with your actual protocol, address, and port configuration, and `your_secret_key` with your Secret Key)(Any existing command is considered an endpoint).*

### 1\. cURL (Command Line)
```
curl \-X GET "http\://localhost:8080/select\_from/users" \\

 \\-H "X-Secret-Key: your\\\_secret\\\_key"

*(If using **HTTPS** with a self-signed certificate, add the `-k` flag to bypass security warnings).*
```
---

### 2\. Python (`requests`)
```
import requests

url \= "http\://localhost:8080/select\_from/users"

headers \= {"X-Secret-Key": "your\_secret\_key"}

response \= requests.get(url, headers=headers, verify=False)  \# verify=False only for self-signed HTTPS

print(response.json())
```
---

### 3\. JavaScript / Node.js (`fetch`)
```
async function getData() {

const url \\= "http\\://localhost:8080/select\\\_from/users";

const response \\= await fetch(url, {

    method: "GET",

    headers: {

        "X-Secret-Key": "your\\\_secret\\\_key"

    }

});

const data \\= await response.json();

console.log(data);

}

getData();
```
---
### 4\. PHP (`cURL`)
```
\<?php

\$url \= "http\://localhost:8080/select\_from/users";

\$ch \= curl\_init(\$url);

curl\_setopt(\$ch, CURLOPT\_RETURNTRANSFER, true);

curl\_setopt(\$ch, CURLOPT\_HTTPHEADER, \[

"X-Secret-Key: your\\\_secret\\\_key"

\]);

// curl\_setopt(\$ch, CURLOPT\_SSL\_VERIFYPEER, false); // Uncomment if using self-signed HTTPS

\$response \= curl\_exec(\$ch);

curl\_close(\$ch);

print\_r(json\_decode(\$response, true));

?\>
```
---

### 5\. Go (`net/http`)
```
package main

import (

"fmt"

"io"

"net/http"

)

func main() {

client := \\\&http.Client{}

req, \\\_ := http.NewRequest("GET", "http\\://localhost:8080/select\\\_from/users", nil)

req.Header.Add("X-Secret-Key", "your\\\_secret\\\_key")

resp, err := client.Do(req)

if err \\\!= nil {

	panic(err)

}

defer resp.Body.Close()

body, \\\_ := io.ReadAll(resp.Body)

println(string(body))

}
```
---

### 6\. C\# (`HttpClient`)
```
using System;

using System.Net.Http;

using System.Threading.Tasks;

class Program

{

static async Task Main()

{

    using var client \\= new HttpClient();

    client.DefaultRequestHeaders.Add("X-Secret-Key", "your\\\_secret\\\_key");

    var response \\= await client.GetAsync("http\\://localhost:8080/select\\\_from/users");

    var jsonString \\= await response.Content.ReadAsStringAsync();

    

    Console.WriteLine(jsonString);

}

}
```
---
### 7\. Java (`HttpClient`)
```
import java.net.URI;

import java.net.http.HttpClient;

import java.net.http.HttpRequest;

import java.net.http.HttpResponse;

public class ApiClient {

public static void main(String\\\[\\\] args) throws Exception {

    HttpClient client \\= HttpClient.newHttpClient();

    HttpRequest request \\= HttpRequest.newBuilder()

        .uri(URI.create("http\\://localhost:8080/select\\\_from/users"))

        .header("X-Secret-Key", "your\\\_secret\\\_key")

        .GET()

        .build();

    HttpResponse\\\<String\\\> response \\= client.send(request, HttpResponse.BodyHandlers.ofString());

    System.out.println(response.body());

}

}
```
---

## 📊 Interactive Web Dashboard

Opening the main API address in your browser (e.g., `http://localhost:8080/` or `https://localhost:8080/`) triggers an automatic `Accept: text/html` check, rendering a rich **Web Dashboard** displaying in real-time:

* The operational status of the API and the active protocol.  
* Existing tables in the database.  
* Formatted JSON output of endpoint responses.
