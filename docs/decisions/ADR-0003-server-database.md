# ADR-0003 — Use PostgreSQL as the server database

- Status: Accepted
- Date: 2026-07-22
- Decision owners: Fasty maintainers

## Context

Fasty requires a server-side database for authenticated user accounts, notes, synchronization metadata, deleted-record tombstones, device sessions, revision history, and future organization or enterprise features.

The database must support reliable transactions because a note change and its associated synchronization record must either both succeed or both fail. It must also run well on Linux and in containers for the initial Lubuntu deployment, while remaining portable to managed cloud services later.

## Decision drivers

- Strong transactional guarantees
- Reliable constraints and relational modelling
- Efficient incremental synchronization queries
- Linux and Docker support
- Straightforward self-hosting on modest hardware
- Mature .NET and Entity Framework Core support
- Open licensing with no production licensing cost
- Availability across major cloud providers
- Backup, restore, replication, and observability tooling
- Support for structured data with limited flexible metadata
- Long-term enterprise credibility
- Low risk of vendor lock-in

## Considered options

1. PostgreSQL
2. Microsoft SQL Server
3. MySQL or MariaDB
4. MongoDB
5. SQLite as the server database
6. Distributed SQL databases such as CockroachDB

## Decision

Fasty will use PostgreSQL as its authoritative server database.

The backend will access PostgreSQL through Entity Framework Core using the Npgsql provider. Database migrations will be version controlled and applied through an explicit deployment process.

Fasty will track a supported PostgreSQL major release and keep its current minor release updated. The project will not permanently bind itself to one major version in architecture documentation.

For the first deployment, PostgreSQL will run as a dedicated container with a persistent volume on the Lubuntu server. Later environments may use managed PostgreSQL without changing the application-domain model.

## Rationale

### Transactional synchronization model

Fasty needs to commit business data and synchronization metadata atomically. PostgreSQL provides the relational transaction semantics, constraints, indexes, and concurrency controls needed for operations such as:

- writing a note revision and a server change sequence in one transaction;
- enforcing unique client operation identifiers for idempotency;
- recording a deletion tombstone without physically losing synchronization history;
- updating device cursors safely;
- applying authorization through ownership and future workspace relationships.

### Data model fit

Fasty's core entities are naturally relational:

- users own notes;
- devices and sessions belong to users;
- notes may belong to folders or workspaces;
- notes have revisions and synchronization events;
- future enterprise users belong to organizations and roles.

A relational schema allows these relationships and invariants to be enforced by the database rather than only by application code.

PostgreSQL JSONB may be used selectively for metadata that is genuinely flexible, but primary business entities and queryable synchronization fields will use explicit relational columns.

### Portability and cost

PostgreSQL is free and open source under a permissive license. It can run locally, in containers, on a VPS, or through managed services from multiple providers. This reduces commercial licensing risk and avoids tying Fasty to one hosting vendor.

### Operational maturity

PostgreSQL provides mature backup and restore tools, physical and logical replication capabilities, point-in-time recovery options, extensions, monitoring integrations, and a broad operational ecosystem.

These features are not all required for the personal MVP, but they provide a credible path toward a production service.

## Alternatives

### Microsoft SQL Server

SQL Server has excellent .NET integration, strong tooling, mature transactions, and enterprise adoption. It also supports Linux and containers.

It was not selected because:

- PostgreSQL avoids production licensing complexity and cost;
- PostgreSQL is more neutral across hosting providers;
- the initial Lubuntu deployment benefits from a lighter open-source operational model;
- Fasty does not require SQL Server-specific capabilities.

SQL Server remains a technically valid database for a future customer-specific deployment if enterprise requirements demand it, but it will not be the canonical database.

### MySQL or MariaDB

MySQL and MariaDB are mature relational databases with broad hosting support and strong performance.

They were not selected because PostgreSQL offers a stronger overall fit for Fasty's expected use of transactional constraints, advanced queries, flexible JSONB metadata, and future synchronization or analytical needs. Choosing MySQL would not provide a decisive operational or product advantage.

### MongoDB

MongoDB offers a flexible document model, transactions, and change streams.

It was not selected because:

- Fasty's core model is relational rather than document-isolated;
- schema flexibility is not a primary requirement;
- synchronization correctness still requires explicit application-level ordering, idempotency, and conflict rules;
- change streams would not replace Fasty's durable synchronization API;
- relational constraints are valuable for users, devices, notes, revisions, and future organizations.

MongoDB may be appropriate for products whose data is naturally aggregate-oriented and highly variable, but that is not currently Fasty's domain.

### SQLite as the server database

SQLite is excellent for local device persistence and may be selected separately for the client.

