# cnpg-postgres-batteries-included: CloudNativePG PostgreSQL + PostGIS image
# pre-loaded with the extensions we use everywhere.
#
# Built on top of `ghcr.io/cloudnative-pg/postgis`, which itself extends
# `ghcr.io/cloudnative-pg/postgresql`. Most extras come from PGDG via apt
# (`EXTRA_EXTENSIONS`); pg_jsonschema isn't in PGDG so we build it from
# source via pgrx in a separate builder stage and copy the artefacts in.

ARG PG_MAJOR=18
ARG BASE=ghcr.io/cloudnative-pg/postgis:18-3-standard-trixie

# ---------------------------------------------------------------------------
# Builder: compile pg_jsonschema (Rust + pgrx) against the target PG major.
# ---------------------------------------------------------------------------
ARG PG_JSONSCHEMA_REF=v0.3.4
ARG PGRX_VERSION=0.16.1

FROM rust:1-trixie AS pg-jsonschema-builder

ARG PG_MAJOR
ARG PG_JSONSCHEMA_REF
ARG PGRX_VERSION

ENV DEBIAN_FRONTEND=noninteractive

# PGDG (for postgresql-server-dev-${PG_MAJOR}) + clang/libclang for bindgen.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates curl gnupg \
        build-essential pkg-config git \
        clang libclang-dev llvm-dev \
    ; \
    install -d /usr/share/postgresql-common/pgdg; \
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
        > /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc; \
    . /etc/os-release; \
    echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt ${VERSION_CODENAME}-pgdg main" \
        > /etc/apt/sources.list.d/pgdg.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        "postgresql-${PG_MAJOR}" \
        "postgresql-server-dev-${PG_MAJOR}" \
    ; \
    rm -rf /var/lib/apt/lists/*

# Match cargo-pgrx version to the pgrx version in pg_jsonschema's Cargo.toml.
RUN cargo install --locked "cargo-pgrx@${PGRX_VERSION}"

# Initialise pgrx against the system PG (avoids pgrx downloading + rebuilding
# its own postgres) and stash logs out of the build cache.
RUN cargo pgrx init "--pg${PG_MAJOR}=/usr/lib/postgresql/${PG_MAJOR}/bin/pg_config"

WORKDIR /src
RUN git clone --depth 1 --branch "${PG_JSONSCHEMA_REF}" \
    https://github.com/supabase/pg_jsonschema.git .

# `cargo pgrx package` writes a deb-style tree under
# target/release/pg_jsonschema-pg${PG_MAJOR}/. We hoist that tree to /pkg
# so the final stage can do a deterministic COPY.
RUN set -eux; \
    cargo pgrx package --features "pg${PG_MAJOR}" --pg-config "/usr/lib/postgresql/${PG_MAJOR}/bin/pg_config"; \
    mv "target/release/pg_jsonschema-pg${PG_MAJOR}" /pkg

# ---------------------------------------------------------------------------
# Final image: postgis + apt extras + pg_jsonschema artefacts.
# ---------------------------------------------------------------------------
FROM ${BASE}

ARG PG_MAJOR
ARG EXTRA_EXTENSIONS="pg-hint-plan wal2json hypopg pg-qualstats repack"

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

# pg_jsonschema artefacts (built above; pgrx writes a deb-style /usr tree).
COPY --from=pg-jsonschema-builder /pkg/usr/lib/postgresql/${PG_MAJOR}/lib/    /usr/lib/postgresql/${PG_MAJOR}/lib/
COPY --from=pg-jsonschema-builder /pkg/usr/share/postgresql/${PG_MAJOR}/extension/ /usr/share/postgresql/${PG_MAJOR}/extension/

USER 26
