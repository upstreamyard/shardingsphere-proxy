# AGENTS.md

Instructions for AI agents and coding assistants working with this repository or deploying the image it publishes.

## Image facts

| Key | Value |
|---|---|
| Image | `upstreamyard/shardingsphere-proxy` (Docker Hub), `ghcr.io/upstreamyard/shardingsphere-proxy` |
| Tags | `<version>` (e.g. `5.5.3`), `<major>.<minor>` (e.g. `5.5`), `latest` |
| Platforms | `linux/amd64`, `linux/arm64` |
| Port | `3307`: MySQL protocol, or PostgreSQL protocol when the backends are PostgreSQL |
| Probe | TCP on the port (built-in `HEALTHCHECK` uses `healthcheck`) |
| User | non-root, UID/GID `10001`; read-only root filesystem works with writable `/tmp` and, for XA transactions, `/opt/shardingsphere-proxy/logs` (Atomikos transaction log) |
| Entrypoint | `tini -- docker-entrypoint.sh`; arguments starting with `-` go to ShardingSphere's `start.sh`, anything else is run as a command |
| Config | YAML files in `/opt/shardingsphere-proxy/conf`: `global.yaml` (users, mode, props) and `database-*.yaml` (data sources, rules) |
| Environment | `PORT`, `CONF_DIR`, `JVM_OPTS`, `CGROUP_MEM_OPTS` (heap: 80% of the memory limit by default) |
| Drivers | MySQL Connector/J (added by this image, in `lib/`), PostgreSQL, openGauss; more in `/opt/shardingsphere-proxy/ext-lib` |
| ShardingSphere project | https://github.com/apache/shardingsphere (Apache-2.0) |

## Deploying the image

Rules that avoid the common failures:

- **Users:** always set `authority.users` in `global.yaml`. Without it, ShardingSphere accepts `root`/`root` as admin from any host (the container logs a warning).
- **MySQL and MariaDB URLs:** `jdbc:mysql://host:3306/db?sslMode=REQUIRED`. Without TLS, MySQL 8 refuses the login (`Public Key Retrieval is not allowed`), because ShardingSphere sets `useSSL=false` by default. Don't use `jdbc:mariadb://` URLs: ShardingSphere 5.5.3 fails at startup with a NullPointerException for the MariaDB database type; the MySQL driver works with MariaDB servers.
- **Backends must be reachable at startup:** otherwise the proxy exits with code 1 and is restarted by Docker or Kubernetes.
- **Standalone mode (default):** one instance; configuration comes from the files on every start, and changes made with DistSQL are lost on restart.
- **Cluster mode (several instances):** needs ZooKeeper (`mode.type: Cluster`, `repository.type: ZooKeeper`). The files only seed ZooKeeper on the first start; afterwards ZooKeeper wins, including users and passwords. To apply changed files, set a new `mode.repository.props.namespace`.
- **Memory:** set a memory limit; the heap is 80% of it (`CGROUP_MEM_OPTS`).
- **Shutdown:** `SIGTERM` stops the proxy within a second and closes client connections; use a short `preStop` sleep in Kubernetes.
- **Removed plugins:** Hive, Seata AT and Narayana XA are removed from 5.5.3 because their libraries are missing from the release.

Ready-to-use manifests:

- Docker Compose: [`docker-compose.yml`](docker-compose.yml) with [`examples/mysql-sharding`](examples/mysql-sharding)
- Cluster mode config: [`examples/cluster-zookeeper`](examples/cluster-zookeeper)
- Kubernetes: Helm chart `upstreamyard/shardingsphere-proxy` from `https://upstreamyard.github.io/helm-charts` (also `oci://ghcr.io/upstreamyard/charts/shardingsphere-proxy`), documented in https://github.com/upstreamyard/helm-charts/tree/main/charts/shardingsphere-proxy

Verify a deployment:

```bash
mysql -h HOST -P 3307 -u USER -p -e "SHOW DATABASES"
```

## Working on this repository

Layout:

- `Dockerfile`: packages the official binary release, which `scripts/fetch-release.sh` downloads, verifies (SHA-512 and GPG) and unpacks into `./upstream/` (git-ignored); adds the MySQL driver, pinned by version and SHA-256
- `docker-entrypoint.sh`: starts `bin/start.sh` with the config folder; `healthcheck`: TCP check
- `examples/`: config used by `docker-compose.yml` and the smoke test
- `scripts/smoke-test.sh`: the test CI runs before publishing; run it locally too
- `.github/workflows/build.yml`: resolves the latest release from Apache's download server, builds, smoke-tests, pushes multi-arch, signs and syncs the Docker Hub README

Build and test locally:

```bash
scripts/fetch-release.sh 5.5.3
docker build -t shardingsphere-proxy:dev --build-arg SHARDINGSPHERE_VERSION=5.5.3 .
scripts/smoke-test.sh shardingsphere-proxy:dev
docker rm -f ss-smoke smoke-mysql && docker network rm smoke
```

Rules:

- Never push to `main`. Create a branch and open a pull request into `main`.
- Do not modify ShardingSphere's files beyond what the `Dockerfile` does now; report ShardingSphere bugs to the user rather than filing them.
- **MySQL driver updates:** change `MYSQL_CONNECTOR_VERSION` and `MYSQL_CONNECTOR_SHA256` in the `Dockerfile`, and the version in `README.md` (At a glance, Licences). Dependabot does not track it. The driver's licence text and source link are written to `/licenses/mysql-connector-j/` by the build.
- When ShardingSphere fixes the packaging of the removed plugins, the `Dockerfile` keeps them automatically (it only removes them while their libraries are missing); update the README section then.
- Keep the image non-root with UID `10001`, and keep `HEALTHCHECK` and the OCI labels.
- When the port, the probe or the config layout change, update `README.md`, this file and `llms.txt` in the same pull request.
- The workflow must pass `actionlint` (`docker run --rm -v "$PWD":/repo -w /repo rhysd/actionlint:latest`).
- `README.md` is also the Docker Hub description, so keep it under 25,000 characters.
