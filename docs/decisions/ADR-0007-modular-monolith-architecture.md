# ADR-0007 — Use a modular monolith for the backend

- Status: Accepted
- Date: 2026-07-22
- Decision owners: Fasty maintainers

## Context

Fasty needs clear internal boundaries for identity, notes, synchronization, attachments, notifications, and future administration. At the same time, the project will initially be developed and operated by one maintainer and deployed on modest infrastructure, including an always-on Lubuntu laptop.

A microservice architecture would introduce distributed deployment, service discovery, cross-service authorization, network failure handling, message delivery guarantees, observability overhead, duplicated configuration, and more complex local development before Fasty has validated product demand.

A single undifferentiated application would be operationally simple but could become difficult to maintain if all features share infrastructure types, database models, and internal implementation details.

## Decision drivers

- Keep development and deployment practical for one maintainer.
- Preserve clear business and ownership boundaries.
- Support transactional note and synchronization operations.
- Run efficiently on modest personal infrastructure.
- Keep local development reproducible.
- Allow future extraction of a module only when evidence justifies it.
- Avoid both premature microservices and a tightly coupled monolith.

## Considered options

1. Modular monolith in one deployable backend process
2. Traditional layered monolith without explicit modules
3. Microservices from the beginning
4. Serverless functions per capability

## Decision

Fasty will begin as a modular monolith deployed as one ASP.NET Core application.

The application will contain explicit business modules. Each module owns its application behaviour, domain rules, persistence mappings, and public internal contracts.

The initial logical modules are:

- Identity
- Notes
- Synchronization
- Attachments
- Notifications
- Administration, when needed

Cross-cutting infrastructure may include:

- Database connection and migrations
- Authentication middleware
- Logging and telemetry
- Time and identifier abstractions
- Object-storage adapter
- Email adapter
- Background-work coordination

Cross-cutting infrastructure must not become a location for business rules.

## Initial solution structure

The exact number of projects may evolve during the proof of concept, but the intended structure is:

```text
backend/
├── Fasty.sln
├── src/
│   ├── Fasty.Api/
│   ├── Fasty.AppHost/                 # optional future local orchestration host
│   ├── BuildingBlocks/
│   │   ├── Fasty.BuildingBlocks.Application/
│   │   ├── Fasty.BuildingBlocks.Domain/
│   │   └── Fasty.BuildingBlocks.Infrastructure/
│   └── Modules/
│       ├── Identity/
│       │   ├── Fasty.Identity.Application/
│       │   ├── Fasty.Identity.Domain/
│       │   ├── Fasty.Identity.Infrastructure/
│       │   └── Fasty.Identity.Contracts/
│       ├── Notes/
│       │   ├── Fasty.Notes.Application/
│       │   ├── Fasty.Notes.Domain/
│       │   ├── Fasty.Notes.Infrastructure/
│       │   └── Fasty.Notes.Contracts/
│       ├── Synchronization/
│       │   ├── Fasty.Synchronization.Application/
│       │   ├── Fasty.Synchronization.Domain/
│       │   ├── Fasty.Synchronization.Infrastructure/
│       │   └── Fasty.Synchronization.Contracts/
│       ├── Attachments/
│       └── Notifications/
└── tests/
    ├── UnitTests/
    ├── IntegrationTests/
    ├── ArchitectureTests/
    └── EndToEndTests/
```

This is an intended boundary model, not a requirement to create every project before it has useful code. Fasty will avoid empty projects and unnecessary interfaces.

## Module ownership

### Identity

Owns:

- User identities
- Password or external-login credentials
- Sessions and refresh tokens
- Registered devices
- Account lifecycle

Does not own note authorization rules beyond providing authenticated identity and account status.

### Notes

Owns:

- Note entities
- Note revisions
- Titles and content
- Pinning, archival, and deletion state
- Future tags and notebooks
- Note-level authorization rules

### Synchronization

Owns:

- Client operation idempotency records
- Server change feed
- Synchronization cursors
- Conflict records
- Bootstrap and incremental synchronization workflows
- Deletion tombstone delivery

The Notes and Synchronization modules must collaborate transactionally without exposing database entities to one another.

### Attachments

Owns:

- Attachment metadata
- Upload lifecycle
- Content hashes and sizes
- Object-storage keys
- Download authorization
- Cache-retention policy metadata

The binary content is stored outside PostgreSQL in object storage or a compatible local storage implementation.

### Notifications

Owns:

- SignalR change-availability notifications
- Future email and push notification coordination
- Delivery attempts when durable delivery is required

