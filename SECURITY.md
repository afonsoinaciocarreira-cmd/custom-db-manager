# Security Policy — Custom DB Manager

**Security and deployment guidance**  
**Software version reviewed:** 1.0  
**Reviewed format:** single Bash file with embedded Python code  
**Reference source:** `versions/customdb-manager/customdb.sh`

This document describes the controls present in the published code and establishes recommendations for secure use. It is not a certification, independent audit, guarantee of invulnerability, or declaration of regulatory compliance.

---

## 1. Purpose and Scope

Custom DB Manager is a local-first data manager featuring a CLI, file-based storage, an HTTP API, and backup automation. It is designed to be usable in personal and professional contexts, including internal services, team tools, and operational environments of controlled size.

The actual security of an installation depends on four areas:

1. **Host:** system account, permissions, updates, isolation, and firewall.
2. **Data:** directories, files, integrity, backups, and cryptographic keys.
3. **API:** network exposure, two-key authentication, permissions, and TLS.
4. **Operations:** process control, retention, restore, and incident response.

The software does not implement a distributed platform or a complete enterprise identity service. It should be deployed in accordance with the limitations described in this document.

## 2. Threat Model

### Assets to Protect

- Database records and metadata.
- API configurations and their keys.
- Backup encryption and signing secrets.
- Backup archives and their manifests.
- Configuration files and command history.
- Availability of API servers and automated workers.

### Relevant Threats

- An unauthorised local user reading or modifying `db_manage`.
- An unauthorised remote client invoking API endpoints.
- Accidental exposure of keys in URLs, shell history, or proxy logs.
- Improper access to the `secret` API or overly broad public permissions.
- Loss, corruption, or removal of the primary disk or secondary destination.
- Loss of keys required to decrypt or validate backups.
- Concurrent writes, unexpected shutdown, or use of a filesystem without the required guarantees.
- Execution of a script version whose origin or integrity has not been validated.

### Outside the Scope of Automatic Protection

The program does not, by itself, protect against compromise of the operating-system user running it, malicious root access, host malware, physical theft, interception over an HTTP channel without TLS, host unavailability, simultaneous failure of multiple disks, or abuse by an authorised user with administrative permissions.

---

## 3. Security Requirements and Assumptions

### Operating System and Filesystem

Linux is the recommended operational target. The code uses mechanisms associated with Unix/Linux environments, including `fcntl.flock`, POSIX permissions, process signals, and information in `/proc` to identify managed processes.

Storage should reside on a local filesystem that correctly implements `flock` locks, `fsync`, and atomic file replacement. Do not assume that a network filesystem, mounted cloud synchronisation service, or volume shared by multiple hosts provides equivalent semantics. Multi-host use requires its own testing and is not a clustering capability provided by the tool.

### Least-Privilege Execution

- Run the CLI under a dedicated account and without `sudo`, except in exceptional operational circumstances.
- Do not run the application as `root` merely to work around permission problems.
- Do not allow untrusted users to write to the installation directory or `db_manage`.
- Protect the working directory because `db_manage` is created relative to the current working directory.
- Avoid running the same data set from different working directories: each directory may create a separate `db_manage` tree.

---

## 4. Local File and Secret Protection

### Locations

Data is stored in `db_manage/database/<database>/`. API configurations are located under `api/public` and `api/secret`; backup secrets and settings are stored in `secrets`.

The code applies restrictive permissions to some items, including:

- `secrets` directory: mode `0700`;
- sensitive key/configuration files: mode `0600`;
- API configuration files: mode `0600`;
- backup files: mode set by `storage_permissions` (default `700`).

These permissions do not replace correct ownership and group management at the operating-system level. Also check the permissions of parent directories, mounted volumes, and external destinations.

### API Credentials

Keys are registered in the database's configuration files and are also written to the API configuration when used. The `api_key list` command displays key values in the terminal. The CLI's `api_request` helper currently constructs requests using the query-string form; for integrations requiring reduced credential exposure, use a direct HTTP client with `Authorization: Bearer`.

Recommendations:

