#!/usr/bin/env bash
# Smoke test for the ShardingSphere-Proxy image: starts MySQL with two databases, runs the
# image with examples/mysql-sharding, then checks that a sharded table works through the
# bundled MySQL driver and that rows land in the right database.
# Usage: scripts/smoke-test.sh <image>   (containers are left running for log inspection;
#        remove them with: docker rm -f ss-smoke smoke-mysql; docker network rm smoke)
set -euo pipefail

IMAGE=${1:?usage: $0 <image>}
CONF="$(cd "$(dirname "$0")/.." && pwd)/examples/mysql-sharding"

docker network create smoke >/dev/null
docker run -d --name smoke-mysql --network smoke --network-alias mysql \
  -e MYSQL_ROOT_PASSWORD=rootpw -e MYSQL_DATABASE=ds_0 mysql:8.4 >/dev/null
for _ in $(seq 1 60); do
  docker exec smoke-mysql mysql -uroot -prootpw -e "CREATE DATABASE IF NOT EXISTS ds_1" >/dev/null 2>&1 && break
  sleep 2
done

docker run -d --name ss-smoke --network smoke \
  -v "$CONF:/opt/shardingsphere-proxy/conf:ro" "$IMAGE" >/dev/null

echo "Waiting for the container healthcheck"
for _ in $(seq 1 60); do
  [ "$(docker inspect -f '{{.State.Health.Status}}' ss-smoke)" = "healthy" ] && break
  if [ "$(docker inspect -f '{{.State.Running}}' ss-smoke)" != "true" ]; then
    echo "Container exited"; docker logs ss-smoke 2>&1 | tail -50; exit 1
  fi
  sleep 2
done
[ "$(docker inspect -f '{{.State.Health.Status}}' ss-smoke)" = "healthy" ] || { echo "Not healthy"; exit 1; }
echo "Healthy"

# SQL through the proxy, with the MySQL client from the MySQL container.
proxy() { docker exec smoke-mysql mysql -h ss-smoke -P 3307 "$@" 2>/dev/null; }
mysql_direct() { docker exec smoke-mysql mysql -uroot -prootpw -N -e "$1" 2>/dev/null; }

proxy -uapp -pchange-me-too sharding_db -e "
  CREATE TABLE t_order (order_id BIGINT PRIMARY KEY, user_id INT NOT NULL, status VARCHAR(32));
  INSERT INTO t_order VALUES (1,1,'new'),(2,2,'new'),(3,3,'paid'),(4,4,'paid');"
[ "$(proxy -uapp -pchange-me-too sharding_db -N -e "SELECT COUNT(*) FROM t_order")" = "4" ] \
  || { echo "Query through the proxy failed"; exit 1; }
[ "$(mysql_direct "SELECT GROUP_CONCAT(user_id ORDER BY user_id) FROM ds_0.t_order")" = "2,4" ] \
  || { echo "Even user_ids are not in ds_0"; exit 1; }
[ "$(mysql_direct "SELECT GROUP_CONCAT(user_id ORDER BY user_id) FROM ds_1.t_order")" = "1,3" ] \
  || { echo "Odd user_ids are not in ds_1"; exit 1; }
echo "Sharded table ok: rows split across ds_0 and ds_1"

# Configured users only: ShardingSphere's root/root fallback must be off.
if proxy -uroot -proot -e "SELECT 1" >/dev/null; then echo "root/root accepted"; exit 1; fi
if proxy -uapp -pwrong -e "SELECT 1" >/dev/null; then echo "Wrong password accepted"; exit 1; fi
echo "Authentication ok"

echo "Smoke test passed"
