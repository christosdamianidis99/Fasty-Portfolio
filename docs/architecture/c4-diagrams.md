# Fasty — C4 Architecture Diagrams

These diagrams describe the intended architecture before Phase 1 implementation. They must be updated when implementation materially changes the system.

## Level 1 — System context

```mermaid
flowchart LR
    User["Fasty user\nUses notes across devices"]
    Fasty["Fasty\nLocal-first cross-platform notes system"]
    Tail["Tailscale\nPrivate network for personal deployment"]
    FutureIdP["Future identity provider\nOIDC / enterprise SSO"]
    FutureObject["Future object storage\nS3-compatible media storage"]

    User -->|Creates, edits, searches and synchronizes notes| Fasty
    User -->|Connects approved devices| Tail
    Tail -->|Private HTTPS route| Fasty
    Fasty -.->|May delegate authentication later| FutureIdP
    Fasty -.->|May store attachments later| FutureObject
```

### Context notes

- The user interacts through Android, Windows, or web clients.
- The system remains useful while disconnected because note text is stored locally.
- Tailscale is a deployment boundary, not the Fasty authentication system.
- External identity and object-storage systems are future integrations, not MVP dependencies.

## Level 2 — Containers

```mermaid
flowchart TB
    User["User"]

    subgraph Devices["User devices"]
        Flutter["Flutter client\nAndroid, Windows, Web\nUI, local repositories, sync engine"]
        SQLite["Local persistence\nSQLite + Drift / web persistence\nNotes, outbox, cursor, conflicts"]
        Cache["Attachment cache\nDevice or browser binary storage"]
    end

    subgraph PersonalHost["Personal Lubuntu host"]
        Edge["Private HTTPS edge\nTailscale Serve or Caddy"]
        Api["Fasty API\nASP.NET Core modular monolith\nREST/OpenAPI + SignalR"]
        Postgres["PostgreSQL\nAuthoritative metadata, identities, changes"]
        Objects["Object storage abstraction\nProtected local volume initially"]
        Backup["Backup process\nDatabase, objects and protected keys"]
    end

    User --> Flutter
    Flutter <--> SQLite
    Flutter <--> Cache
    Flutter -->|HTTPS REST: auth, push, pull, bootstrap| Edge
    Edge --> Api
    Api --> Postgres
    Api --> Objects
    Api -.->|Changes-available notification| Flutter
    Backup --> Postgres
    Backup --> Objects
    Backup -->|Protected backup| Api
```

### Container responsibilities

#### Flutter client

- Renders adaptive mobile, desktop, and web interfaces.
- Reads application state from local persistence.
- Writes user mutations locally and to the outbox atomically.
- Pushes pending operations and pulls incremental server changes.
- Stores native credentials in platform-protected storage.
- Uses secure cookies on web.

#### Local persistence

- Stores note text for offline access.
- Stores the outbox, synchronization cursor, conflict copies, and attachment metadata.
- Applies downloaded changes and cursor advancement transactionally.

#### Fasty API

- Authenticates users and authorizes every resource operation.
- Processes idempotent synchronization commands.
- Maintains server versions, tombstones, conflicts, and durable change entries.
- Exposes versioned REST/OpenAPI endpoints.
- Sends optional SignalR change notifications.
- Coordinates attachment metadata with binary storage.

#### PostgreSQL

- Authoritative system of record for identities, notes, synchronization state, conflicts, and attachment metadata.
- Enforces relational constraints and transactional invariants.

#### Object storage abstraction

- Stores media binaries outside PostgreSQL.
- Begins as protected local storage and can move to S3-compatible storage.

#### Backup process

- Produces versioned, protected backups.
- Includes PostgreSQL, object data, configuration required for restoration, and persistent cryptographic keys.
- Is validated through restoration tests.

## Level 3 — ASP.NET Core modular monolith

