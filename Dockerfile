# cnpg-postgres-batteries-included: CloudNativePG PostgreSQL + PostGIS image
# pre-loaded with the extensions we use everywhere.
#
# Built on top of `ghcr.io/cloudnative-pg/postgis`, which itself extends
# `ghcr.io/cloudnative-pg/postgresql` and pulls packages from PGDG. Adding
# another extension is therefore just one more `apt-get install` line.

ARG BASE=ghcr.io/cloudnative-pg/postgis:18-3-standard-trixie
FROM ${BASE}

ARG PG_MAJOR=18
ARG EXTRA_EXTENSIONS="pg-hint-plan wal2json"

USER root

RUN set -eux; \
    extensions=""; \
    for ext in ${EXTRA_EXTENSIONS}; do \
        extensions="${extensions} postgresql-${PG_MAJOR}-${ext}"; \
    done; \
    apt-get update; \
    apt-get install -y --no-install-recommends ${extensions}; \
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
    rm -rf /var/lib/apt/lists/* /var/cache/* /var/log/*

USER 26
