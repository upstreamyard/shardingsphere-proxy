#!/bin/bash
# Starts ShardingSphere-Proxy through the release's bin/start.sh.
#   (no arguments)      start with the config folder $CONF_DIR (default: conf/)
#   -g, -a ..., -s ...  start with extra start.sh options (-g enables the agent)
#   anything else       run that command instead (e.g. bash)
set -euo pipefail

HOME_DIR=/opt/shardingsphere-proxy
CONF_DIR=${CONF_DIR:-$HOME_DIR/conf}

if [ $# -gt 0 ] && [[ $1 != -* ]]; then
  exec "$@"
fi

# Netty loads its native transport; Java 25 warns about that unless it is allowed.
export JVM_OPTS="--enable-native-access=ALL-UNNAMED ${JVM_OPTS:-}"

# Without its own logback.xml in the config folder, Logback would log everything at DEBUG.
if [ ! -f "$CONF_DIR/logback.xml" ]; then
  export JVM_OPTS="-Dlogback.configurationFile=$HOME_DIR/default-conf/logback.xml ${JVM_OPTS:-}"
fi

if ! grep -qs '^authority:' "$CONF_DIR/global.yaml"; then
  echo "WARNING: no 'authority:' users in $CONF_DIR/global.yaml. ShardingSphere then accepts" \
       "user root with password root as admin from any host. Configure your own users." >&2
fi

args=(-c "$CONF_DIR")
if [ -n "${PORT:-}" ]; then
  args+=(-p "$PORT")
fi

exec "$HOME_DIR/bin/start.sh" "$@" "${args[@]}"
