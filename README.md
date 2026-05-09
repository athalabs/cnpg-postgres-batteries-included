# cnpg-postgres-batteries-included

[CloudNativePG](https://cloudnative-pg.io/) PostgreSQL + PostGIS container
image with the extensions we use baked in. One image, one tag, no surprises
when a new cluster needs `pg_hint_plan` or `wal2json` and the upstream image
doesn't ship it.

Built on
[`ghcr.io/cloudnative-pg/postgis`](https://github.com/cloudnative-pg/postgis-containers),
which itself extends the official CNPG operand image. Extensions are pulled
from the [PostgreSQL APT repository (PGDG)](https://wiki.postgresql.org/wiki/Apt).

### Bundled on top of the PostGIS image

| Extension | Source | What it gives you |
| --- | --- | --- |
| [`pg_hint_plan`](https://github.com/ossc-db/pg_hint_plan) | PGDG | Query planner hints injected via SQL comments |
| [`wal2json`](https://github.com/eulerto/wal2json) | PGDG | Logical decoding output plugin that emits WAL changes as JSON |
| [`hypopg`](https://github.com/HypoPG/hypopg) | PGDG | Hypothetical indexes — test "would this index help?" without building it |
| [`pg_qualstats`](https://github.com/powa-team/pg_qualstats) | PGDG | Per-predicate statistics; pairs with `hypopg` for index suggestions |
| [`pg_repack`](https://github.com/reorg/pg_repack) | PGDG | Online table/index reorg without `VACUUM FULL`'s exclusive lock |
| [`pg_jsonschema`](https://github.com/supabase/pg_jsonschema) | source (pgrx) | JSON Schema validation as a `CHECK` constraint |

### Already provided by the upstream `standard` variant

These ship with `cloudnative-pg/postgresql:*-standard-*`, so you can
`CREATE EXTENSION` them out of the box without anything from this repo:

- [`pgaudit`](https://github.com/pgaudit/pgaudit) — structured audit logging
- [`pgvector`](https://github.com/pgvector/pgvector) — vector similarity (AI embeddings)
- [`pg_failover_slots`](https://github.com/EnterpriseDB/pg_failover_slots) — preserves logical slots across CNPG failovers

## Tags

Each push to `main` (and the weekly scheduled rebuild) publishes the following
tags to `ghcr.io/athalabs/cnpg-postgres-batteries-included`:

| Tag | Mutability | Use for |
| --- | --- | --- |
| `18-3-standard-trixie` | mutable, latest within `pg-major.postgis-major` | manual pinning |
| `18-standard-trixie` | mutable, latest within `pg-major` | manual pinning |
| `18-3-standard-trixie-YYYYMMDDhhmm` | immutable | Flux `ImagePolicy` (`numerical` ordering on the timestamp suffix) |

Built multi-arch for `linux/amd64` and `linux/arm64`. The build matrix (PG
major, PostGIS major, distro, image type) is configured in
[`docker-bake.hcl`](docker-bake.hcl). Defaults: PG 18, PostGIS 3, Debian
trixie, `standard` variant.

## Use it in a CNPG `Cluster`

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: example-db
  namespace: tenant-a9
spec:
  imageName: ghcr.io/athalabs/cnpg-postgres-batteries-included:18-3-standard-trixie
  instances: 3
  enableSuperuserAccess: true
  postgresql:
    shared_preload_libraries:
      - pg_hint_plan
    parameters:
      # Enable wal2json for logical replication slots
      wal_level: logical
      max_replication_slots: "10"
      max_wal_senders: "10"
  storage:
    size: 8Gi
```

After the cluster is up, create the extensions in each database that needs
them:

```sql
CREATE EXTENSION pg_hint_plan;
-- wal2json is an output plugin, not a SQL extension; it does not need
-- CREATE EXTENSION. Use it via a logical replication slot:
SELECT pg_create_logical_replication_slot('my_slot', 'wal2json');
```

## Use it via `ClusterImageCatalog` (recommended for Flux)

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: ClusterImageCatalog
metadata:
  name: cnpg-batteries
spec:
  images:
    - major: 18
      image: ghcr.io/athalabs/cnpg-postgres-batteries-included:18-3-standard-trixie # {"$imagepolicy": "tenant-a9:cnpg-batteries"}
---
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: example-db
spec:
  imageCatalogRef:
    apiGroup: postgresql.cnpg.io
    kind: ClusterImageCatalog
    name: cnpg-batteries
    major: 18
  instances: 3
  storage:
    size: 8Gi
```

Pair with a Flux `ImageRepository` + `ImagePolicy` keyed on the timestamp
suffix to get automatic updates.

## Sibling: plv8 via ImageVolume

[plv8](https://plv8.github.io/) isn't bundled here — it pulls V8 in as a
build-time dependency, which would inflate every rebuild of this image by
hours. It's published as a separate
[`cnpg-plv8`](https://github.com/athalabs/cnpg-plv8) ImageVolume extension
image and attached on demand:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: example-db
spec:
  imageName: ghcr.io/athalabs/cnpg-postgres-batteries-included:18-3-standard-trixie
  instances: 3
  storage:
    size: 8Gi
  postgresql:
    extensions:
      - name: plv8
        image:
          reference: ghcr.io/athalabs/cnpg-plv8:18-trixie
```

Requires CNPG with the `ImageVolume` feature, Kubernetes 1.35+ (or 1.33–1.34
with the `ImageVolume` feature gate), and PostgreSQL 18+.

## Adding more extensions

**If it's in PGDG:** append to `extraExtensions` in
[`docker-bake.hcl`](docker-bake.hcl). The Dockerfile expands each name to
`postgresql-<PG_MAJOR>-<name>` and `apt-get install`s it. The package must
exist there for every PostgreSQL major in the matrix and every architecture
you build for. Confirm before adding:

```bash
curl -sL https://apt.postgresql.org/pub/repos/apt/dists/trixie-pgdg/main/binary-amd64/Packages.gz \
  | gunzip | grep "^Package: postgresql-18-<name>$"
```

**If it's a Rust extension built with pgrx (like pg_jsonschema):** add another
`FROM rust:1-trixie AS <name>-builder` stage modelled on the existing
`pg-jsonschema-builder` stage, and `COPY --from=...` its `/usr/lib` and
`/usr/share` artefacts into the final image. Pin both the upstream tag and
`cargo-pgrx` to the version specified in the extension's `Cargo.toml`.

**If it's a heavy non-PGDG extension** (e.g. plv8, which drags V8 in as a
build dep), publish it as a separate ImageVolume image instead — see the
sibling [`cnpg-plv8`](https://github.com/athalabs/cnpg-plv8) repo.

## Building locally

```bash
# Build all matrix variants for the host architecture
docker buildx bake --set '*.platform=linux/amd64'

# Build and push to your own registry (multi-arch)
registry=ghcr.io/yourname/cnpg-postgres-batteries-included \
  docker buildx bake --push
```

## CI

[`.github/workflows/bake.yml`](.github/workflows/bake.yml) builds and pushes
to GHCR on:

- Push to `main` (paths-filtered to image sources)
- Weekly schedule (picks up upstream CNPG, PostGIS and PGDG security patches)
- Manual `workflow_dispatch`

Pull requests get a build-only run (no push) for `linux/amd64` to keep CI fast.

## License

[Apache 2.0](LICENSE). PostgreSQL, PostGIS, pg_hint_plan and wal2json retain
their respective upstream licenses.