```mermaid
flowchart LR
    Edge["HTTP / SignalR entry points"]

    subgraph Api["Fasty.Api"]
        Endpoints["Versioned REST endpoints"]
        Hub["SignalR notification hub"]
        Middleware["Auth, authorization, errors, logging, rate limits"]
    end

    subgraph Modules["Business modules"]
        Identity["Identity\nUsers, devices, sessions"]
        Notes["Notes\nNotes, versions, conflicts"]
        Sync["Synchronization\nOutbox commands, change feed, bootstrap"]
        Attachments["Attachments\nMetadata, upload states, object coordination"]
        Notifications["Notifications\nChanges-available publication"]
    end

    subgraph BuildingBlocks["Small shared building blocks"]
        Clock["Clock and IDs"]
        Results["Errors and results"]
        Events["Explicit internal contracts"]
    end

    Db[("PostgreSQL")]
    Obj[("Object storage")]

    Edge --> Endpoints
    Edge --> Hub
    Middleware --> Endpoints
    Endpoints --> Identity
    Endpoints --> Notes
    Endpoints --> Sync
    Endpoints --> Attachments
    Hub --> Identity
    Sync --> Notes
    Sync --> Attachments
    Sync --> Notifications
    Notes --> Notifications
    Attachments --> Notifications
    Identity --> Db
    Notes --> Db
    Sync --> Db
    Attachments --> Db
    Attachments --> Obj
    Notifications --> Hub
    Identity --> BuildingBlocks
    Notes --> BuildingBlocks
    Sync --> BuildingBlocks
    Attachments --> BuildingBlocks
```

### Module rules

- Modules expose explicit application contracts.
- No module accesses another module's infrastructure implementation directly.
- Domain code does not depend on ASP.NET Core, EF Core, SignalR, or storage SDKs.
- The API layer contains transport mapping, not domain rules.
- One PostgreSQL database may use module-owned schemas.
- Cross-module transactions are allowed only where required by documented invariants, especially note mutation plus change-feed creation.

## Level 3 — Client synchronization components

```mermaid
flowchart TB
    UI["Flutter UI"]
    Repo["Local repositories"]
    LocalDb[("SQLite / web local database")]
    Outbox["Outbox coordinator"]
    Sync["Single-flight sync engine"]
    Api["REST API client"]
    Realtime["SignalR notification client"]
    Secure["Platform secure credential storage"]
    Cache["Attachment cache manager"]

    UI --> Repo
    Repo --> LocalDb
    Repo -->|Local transaction creates mutation + operation| Outbox
    Outbox --> LocalDb
    Sync --> Outbox
    Sync --> Api
    Api --> Secure
    Api -->|Apply changes + cursor atomically| LocalDb
    Realtime -->|Trigger sync only| Sync
    LocalDb --> UI
    Cache --> LocalDb
    Sync --> Cache
```

## Primary synchronization sequence

```mermaid
sequenceDiagram
    participant U as User
    participant C as Flutter client
    participant L as Local database
    participant A as Fasty API
    participant P as PostgreSQL
    participant O as Other device

    U->>C: Edit note
    C->>L: Transaction: update note + add outbox operation
    L-->>C: Commit
    C-->>U: Show saved state immediately
    C->>A: POST /api/v1/sync/push
    A->>P: Transaction: validate version, mutate note, record operation, add change entry
    P-->>A: Commit version and cursor
    A-->>C: Acknowledge operation, version and cursor
    C->>L: Mark outbox operation acknowledged
    A-->>O: SignalR: changes available
    O->>A: GET /api/v1/sync/changes?after=cursor
    A->>P: Read ordered user changes
    P-->>A: Change page
    A-->>O: Changes + next cursor
    O->>O: Transaction: apply changes + advance cursor
```

## Deployment view

```mermaid
flowchart LR
    Android["Android app"]
    Windows["Windows app"]
    Browser["Web browser"]
    Tail["Tailscale tailnet"]

    subgraph Laptop["Always-on Lubuntu laptop"]
        Docker["Docker Compose"]
        Edge["Caddy / Tailscale Serve"]
        Api["Fasty API container"]
        Db["PostgreSQL container"]
        Obj["Protected attachment volume"]
        Backups["Scheduled backup job"]

        Edge --> Api
        Api --> Db
        Api --> Obj
        Backups --> Db
        Backups --> Obj
    end

    Android --> Tail
    Windows --> Tail
    Browser --> Tail
    Tail --> Edge
    Backups --> Offsite["Encrypted off-device backup"]
```

## Evolution boundaries

The architecture intentionally supports these later substitutions:

- Lubuntu host → VPS or managed containers
- local PostgreSQL → managed PostgreSQL
- local object volume → S3-compatible storage
- Tailscale-only edge → public domain and hardened public edge
- local Identity → OpenID Connect provider
- selected internal module → independent service, only after a new ADR

The clients and synchronization protocol must not depend on deployment-specific hostnames, Docker network names, or local file paths.
