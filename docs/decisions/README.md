# Architecture Decision Records

Fasty uses Architecture Decision Records (ADRs) to preserve the context and consequences of important technical choices.

## Decision index

| ADR | Decision | Status |
|---|---|---|
| [ADR-0001](ADR-0001-cross-platform-client-framework.md) | Use Flutter for the cross-platform client | Accepted |
| [ADR-0002](ADR-0002-backend-platform.md) | Use ASP.NET Core on the current .NET LTS for the backend | Accepted |
| [ADR-0003](ADR-0003-server-database.md) | Use PostgreSQL as the server database | Accepted |
| [ADR-0004](ADR-0004-client-database-and-local-retention.md) | Use SQLite with Drift and separate attachment caching | Accepted |
| [ADR-0005](ADR-0005-local-first-synchronization.md) | Use an outbox-based local-first synchronization protocol | Accepted |
| [ADR-0006](ADR-0006-sync-transport-and-notifications.md) | Use REST/OpenAPI for durable sync and SignalR for notifications | Accepted |
| [ADR-0007](ADR-0007-modular-monolith-architecture.md) | Use a modular monolith for the backend | Accepted |
| [ADR-0008](ADR-0008-personal-deployment-model.md) | Use Docker Compose and private Tailscale access for personal deployment | Accepted |
| [ADR-0009](ADR-0009-attachment-and-object-storage.md) | Use PostgreSQL metadata with local/S3-compatible object storage | Accepted |
| [ADR-0010](ADR-0010-authentication-and-token-security.md) | Use ASP.NET Core Identity with secure browser cookies and rotating native-client tokens | Accepted |
| [ADR-0011](ADR-0011-initial-logical-data-model.md) | Adopt the initial relational and synchronization data model | Accepted |

## Naming

```text
ADR-0001-short-decision-title.md
```

## Status values

- Proposed
- Accepted
- Superseded
- Deprecated
- Rejected

## ADR template

```markdown
# ADR-0000 — Decision title

- Status: Proposed
- Date: YYYY-MM-DD
- Decision owners: Fasty maintainers

## Context

What problem or constraint requires a decision?

## Decision drivers

- Driver one
- Driver two

## Considered options

1. Option A
2. Option B
3. Option C

## Decision

What was selected and why?

## Consequences

### Positive

- Consequence

### Negative

- Consequence

### Risks

- Risk and mitigation

## Validation

How will the decision be validated in practice?

## References

- Relevant documentation or investigation
```

## Future ADR candidates

New ADRs will be created only when implementation or validated product needs require a significant decision. Likely future topics include:

- public cloud deployment
- public identity provider and enterprise federation
- sharing and collaboration model
- rich-text editor representation
- object-storage provider selection
- change-feed retention and archival
- extraction of any backend module into a service