- Use long, random, distinct keys that are not reused in other systems.
- Do not include keys in tickets, screenshots, public documentation, version-controlled scripts, or support messages.
- Restrict access to `db_manage/database/<database>/secrets` and `api.cfg` files.
- Do not share the output of `api_key list`.
- Remove old keys after replacing them in API configurations.
- Maintain a controlled record of who has access to both keys.

The requirement for two distinct keys means that the client must present both values. **It is not equivalent to multi-factor authentication:** both keys are sent together in the same header/query and do not represent two independent factors or two individual identities.

### Key Rotation

The `api_key remove` command prevents removal of a key that is still used by an API configuration. Recommended procedure:

1. Generate two new, distinct keys.
2. Update the API with `api_edit <public|secret>` or configure the API again.
3. Restart and validate the API server.
4. Confirm that clients are already using the new pair.
5. Remove the old keys with `api_key remove <key|secret_key_N>`.

Rotation is not automatic, and keys do not have an implemented expiry period.

---

## 5. HTTP API Security

### Mandatory Authentication

All requests are authenticated before an endpoint is executed. Two formats are accepted:

**Recommended — Authorization header:**

```http
Authorization: Bearer <key1>/<key2>
```

**Compatibility — query string:**

```text
?key=<key1>/<key2>
```

The code also recognises alternative separators (`:` and `,`) in the combined value. The two keys are compared using `hmac.compare_digest`.

If a malformed `Authorization` header is supplied, the request is rejected; the server does not silently fall back to the query string as an alternative. This reduces ambiguity between authentication methods.

### Avoid Credentials in URLs

Always prefer `Authorization: Bearer`. Query parameters may be exposed in:

- shell history;
- reverse proxy, gateway, and load balancer logs;
- diagnostic tools;
- browser history or HTTP clients;
- process arguments while a client is making a request.

The server minimises exposure in its own HTTP logs, but it does not control the logs of external components.

### `public` API and `secret` API

**`public`** checks `permissions.cfg`. Known permissions are initialised as `false`, so protected operations must be explicitly enabled with `api_permissions <perm> <true|false>`.

**`secret`** bypasses permission-matrix checks after validating both keys. It must be treated as a privileged administrative interface.

Recommended policy:

- keep the `secret` API on `localhost` whenever possible;
- do not expose the `secret` API directly to the Internet;
- enable only the permissions strictly required by the `public` API;
- restrict access through a firewall to authorised addresses and networks;
- use separate credentials per database and integration;
- review permissions whenever an integration is added or removed.

The permission matrix contains CLI operation names, but only HTTP endpoints implemented in the code are available over HTTP. A key in `permissions.cfg` does not automatically create an endpoint.

### Listening Address and Network Exposure

The setup assistant uses `localhost` as the default address. This limits listening to the loopback interface. To allow remote access, the listening address must be deliberately configured and the firewall must restrict authorised sources.

Do not configure `0.0.0.0` or a public address without understanding that the API will become accessible through the corresponding interfaces. Do not expose the `secret` API to untrusted networks.

### TLS / HTTPS

The API supports `http` and `https`. When needed, the code can automatically generate a self-signed certificate through OpenSSL, with `CN=localhost`.

A self-signed certificate does not, by itself, establish public trust in the server. For professional remote use:

- prefer a certificate issued by a trusted certificate authority;
- validate the DNS name, certificate chain, validity period, and renewal process;
- consider terminating TLS at a correctly configured reverse proxy;
- do not disable certificate validation in clients to bypass warnings;
- protect private-key files and restrict who can read them.

HTTPS support in the code is not equivalent to a complete enterprise TLS configuration or a cryptographic configuration audit.

### Request Rate Limiting and Body Size

The `public` API applies an in-memory limit of 10 requests per IP address within a 5-second interval. `POST` and `PUT` request bodies are limited to 2 MB.

This is a basic control, resets when the process restarts, and does not replace perimeter protection, a WAF, global quotas, abuse monitoring, or DDoS mitigation. The code does not apply the same per-IP limit to the `secret` API.

### Endpoints and Operations with Impact

