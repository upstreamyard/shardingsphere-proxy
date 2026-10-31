<img src="https://upstreamyard.github.io/helm-charts/logo.png" alt="upstreamyard logo" width="120" align="right">

# ShardingSphere-Proxy container image

> **Support:** For help with setup, production issues, or hardened and custom images, email [upstreamyard@proton.me](mailto:upstreamyard@proton.me).

Multi-arch (`amd64`, `arm64`), signed container images for [Apache ShardingSphere-Proxy](https://github.com/apache/shardingsphere), the database proxy that adds sharding, read/write splitting, encryption and masking in front of MySQL and PostgreSQL. Applications connect to it like to a normal MySQL or PostgreSQL server. **The MySQL JDBC driver is included**, so MySQL and MariaDB backends work without building your own image. Made for Kubernetes and Docker Compose.

> Community-maintained by **upstreamyard**. This is not an official Apache ShardingSphere image. Apache ShardingSphere is licensed under Apache-2.0; the included MySQL Connector/J is © Oracle and licensed under GPL-2.0 with the Universal FOSS Exception (see [Licences](#licences)). Apache, Apache ShardingSphere and ShardingSphere are trademarks of the Apache Software Foundation; MySQL is a trademark of Oracle.

| Registry | Image |
|---|---|
| Docker Hub | `upstreamyard/shardingsphere-proxy` |
| GitHub Container Registry | `ghcr.io/upstreamyard/shardingsphere-proxy` |

**Tags:** `latest`, `<major>.<minor>` (e.g. `5.5`), `<version>` (e.g. `5.5.3`, matching the [ShardingSphere releases](https://shardingsphere.apache.org/document/current/en/downloads/)). New releases are built automatically within 24 hours of appearing on Apache's download server.

## At a glance

| | |
|---|---|
| Port | `3307`. Speaks the MySQL protocol, or the PostgreSQL protocol when your backend databases are PostgreSQL |
| Probe | TCP on port 3307. The port opens once the configuration is loaded and all backends are connected; if a backend is unreachable at startup, the proxy exits with code 1 (Docker and Kubernetes restart it) |
| Requires | your MySQL, MariaDB or PostgreSQL databases (tested: MySQL 8.4, MariaDB 11.4, PostgreSQL 17). For more than one proxy instance: ZooKeeper |
| Config | YAML files in `/opt/shardingsphere-proxy/conf` (`global.yaml`, `database-*.yaml`) |
| Drivers | MySQL Connector/J 26.7.0 (added by us), PostgreSQL and openGauss (part of the ShardingSphere release) |
| Runs as | non-root UID `10001`; works with a read-only root filesystem (XA transactions need a writable `/opt/shardingsphere-proxy/logs`) |
| Java | Eclipse Temurin 25 JRE on Ubuntu 24.04; heap is 80% of the container's memory limit |
| Default users | **none configured means `root`/`root` as admin from any host** (ShardingSphere's default). Always configure `authority` users; the container logs a warning otherwise |

**AI agents and coding assistants:** read [`AGENTS.md`](https://github.com/upstreamyard/shardingsphere-proxy/blob/main/AGENTS.md) for deployment rules, and [`llms.txt`](https://github.com/upstreamyard/shardingsphere-proxy/blob/main/llms.txt) for an index of all docs.

## Quick start

The repository contains a working example: the logical database `sharding_db` with a table `t_order` that is split by `user_id` across two MySQL databases, `ds_0` and `ds_1`.

```bash
git clone https://github.com/upstreamyard/shardingsphere-proxy.git
cd shardingsphere-proxy
docker compose up -d
mysql -h 127.0.0.1 -P 3307 -u app -pchange-me-too sharding_db
```

```sql
CREATE TABLE t_order (order_id BIGINT PRIMARY KEY, user_id INT NOT NULL, status VARCHAR(32));
INSERT INTO t_order VALUES (1, 1, 'new'), (2, 2, 'new'), (3, 3, 'paid'), (4, 4, 'paid');
SELECT * FROM t_order;   -- all four rows; in MySQL, ds_0 holds user_id 2 and 4, ds_1 holds 1 and 3
```

Or with plain `docker run`, with your own config folder:

```bash
docker run -d --name shardingsphere-proxy -p 3307:3307 \
  -v "$PWD/conf:/opt/shardingsphere-proxy/conf:ro" \
  upstreamyard/shardingsphere-proxy:5.5
```

## Configuration

ShardingSphere-Proxy is configured with YAML files, not environment variables. Mount a folder with them at `/opt/shardingsphere-proxy/conf`:

- **`global.yaml`**: users (`authority`), the mode (Standalone or Cluster, below) and properties (`props`).
- **`database-<name>.yaml`**: one per logical database: its backend databases (`dataSources`) and rules (sharding, read/write splitting, encryption, masking, shadow).

Start from [`examples/mysql-sharding`](https://github.com/upstreamyard/shardingsphere-proxy/tree/main/examples/mysql-sharding). ShardingSphere's documentation describes all options: [global settings, data sources and rules](https://shardingsphere.apache.org/document/current/en/user-manual/shardingsphere-proxy/yaml-config/). The files hold database passwords, so keep them out of version control; in Kubernetes, our Helm chart stores them in a Secret.

### Users

```yaml
# global.yaml
authority:
  users:
    - user: admin@%        # user@host; % = any host
      password: change-me
      admin: true          # may run DistSQL (ShardingSphere's admin SQL)
    - user: app@%
      password: change-me-too
  privilege:
    type: ALL_PERMITTED
```

Without an `authority` section, ShardingSphere accepts `root` with password `root` as admin from anywhere. The container prints a warning at startup in that case.

### MySQL and MariaDB backends

Use `jdbc:mysql://` URLs for both MySQL and MariaDB servers. Our tests cover MySQL 8.4 and MariaDB 11.4.

```yaml
dataSources:
  ds_0:
    url: jdbc:mysql://mysql:3306/ds_0?sslMode=REQUIRED
    username: root
    password: rootpw
```

ShardingSphere turns TLS off for MySQL connections by default (`useSSL=false`), and MySQL 8's default login method then refuses to connect (`Public Key Retrieval is not allowed`). Add `sslMode=REQUIRED` (or `VERIFY_IDENTITY` with a trusted CA) to the URL, as above.

### PostgreSQL backends

Use `jdbc:postgresql://` URLs. With PostgreSQL backends the proxy speaks the PostgreSQL protocol, so clients connect with `psql` or any PostgreSQL driver on port 3307.

### Standalone and Cluster mode

| | Standalone (default) | Cluster |
|---|---|---|
| Instances | one | any number, sharing their configuration |
| Needs | nothing | ZooKeeper |
| Source of configuration | the files, on every start | the files on the **first** start; after that, ZooKeeper |
| Changes made with DistSQL | lost on restart | kept in ZooKeeper and seen by all instances at once |

Cluster mode, in `global.yaml` (full example: [`examples/cluster-zookeeper`](https://github.com/upstreamyard/shardingsphere-proxy/tree/main/examples/cluster-zookeeper)):

```yaml
mode:
  type: Cluster
  repository:
    type: ZooKeeper
    props:
      namespace: shardingsphere
      server-lists: zookeeper:2181
```

In Cluster mode, ShardingSphere ignores the files completely once ZooKeeper holds a configuration. That includes users and passwords, for which DistSQL has no command. To apply changed files, use a new, empty `namespace`. ShardingSphere then starts from the files again, and changes made with DistSQL in the old namespace are not carried over.

### Environment variables

| Variable | Default | Notes |
|---|---|---|
| `PORT` | – (port from `props.proxy-default-port`, `3307`) | Listen port; also used by the healthcheck |
| `CONF_DIR` | `/opt/shardingsphere-proxy/conf` | Config folder |
| `JVM_OPTS` | – | Extra Java options |
| `CGROUP_MEM_OPTS` | `-XX:InitialRAMPercentage=80.0 -XX:MinRAMPercentage=80.0 -XX:MaxRAMPercentage=80.0` | Heap sizing relative to the memory limit (ShardingSphere's start script default). Give the container a memory limit |

If your config folder has no `logback.xml`, the image uses ShardingSphere's default (INFO to the console).

### More drivers and plugins

Jar files in `/opt/shardingsphere-proxy/ext-lib` are on the classpath, e.g. other JDBC drivers or your own sharding algorithms. Mount a folder there.

### Changes to the ShardingSphere release

The 5.5.3 release contains optional plugins without the libraries they need, and loading them fails. The image removes them while their libraries are missing:

- **Hive**: stops the proxy from starting as soon as any database is configured ([apache/shardingsphere#38306](https://github.com/apache/shardingsphere/issues/38306));
- **Seata AT transactions**: every SQL statement fails ([#38317](https://github.com/apache/shardingsphere/issues/38317));
- **Narayana XA**: fails when selected. The default XA manager, Atomikos, is complete and stays.

## Kubernetes

The recommended way is the Helm chart ([`upstreamyard/helm-charts`](https://github.com/upstreamyard/helm-charts/tree/main/charts/shardingsphere-proxy)):

```bash
helm repo add upstreamyard https://upstreamyard.github.io/helm-charts
helm install shardingsphere-proxy upstreamyard/shardingsphere-proxy -f my-values.yaml
```

Running it yourself:

1. Put `global.yaml` and the `database-*.yaml` files in a Secret (they contain passwords) and mount it at `/opt/shardingsphere-proxy/conf`.
2. Use one replica in Standalone mode, or Cluster mode with ZooKeeper for more.
3. Probe TCP port 3307. The proxy exits if a backend database is unreachable at startup, so expect restarts until the databases are up.
4. Set a memory limit; the heap is 80% of it.
5. On `SIGTERM` the proxy exits within a second and closes open client connections, so add a short `preStop` sleep to let the Service stop sending new connections first.

The container works with `runAsNonRoot: true`, `readOnlyRootFilesystem: true` and all capabilities dropped. With a read-only root filesystem, mount writable volumes at `/tmp` and, for XA transactions (Atomikos writes its transaction log there), at `/opt/shardingsphere-proxy/logs`.

## Verifying images

Images are signed keylessly with [cosign](https://github.com/sigstore/cosign) and include an SBOM and SLSA provenance:

```bash
cosign verify upstreamyard/shardingsphere-proxy:5.5 \
  --certificate-identity-regexp '^https://github.com/upstreamyard/shardingsphere-proxy/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com

docker buildx imagetools inspect upstreamyard/shardingsphere-proxy:5.5 --format '{{ json .SBOM }}'
```

## How it's built

[`.github/workflows/build.yml`](https://github.com/upstreamyard/shardingsphere-proxy/blob/main/.github/workflows/build.yml) runs [`scripts/fetch-release.sh`](https://github.com/upstreamyard/shardingsphere-proxy/blob/main/scripts/fetch-release.sh). It downloads the official ShardingSphere-Proxy binary release from Apache and checks its SHA-512 and its GPG signature against the ShardingSphere KEYS file. Then it builds [`Dockerfile`](https://github.com/upstreamyard/shardingsphere-proxy/blob/main/Dockerfile) for amd64 and arm64.

- **MySQL driver:** downloaded from Maven Central, pinned by SHA-256.
- **Testing:** before publishing, [`scripts/smoke-test.sh`](https://github.com/upstreamyard/shardingsphere-proxy/blob/main/scripts/smoke-test.sh) starts the image against MySQL. It creates a sharded table, checks which database each row landed in, and checks that `root`/`root` is refused.
- **Differences from the official Apache image:**
  - the MySQL driver is included;
  - it runs as non-root;
  - it uses a JRE instead of a full JDK;
  - `tini` is PID 1, and there's a built-in `HEALTHCHECK`;
  - broken optional plugins are removed (above);
  - it warns when no users are configured.

## Licences

| Component | Licence | Licence text in the image | Source code |
|---|---|---|---|
| Apache ShardingSphere | Apache-2.0 | `/licenses/shardingsphere/` (with the licences of its bundled libraries) | [apache/shardingsphere](https://github.com/apache/shardingsphere) at the tag of the image version |
| MySQL Connector/J 26.7.0 | GPL-2.0 with the Universal FOSS Exception 1.0 | `/licenses/mysql-connector-j/` | [mysql/mysql-connector-j, tag 26.7.0](https://github.com/mysql/mysql-connector-j/tree/26.7.0) |
| Ubuntu packages, Eclipse Temurin | various, incl. GPL | `/usr/share/doc/*/copyright`, `/opt/java/openjdk/legal/` | Ubuntu and Adoptium source archives |
| Our packaging (Dockerfile, scripts) | Apache-2.0 | – | this repository |

On request, we provide the source code of the GPL-licensed components in an image, in the exact versions it contains, for three years after we published that image. [Open an issue](https://github.com/upstreamyard/shardingsphere-proxy/issues) to ask for it.

## Support

Issues with the image: [open an issue here](https://github.com/upstreamyard/shardingsphere-proxy/issues). Questions about using ShardingSphere: [ShardingSphere's GitHub discussions](https://github.com/apache/shardingsphere/discussions).