SignalR notifications are not the durable source of synchronization truth.

## Dependency rules

- Domain projects do not depend on ASP.NET Core, EF Core, SignalR, or storage SDKs.
- Application projects define use cases and depend on domain types and narrow abstractions.
- Infrastructure projects implement persistence and external adapters.
- API endpoints call application use cases; they do not implement business rules.
- A module must not reference another module's Infrastructure or Domain project directly.
- Cross-module access occurs through explicit Contracts projects or application-level interfaces.
- EF Core entities and DbContext types remain internal to the owning module where practical.
- Shared building blocks contain only genuinely generic concepts.
- A type is not moved to shared code merely because two modules currently use similar names.

## Database boundaries

The modular monolith may initially use one PostgreSQL database and one physical deployment.

Each module should have clear table ownership. Schema separation may be used, for example:

```text
identity.*
notes.*
sync.*
attachments.*
notifications.*
```

Whether the first implementation uses separate PostgreSQL schemas or consistent table prefixes will be validated during scaffolding.

Modules must not update another module's tables through ad hoc SQL or direct DbSet access.

A single application transaction may span multiple module-owned tables when required for correctness, especially when a note mutation and synchronization change record must commit atomically.

## Internal communication

Prefer direct in-process calls through explicit interfaces or commands for work that must complete synchronously.

Use in-process domain or integration events when they reduce coupling, but do not introduce a message broker for the personal MVP.

Events that represent required durable follow-up work must be persisted transactionally before asynchronous processing. In-memory event delivery alone is not sufficient for critical operations.

## API organization

Public HTTP endpoints may be organized by feature or module:

```text
/api/v1/auth/*
/api/v1/notes/*
/api/v1/sync/*
/api/v1/attachments/*
```

The public API contract must not expose internal domain entities or EF Core models directly.

## Testing requirements

The backend will include:

- Unit tests for domain and application rules
- Integration tests with real PostgreSQL
- Architecture tests enforcing forbidden project dependencies
- End-to-end tests crossing API, database, and synchronization boundaries
- Module-specific tests for authorization and ownership

Architecture tests should detect at least:

- Domain depending on Infrastructure
- One module directly referencing another module's Infrastructure
- API endpoints depending on EF Core DbContext types
- Business rules implemented only in controllers or endpoint handlers

## When extraction may be justified

A module may be considered for extraction into a separate deployable service only when there is measurable evidence such as:

- Independent scaling requirements that cannot be handled within the monolith
- A distinct security or regulatory boundary
- A separate operational or release cadence
- A specialized runtime or technology requirement
- A team ownership boundary that causes meaningful coordination problems
- Resource isolation requirements for expensive media processing
- Availability requirements that differ materially from the main application

Extraction requires a new ADR that documents data ownership, communication, consistency, deployment, observability, security, and migration implications.

## Consequences

### Positive

- One deployment unit is practical for Lubuntu and early cloud hosting.
- Local development and integration testing remain straightforward.
- Cross-module database transactions remain possible.
- Business boundaries are documented and enforceable.
- The project avoids distributed-system complexity before it is justified.
- Future service extraction remains possible from clearer seams.

### Negative

- A failure in the application process may affect all modules.
- The entire backend is deployed for every backend release.
- Poor discipline could allow module boundaries to erode over time.
- A single database can tempt developers to bypass module contracts.

### Risks and mitigations

- Risk: Creating excessive projects and abstractions slows delivery.
  - Mitigation: Create a project or interface only when it protects a real boundary or supports testing.
- Risk: Modules become coupled through shared database access.
  - Mitigation: Enforce ownership with architecture tests and code review.
- Risk: The shared building-blocks area becomes a dumping ground.
  - Mitigation: Require a clear cross-module invariant before moving code there.
- Risk: Future extraction is assumed to be effortless.
  - Mitigation: Treat extraction as a migration project requiring its own ADR.

## Validation

The technical proof of concept must demonstrate:

1. Identity, Notes, and Synchronization are represented as explicit modules.
2. A note mutation and synchronization change record commit atomically.
3. API endpoints do not contain domain business logic.
4. A module cannot directly depend on another module's Infrastructure project.
5. Integration tests run against PostgreSQL in a reproducible environment.
6. The full backend runs as one containerized deployable application.
7. Module boundaries can be explained through a component diagram.

## References

- ADR-0002 — Backend platform
- ADR-0003 — Server database
- ADR-0005 — Local-first synchronization
- ADR-0006 — Synchronization transport and notifications