It was rejected as the authoritative server database because the backend needs concurrent access, server-oriented operations, scalable backups, connection management, and a future path to multi-user production deployment.

### Distributed SQL databases

Distributed SQL systems can provide multi-region resilience and horizontal scale.

They were rejected for the initial architecture because they add operational and conceptual complexity before Fasty has usage that requires them. PostgreSQL is sufficient for the personal, beta, and likely early commercial stages.

## Data modelling rules

- Use UUIDs for externally visible aggregate identifiers.
- Use UTC timestamps for recorded times.
- Do not use client clocks as the authoritative synchronization order.
- Use a server-generated monotonic sequence or equivalent durable cursor for incremental synchronization.
- Enforce idempotency with unique client operation identifiers.
- Use foreign keys, unique constraints, and check constraints for important invariants.
- Represent deletions required for synchronization with tombstones before eventual retention cleanup.
- Keep note revision history separate from the current note projection when history is introduced.
- Do not store binary attachments directly in normal note rows; use object storage later and retain metadata in PostgreSQL.
- Use JSONB only where flexibility is intentional and documented.
- Avoid database triggers for core business workflows unless an ADR justifies them.
- Treat migrations as reviewed production code.

## Operational rules

- PostgreSQL must not be exposed directly to the public internet.
- Only the backend service may connect to the production database.
- Credentials must come from environment-specific secret management.
- The database must use persistent storage outside the disposable container filesystem.
- Automated backups must be configured before Fasty becomes the primary personal notes system.
- Restoration must be tested, not merely assumed from successful backup creation.
- Minor security and bug-fix releases should be applied regularly.
- Major upgrades require a documented rehearsal and rollback plan.
- Connection pooling and database limits must be appropriate for the Lubuntu hardware.

## Consequences

### Positive

- Strong fit for synchronization transactions and relational constraints
- No commercial production licence fee
- Excellent Linux and container support
- Mature Entity Framework Core integration
- Straightforward path from self-hosted to managed cloud PostgreSQL
- Rich indexing, query, JSONB, replication, and backup capabilities
- Lower vendor lock-in than a provider-specific database service

### Negative

- Fasty is responsible for database administration during self-hosting
- Major PostgreSQL upgrades require deliberate migration planning
- JSONB flexibility could be misused instead of designing clear schemas
- Production operation still requires backups, monitoring, patching, and capacity management

### Risks and mitigations

- Risk: The old laptop suffers disk failure.
  - Mitigation: encrypted automated backups must be copied to a separate physical or remote location.
- Risk: Database schema becomes tightly coupled to EF Core implementation details.
  - Mitigation: review migrations and keep domain concepts explicit.
- Risk: Unbounded synchronization and revision tables grow indefinitely.
  - Mitigation: define retention, indexing, pagination, and archival policies before public release.
- Risk: PostgreSQL is treated as the client synchronization protocol.
  - Mitigation: clients communicate only with the backend API; database internals remain private.
- Risk: Advanced PostgreSQL-specific features create unnecessary lock-in.
  - Mitigation: use standard relational features by default and document deliberate PostgreSQL-specific usage.

## Validation

The initial technical proof of concept must demonstrate:

1. PostgreSQL runs through Docker Compose on the Lubuntu-compatible development environment.
2. ASP.NET Core connects through Npgsql and EF Core.
3. Migrations create and update the schema reproducibly.
4. A note and its synchronization change record commit atomically.
5. Duplicate client operation IDs are rejected or safely return the prior result.
6. Incremental changes can be queried efficiently using an indexed server cursor.
7. A database backup can be restored into a clean PostgreSQL instance.
8. Integration tests run against a real PostgreSQL instance rather than an incompatible in-memory substitute.

## Reconsideration triggers

Revisit this decision if:

- verified scale requirements exceed what a well-operated PostgreSQL deployment can support;
- a customer requires a different database for a dedicated enterprise deployment;
- multi-region active-active writes become a proven product requirement;
- PostgreSQL operation becomes the dominant product risk;
- a managed service constraint materially changes portability or cost assumptions.

## References

- PostgreSQL licence: https://www.postgresql.org/about/licence/
- PostgreSQL versioning policy: https://www.postgresql.org/support/versioning/
- PostgreSQL logical decoding: https://www.postgresql.org/docs/current/logicaldecoding.html
- SQL Server Linux containers: https://learn.microsoft.com/en-us/sql/linux/containers/deploy
- MongoDB transactions: https://www.mongodb.com/docs/manual/core/transactions/
- MongoDB change streams: https://www.mongodb.com/docs/manual/changestreams/
- MySQL replication: https://dev.mysql.com/doc/refman/8.4/en/replication.html
