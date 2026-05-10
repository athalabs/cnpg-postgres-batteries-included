// Bake recipe for building a CloudNativePG PostgreSQL + PostGIS image with
// the extensions we use across our clusters baked in (pg_hint_plan, wal2json,
// and any others added to `extraExtensions`).
//
// Build all variants for the current matrix:
//
//   docker buildx bake
//
// Build and push to a custom registry:
//
//   registry=ghcr.io/athalabs/cnpg-postgres-batteries-included \
//     docker buildx bake --push
//
// Build a single variant only:
//
//   docker buildx bake batteries-18-3-standard-trixie

variable "registry" {
  default = "ghcr.io/athalabs/cnpg-postgres-batteries-included"
}

// Identifies the commit that produced the image. Set in CI to ${{ github.sha }}.
variable "revision" {
  default = ""
}

variable "pgMajors" {
  default = ["18"]
}

// PostGIS major versions to ship per PG major. Match the upstream
// `cloudnative-pg/postgis-containers` matrix.
variable "postgisMajors" {
  default = ["3"]
}

variable "distros" {
  default = ["trixie"]
}

variable "imageTypes" {
  default = ["standard"]
}

// Extra extensions to install from PGDG. Each name is expanded to
// `postgresql-<PG_MAJOR>-<name>` inside the Dockerfile.
//
// Note on what's already in the base:
//   `pgaudit`, `pgvector`, and `pg-failover-slots` are baked into the
//   upstream cloudnative-pg/postgresql:*-standard variant, which the
//   PostGIS image (and therefore this image) inherits -- don't re-add.
variable "extraExtensions" {
  default = "pg-hint-plan wal2json hypopg pg-qualstats repack"
}

// pg_jsonschema isn't in PGDG; it's built from source in the Rust builder
// stage. Pin tag + matching pgrx version (must match Cargo.toml's pgrx dep
// in pg_jsonschema at this ref).
variable "pgJsonschemaRef" {
  default = "v0.3.4"
}
variable "pgrxVersion" {
  default = "0.16.1"
}

// amd64-only: pg_jsonschema is built from source via pgrx, and the Rust
// compile under arm64 QEMU emulation pushes the build past 60min vs. ~10min
// for amd64 alone. Re-add "linux/arm64" if/when our clusters need it (will
// likely require a self-hosted arm64 runner to stay tolerable).
variable "platforms" {
  default = ["linux/amd64"]
}

now     = timestamp()
authors = "Atha Labs"
url     = "https://github.com/athalabs/cnpg-postgres-batteries-included"

target "default" {
  matrix = {
    pgMajor      = pgMajors
    postgisMajor = postgisMajors
    distro       = distros
    tgt          = imageTypes
  }

  name       = "batteries-${pgMajor}-${postgisMajor}-${tgt}-${distro}"
  dockerfile = "Dockerfile"
  context    = "."
  platforms  = platforms

  args = {
    BASE               = "ghcr.io/cloudnative-pg/postgis:${pgMajor}-${postgisMajor}-${tgt}-${distro}"
    PG_MAJOR           = pgMajor
    EXTRA_EXTENSIONS   = extraExtensions
    PG_JSONSCHEMA_REF  = pgJsonschemaRef
    PGRX_VERSION       = pgrxVersion
  }

  tags = [
    // Stable, human-friendly tags
    "${registry}:${pgMajor}-${postgisMajor}-${tgt}-${distro}",
    "${registry}:${pgMajor}-${tgt}-${distro}",
    // Immutable, timestamped tag for Flux ImagePolicy `numerical` ordering
    "${registry}:${pgMajor}-${postgisMajor}-${tgt}-${distro}-${formatdate("YYYYMMDDhhmm", now)}",
  ]

  attest = [
    "type=provenance,mode=max",
    "type=sbom",
  ]

  annotations = [
    "index,manifest:org.opencontainers.image.created=${now}",
    "index,manifest:org.opencontainers.image.url=${url}",
    "index,manifest:org.opencontainers.image.source=${url}",
    "index,manifest:org.opencontainers.image.version=${pgMajor}-${postgisMajor}",
    "index,manifest:org.opencontainers.image.revision=${revision}",
    "index,manifest:org.opencontainers.image.vendor=${authors}",
    "index,manifest:org.opencontainers.image.title=CNPG Postgres Batteries Included ${pgMajor}/${postgisMajor} (${tgt}, ${distro})",
    "index,manifest:org.opencontainers.image.description=CloudNativePG PostgreSQL ${pgMajor} + PostGIS ${postgisMajor} with extensions: ${extraExtensions}",
    "index,manifest:org.opencontainers.image.documentation=${url}",
    "index,manifest:org.opencontainers.image.authors=${authors}",
    "index,manifest:org.opencontainers.image.licenses=Apache-2.0",
    "index,manifest:org.opencontainers.image.base.name=ghcr.io/cloudnative-pg/postgis:${pgMajor}-${postgisMajor}-${tgt}-${distro}",
  ]

  labels = {
    "org.opencontainers.image.created"       = "${now}"
    "org.opencontainers.image.url"           = "${url}"
    "org.opencontainers.image.source"        = "${url}"
    "org.opencontainers.image.version"       = "${pgMajor}-${postgisMajor}"
    "org.opencontainers.image.revision"      = "${revision}"
    "org.opencontainers.image.vendor"        = "${authors}"
    "org.opencontainers.image.title"         = "CNPG Postgres Batteries Included ${pgMajor}/${postgisMajor} (${tgt}, ${distro})"
    "org.opencontainers.image.description"   = "CloudNativePG PostgreSQL ${pgMajor} + PostGIS ${postgisMajor} with extensions: ${extraExtensions}"
    "org.opencontainers.image.documentation" = "${url}"
    "org.opencontainers.image.authors"       = "${authors}"
    "org.opencontainers.image.licenses"      = "Apache-2.0"
    "org.opencontainers.image.base.name"     = "ghcr.io/cloudnative-pg/postgis:${pgMajor}-${postgisMajor}-${tgt}-${distro}"
  }
}