The API exposes endpoints for status, dump, table listing, reading, inserting, table creation/removal, and record deletion. Destructive operations such as `drop_table`, `delete_from`, and `delete_record` should only be authorised when necessary.

Before granting permissions to clients, assess the impact of each endpoint and restrict the API to the required network.

---

## 6. Concurrency, Integrity, and Writes

The storage engine combines:

- `threading.RLock` for coordination within a process;
- `fcntl.flock` for coordination between processes on the same host;
- temporary files in the same directory as the destination;
- `flush`/`fsync` where applicable;
- `os.replace` to publish files/manifests atomically;
- storage generations and a manifest to reference the active table state.

Table read and modification routines use table-specific locks. API insert and delete operations perform the read/modify/publish transaction while holding the table lock.

### Limits of These Guarantees

- `flock` is advisory: all writers must follow the locking protocol.
- The guarantee targets processes on the same host and a filesystem with compatible semantics.
- There is no consensus or distributed coordination between multiple servers.
- An atomic file write does not automatically make multiple separate operations a distributed transaction.
- There is no WAL-based point-in-time recovery feature.

For processes sharing the same database, keep all access on the same host and through the same data tree.

---

## 7. Backup Protection

### Archive Contents

Backups archive the database directory and exclude the backups directory itself, `.pid` files, logs, and the internal keys `backup_encryption.key` and `backup_manifest.key`.

API configurations and other database configuration files may be included in the archive. Consequently, an unencrypted backup may contain sensitive information, including API credentials.

### Encryption

When `encrypt_backups=true`, the code uses OpenSSL with:

```text
AES-256-CBC + salt + PBKDF2
```

The key/passphrase is generated and stored in a private file at `secrets/backup_encryption.key`. This file is excluded from the archive so that the encrypted archive does not contain its own key.

**Critical operational implication:** the encryption key is not recoverable from the backup. Keep a secure, independent copy of the key. If the primary disk fails and the only copy of the key is on that disk, encrypted archives on the secondary disk may become unrecoverable.

CBC encryption does not, by itself, provide cryptographic authentication of the contents. To detect corruption and tampering, also enable SHA-256 verification and HMAC signing, while preserving the signing key. By default, `encrypt_backups`, `verify_integrity`, and `sign_manifest` are disabled; a backup created without changing these settings is not encrypted and does not include these additional controls.

### Verification and Signing

- `verify_integrity=true`: calculates and writes a `.sha256` sidecar, which is validated during restore.
- `sign_manifest=true`: generates a `.sig` sidecar with an HMAC-SHA256 signature of the archive digest.

The signature is symmetric: the HMAC secret key is required to validate authenticity. It is not an asymmetric digital signature and does not provide non-repudiation.

The `backup_manifest.key` key is also excluded from the archive and must be preserved separately.

### Secondary Disk Destination

`backup_storage_path` requires an existing, mounted, writable absolute path on a filesystem different from the primary `db_manage` directory.

The program stores backups in `<backup_storage_path>/<database>/` and checks the storage device. If the destination is unavailable or does not meet the conditions, the operation should fail instead of silently treating it as a directory on the primary disk.

A secondary disk alone is not a complete continuity strategy. To reduce risk, also maintain an offline copy or a copy at another physical location, control access to the volume, and regularly test reading and restoring backups.

### Retention and Automatic Deletion

`auto_cleanup`, `max_backups`, `keep_daily`, and `keep_weekly` may automatically remove older backups. Configure retention carefully and confirm that the policy meets the organisation's recovery requirements.

### Recovery Testing

Perform test restores in an isolated environment. Confirm:

- that the archive exists and is readable;
- that SHA-256 verification and HMAC signing pass, when enabled;
- that decryption keys are available;
- that the restored database contains the expected tables and records;
- that the API and workers can be restarted correctly;
- that the application operates again with the secondary destination configured.

---

## 8. Process Management and Destructive Commands

API processes and backup workers are identified through PID files and process metadata, including a management token and process identity information. The `system_process` command lists managed processes, and `system_process kill` accepts managed identifiers rather than arbitrary PIDs.

