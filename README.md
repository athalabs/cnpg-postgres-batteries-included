# cnpg-postgres-batteries-included

[CloudNativePG](https://cloudnative-pg.io/) PostgreSQL + PostGIS container
image with the extensions we use baked in. One image, one tag, no surprises
when a new cluster needs `pg_hint_plan` or `wal2json` and the upstream image
doesn't ship it.

Currently bundled on top of the upstream PostGIS image:

- [`pg_hint_plan`](https://github.com/ossc-db/pg_hint_plan) — query planner
  hints injected via SQL comments.
- [`wal2json`](https://github.com/eulerto/wal2json) — logical decoding output
  plugin that emits WAL changes as JSON.

Built on
[`ghcr.io/cloudnative-pg/postgis`](https://github.com/cloudnative-pg/postgis-containers),
which itself extends the official CNPG operand image. Extensions are pulled
from the [PostgreSQL APT repository (PGDG)](https://wiki.postgresql.org/wiki/Apt).

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

## Adding more extensions

Append to `extraExtensions` in [`docker-bake.hcl`](docker-bake.hcl). The
Dockerfile expands each name to `postgresql-<PG_MAJOR>-<name>` and
`apt-get install`s it from PGDG, so the package must exist there for every
PostgreSQL major in the matrix and every architecture you build for.

Confirm a candidate is available before adding it:

```bash
curl -sL https://apt.postgresql.org/pub/repos/apt/dists/trixie-pgdg/main/binary-amd64/Packages.gz \
  | gunzip | grep "^Package: postgresql-18-<name>$"
```

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
