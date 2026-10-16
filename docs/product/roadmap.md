# Fasty — Product Roadmap

## Roadmap principles

- Synchronization reliability comes before advanced editor features.
- The client remains local-first at every stage.
- Text notes remain available offline after synchronization.
- Large synchronized attachments may use an evictable local cache.
- The personal deployment must not constrain future cloud deployment.
- Each phase must have observable completion criteria.
- Features are added only after the previous phase is usable and tested.

## Phase 0 — Product and architecture foundation

### Goals

Define what Fasty is, what the first release includes, and how technical decisions will be recorded.

### Deliverables

- Product vision
- Initial scope and explicit non-goals
- Functional and non-functional requirements
- MVP acceptance scenarios
- Technology evaluation
- Architecture Decision Records
- Initial threat model
- Synchronization specification
- Initial data model
- C4 architecture diagrams
- Repository and contribution standards

### Exit criteria

- MVP boundaries are clear.
- Major technology choices are documented.
- Synchronization invariants are written before implementation.
- The initial architecture can be explained using diagrams.

## Phase 1 — End-to-end technical proof of concept

### Goals

Prove that the selected client, API, and database technologies work together.

### Deliverables

- Minimal Flutter client
- Minimal ASP.NET Core API
- PostgreSQL development database
- Basic account authentication
- Create, read, update, and delete one plain-text note
- OpenAPI contract
- Containerized local backend

### Exit criteria

- Two authenticated clients can access the same server-side note.
- The development environment can be created from documentation.
- Automated builds and basic tests run in CI.

## Phase 2 — Local-first synchronization

### Goals

Make the client independently usable and implement reliable synchronization.

### Deliverables

- Local SQLite database
- Local repository layer
- Outbox for pending operations
- Incremental server change feed
- Idempotent push operations
- Deletion tombstones
- Retry policy
- Conflict detection and preservation
- Synchronization status
- Automated synchronization tests

### Exit criteria

- Offline creation, editing, and deletion work.
- Reconnection synchronizes changes without duplicates.
- Conflicting edits do not silently destroy content.
- A client can synchronize after an extended offline period.
- Synchronized note text remains searchable while the backend is unavailable.

## Phase 3 — Personal alpha on Lubuntu

### Goals

Deploy Fasty on the always-on Lubuntu laptop and use it in daily life.

### Deliverables

- Docker Compose deployment
- Private remote access
- Reverse proxy and encrypted transport
- Automated PostgreSQL backups
- Tested restoration instructions
- Health checks
- Structured logs
- Android, Windows, and web builds

### Exit criteria

- Fasty is used regularly from at least two devices.
- The backend survives routine restarts.
- Backup and restoration succeed in a clean environment.
- Operational issues are documented as GitHub issues.

## Phase 4 — Personal product quality

### Goals

Turn the functional alpha into a polished and dependable personal notes product.

### Candidate features

- Search
- Pinned notes
- Tags or notebooks
- Markdown or limited rich text
- Easier note editor on Android and desktop
  - Visible checklist and formatting controls; no need to type `- [ ]` or `- [x]`
  - Interactive task completion, automatic list continuation, and an easy way to exit lists
  - Bold, italic, headings, bulleted/numbered lists, links, and undo/redo
  - Touch-friendly controls with the Android keyboard open; mouse and keyboard support on desktop
  - Preserve existing content, offline editing, sync, and task-related behavior
  - Candidate improvement: easier note editing across Android and desktop; not scheduled for the portfolio snapshot.
- Checklists
- Note history
- Export
- Dark mode
- Accessibility improvements
- Better synchronization diagnostics
- Attachments and media content
  - Images
  - Voice notes and audio recordings
  - PDFs
  - Office documents and other files
  - Generated previews and thumbnails
- Attachment cache management and offline pinning
- Reminders

### Exit criteria

- The application is comfortable for daily use.
- Performance is measured with a representative note collection.
- Critical flows have automated end-to-end coverage.
- Data export is usable outside Fasty.
- Synchronized attachment binaries can be evicted and downloaded again without data loss.

## Phase 5 — Public beta preparation

### Goals

Move from personal infrastructure to production-grade hosted infrastructure.

### Deliverables

- Managed or professionally operated PostgreSQL
- Hosted application containers
- Object storage
- Transactional email
- Public domain and HTTPS
- Monitoring and alerting
- Rate limiting
- Abuse protections
- Privacy policy and terms
- Account deletion and data export workflows
- Release and rollback procedures

### Exit criteria

- Production and personal environments are separated.
- Deployments and rollbacks are automated.
- Security review findings are addressed.
- Operational responsibilities and costs are understood.

## Phase 6 — Enterprise discovery

### Goals

Validate actual enterprise demand before implementing enterprise complexity.

### Areas to investigate

- Organizations and workspaces
- Role-based access control
- Shared notes and collaboration
- Audit logs
- SSO using OpenID Connect or SAML
- SCIM provisioning
- Data retention controls
- Regional data storage
- Customer-managed keys
- Self-hosted deployment
- Administrative reporting
- Support commitments and service objectives
- Compliance expectations

### Exit criteria

- Enterprise features are based on validated user needs.
- Tenant isolation and authorization are formally reviewed.
- Commercial, legal, operational, and support implications are documented.

## Idea parking lot

The following ideas are intentionally not scheduled:

- AI-assisted organization and summaries
- OCR and document scanning
- Handwriting recognition
- Browser clipping
- Public notes
- Plugin marketplace
- Real-time collaborative text editing
- CRDT-based editor
- Calendar and email integrations

They may be reconsidered after the core product is reliable and user needs are validated.