The `system_terminate` command is particularly destructive: it stops managed processes and removes the `db_manage` tree, then recreates the base structure. Do not use it as a routine shutdown command or without a validated backup.

`drop_database`, `drop_table`, `delete_from`, `delete_record`, `backup_restore`, and `backup_delete` may also remove or replace data. Restrict their use and require operational confirmation in shared environments.

---

## 9. Logging, History, and Sensitive Information

- Command history is persisted per database in `.cli_history`, with a separate history when no database is active.
- API logs avoid writing the full request path/query, reducing direct exposure of credentials sent in the query string.
- Backup workers write their own logs; the terminal window is a viewer for those logs.
- `api_key list` prints keys and should only be used in private terminals.
- Configuration files and logs may reveal database/table names, addresses, ports, activity, and operational errors.

Do not include secrets in error messages, backup names, version-controlled automation scripts, or support reports.

---

## 10. Hardening Guide for a Professional Deployment

Before putting an installation into service:

- [ ] Pin the exact script version and validate its source.
- [ ] Record the SHA-256 hash of the approved version and control updates.
- [ ] Run under a dedicated system account without excessive privileges.
- [ ] Restrict permissions on the script, `db_manage`, `secrets`, and API files.
- [ ] Keep the API address on `localhost` if remote access is not required.
- [ ] If remote access is required, restrict the network through a firewall and use TLS with a trusted certificate.
- [ ] Prefer `Authorization: Bearer` and never distribute URLs containing keys.
- [ ] Create two strong, distinct keys specific to the database.
- [ ] Keep the `secret` API off public networks and review the `public` permission matrix.
- [ ] Enable `encrypt_backups`, `verify_integrity`, and `sign_manifest` according to policy.
- [ ] Preserve encryption and signing keys in an independent secure vault.
- [ ] Configure a genuinely independent secondary destination and test behaviour when it is unmounted.
- [ ] Define retention and perform restore rehearsals.
- [ ] Monitor processes, logs, disk space, backups, and errors.
- [ ] Document owners for keys, approvals, recovery, and incident response.
- [ ] Do not assume multi-host support or high availability without a validated external architecture.

---

## 11. Incident Response

### Suspected API Key Exposure

1. Identify the database and APIs that use the key.
2. Generate a new key pair and update the API configuration with `api_edit`.
3. Restart/validate the service and update authorised clients.
4. Remove the old key with `api_key remove <key|secret_key_N>` once it is no longer in use.
5. Review public permissions, listening addresses, firewall rules, and available logs.
6. Preserve evidence without disclosing secret values.

### Suspected Backup Tampering or Corruption

1. Suspend automatic cleanup to prevent further deletion.
2. Preserve the archive, `.sha256`/`.sig` sidecars, and logs.
3. Validate the digest and signature using the correct keys.
4. Do not restore an archive whose integrity/authenticity cannot be established.
5. Compare it with a known-good offline copy and document the incident.

### Suspected Host Compromise

Isolate the host from the network, preserve logs and forensic images according to the organisation's procedures, rotate credentials from a clean environment, and only expose the API again after reviewing the installation. Do not rely on process files, logs, or configuration from a compromised host as the sole source of evidence.

---

## 12. Responsible Vulnerability Disclosure

Do not publish keys, personal data, backup archives, tokens, private addresses, or details that could enable exploitation of an active installation in public issues.

To report a vulnerability, use a private channel made available by the maintainers of the official repository:

<https://github.com/afonsoinaciocarreira-cmd/custom-db-manager>

Where possible, include the version/revision reviewed, operating system, minimum reproduction steps, and observed impact, while removing all secrets and real data. Wait for a response before publicly disclosing exploitable details.

---

## 13. Security Statement

Custom DB Manager includes useful operational security mechanisms — two-key authentication, `public` API permissions, HTTPS options, local locking, atomic writes, process management, and backup-protection features. These mechanisms reduce specific classes of risk, but they do not automatically make every deployment secure.

No certification, external audit, standards compliance, guaranteed availability, absolute security, or universal suitability for regulated data is claimed. Each organisation must assess the software, its environment, and complementary controls before using it in production.
