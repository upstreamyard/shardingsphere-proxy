# syntax=docker/dockerfile:1.7
# Container image for Apache ShardingSphere-Proxy (https://github.com/apache/shardingsphere)
# Maintained by upstreamyard. Packages the official Apache binary release, unpacked into
# ./upstream by CI after checking its SHA-512 and GPG signature, plus the MySQL JDBC driver.

ARG JAVA_VERSION=25

# -----------------------------
# Prepare: release files and the MySQL driver
# -----------------------------
# Only unpacks platform-independent files (jars, scripts), so it runs natively.
FROM --platform=$BUILDPLATFORM alpine:3.24 AS prepare

# MySQL Connector/J (GPL-2.0 with the Universal FOSS Exception), from Maven Central.
ARG MYSQL_CONNECTOR_VERSION=26.7.0
ARG MYSQL_CONNECTOR_SHA256=69084713593a4aa8d07c383619b9639276f08bccf8faf1c562178147d389b1e1

RUN apk add --no-cache unzip

COPY upstream/ /opt/shardingsphere-proxy/
ADD --chmod=644 --checksum=sha256:${MYSQL_CONNECTOR_SHA256} \
    https://repo1.maven.org/maven2/com/mysql/mysql-connector-j/${MYSQL_CONNECTOR_VERSION}/mysql-connector-j-${MYSQL_CONNECTOR_VERSION}.jar \
    /opt/shardingsphere-proxy/lib/

RUN set -eux; \
    cd /opt/shardingsphere-proxy; \
    # Licences: ShardingSphere's own (with its third-party licences) and the driver's.
    mkdir -p /licenses/shardingsphere /licenses/mysql-connector-j; \
    cp -r LICENSE NOTICE licenses /licenses/shardingsphere/; \
    unzip -q -o lib/mysql-connector-j-*.jar LICENSE README INFO_SRC -d /licenses/mysql-connector-j/; \
    printf 'MySQL Connector/J %s\nSource code: https://github.com/mysql/mysql-connector-j/tree/%s\n' \
      "${MYSQL_CONNECTOR_VERSION}" "${MYSQL_CONNECTOR_VERSION}" > /licenses/mysql-connector-j/SOURCE; \
    # The release's logback.xml uses the deprecated <level value> element, which makes Logback
    # print its own status messages on every start. Same settings, current syntax.
    sed -i -e 's|<root>|<root level="info">|' -e '/<level value="info" \/>/d' conf/logback.xml; \
    # Keep it as the fallback for config folders without a logback.xml.
    mkdir default-conf; cp conf/logback.xml default-conf/; \
    mkdir -p ext-lib logs; \
    rm -f bin/start.bat; \
    # The release includes optional plugins without the libraries they need. Loading them
    # fails: Hive stops the proxy from starting once any database is configured
    # (apache/shardingsphere#38306), Seata AT fails every SQL statement (#38317), and
    # Narayana fails when selected as XA manager. Remove each while its libraries are missing.
    if ! ls lib/hive-jdbc-*.jar >/dev/null 2>&1; then rm -v lib/shardingsphere-*-hive-*.jar; fi; \
    if ! ls lib/seata-*.jar >/dev/null 2>&1; then rm -v lib/shardingsphere-transaction-base-seata-at-*.jar; fi; \
    if ! ls lib/narayana-jta-*.jar lib/jta-*.jar >/dev/null 2>&1; then rm -v lib/shardingsphere-transaction-xa-narayana-*.jar; fi

# -----------------------------
# Runtime
# -----------------------------
FROM eclipse-temurin:${JAVA_VERSION}-jre-noble AS final

ARG SHARDINGSPHERE_VERSION=unknown

RUN apt-get update && apt-get install -y --no-install-recommends tini \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --system --gid 10001 app \
    && useradd --system --uid 10001 --gid app --home-dir /opt/shardingsphere-proxy --no-create-home app

COPY --from=prepare /licenses/ /licenses/
COPY --from=prepare /opt/shardingsphere-proxy/ /opt/shardingsphere-proxy/
COPY docker-entrypoint.sh healthcheck /usr/local/bin/

# Logs and ext-lib are written or mounted at runtime; the rest stays read-only for the app user.
RUN chown app:app /opt/shardingsphere-proxy/logs /opt/shardingsphere-proxy/ext-lib

WORKDIR /opt/shardingsphere-proxy

# IS_DOCKER makes start.sh run Java in the foreground and size the heap from the
# container's memory limit (CGROUP_MEM_OPTS).
ENV IS_DOCKER=true \
    SHARDINGSPHERE_HOME=/opt/shardingsphere-proxy

LABEL org.opencontainers.image.title="shardingsphere-proxy" \
      org.opencontainers.image.description="Apache ShardingSphere-Proxy with the MySQL driver included. Community image by upstreamyard, not an official Apache image." \
      org.opencontainers.image.version="${SHARDINGSPHERE_VERSION}" \
      org.opencontainers.image.licenses="Apache-2.0 AND GPL-2.0-only WITH Universal-FOSS-exception-1.0" \
      org.opencontainers.image.vendor="upstreamyard" \
      org.opencontainers.image.url="https://github.com/upstreamyard/shardingsphere-proxy" \
      org.opencontainers.image.documentation="https://github.com/upstreamyard/shardingsphere-proxy#readme"

EXPOSE 3307

HEALTHCHECK --interval=15s --timeout=5s --start-period=60s --retries=3 CMD ["healthcheck"]

USER 10001:10001

ENTRYPOINT ["/usr/bin/tini", "--", "docker-entrypoint.sh"]
