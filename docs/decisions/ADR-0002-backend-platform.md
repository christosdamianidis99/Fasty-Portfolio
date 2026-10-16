# ADR-0002 — Backend platform

- Status: Accepted
- Date: 2026-07-22
- Decision owners: Fasty maintainers

## Context

Fasty requires a backend that can reliably support authenticated multi-device synchronization, incremental change exchange, conflict detection, background processing, future attachments, operational monitoring, and near-real-time client notifications.

The first deployment should run efficiently on an always-on Lubuntu laptop using containers. The same application must later be portable to a VPS, managed container platform, public cloud, or enterprise-controlled environment without rewriting the business logic.

The backend is expected to begin as a modular monolith. It must expose a stable, documented API to Flutter clients and retain control over the synchronization protocol rather than coupling clients directly to database tables.

## Decision drivers

- Reliable implementation of synchronization and transactional workflows
- Strong authentication and authorization support
- Linux and Docker deployment
- Clear support and upgrade lifecycle
- Good observability, testing, and API documentation
- Long-term suitability for public and enterprise deployments
- Efficient development by a single developer
- Strong ecosystem for PostgreSQL, background jobs, and real-time notifications
- Ability to keep domain and synchronization logic independent from infrastructure
- Professional learning value without unnecessary project risk

## Considered options

1. ASP.NET Core with C#
2. Spring Boot with Java or Kotlin
3. NestJS with TypeScript
4. Go with a lightweight HTTP framework or standard library
5. Rust with Axum or Actix Web
6. Supabase or another backend-as-a-service as the primary backend

## Decision

Use **ASP.NET Core on the current supported .NET Long Term Support release** as Fasty's backend platform.

At the time of this decision, .NET 10 is the active LTS release. Fasty should track supported LTS versions and remain current with security and servicing patches rather than permanently pinning the project to a historical version.

The backend will initially use:

- C#
- ASP.NET Core Web API
- OpenAPI as the HTTP API contract
- Entity Framework Core for the primary persistence integration
- PostgreSQL as the planned server database, subject to ADR-0003
- SignalR for online change notifications, subject to a later synchronization transport ADR
- Docker containers for development and deployment
- Built-in dependency injection, configuration, logging, health checks, and authentication facilities

The authoritative synchronization process will use normal transactional API endpoints. SignalR will notify connected devices that new changes are available, but it will not be the sole carrier or source of truth for synchronization data.

## Architectural constraints

### Modular monolith first

The backend must begin as one deployable application with internally separated modules. Microservices are not justified for the personal MVP.

Expected initial modules include:

- Identity
- Notes
- Synchronization
- Devices and sessions
- Attachments, later
- Administration, later

Modules should have explicit responsibilities and should not communicate through arbitrary cross-module database access.

### API boundaries

Flutter clients must communicate through a versioned application API. Clients must not connect directly to PostgreSQL or depend on its table layout.

OpenAPI will be used to:

- Document endpoints and schemas
- Review API changes
- Support generated or strongly typed client integrations
- Test compatibility between backend and clients

### Synchronization ownership

The backend owns:

- Server-generated change ordering
- Idempotency checks
- Authorization of every synchronized entity
- Conflict detection metadata
- Tombstones and deletion rules
- Validation of client operations
- Transactional persistence

These responsibilities must not be delegated solely to generic database change subscriptions.

### Framework isolation

Domain rules and synchronization decisions should not be embedded directly in controllers, Entity Framework entities, or SignalR hubs.

The codebase should separate at least:

- Domain concepts and rules
- Application use cases
- Infrastructure integrations
- HTTP and real-time delivery

This separation should remain pragmatic. Fasty should avoid creating interfaces and layers that do not protect a meaningful boundary or improve testing.

### Version and dependency policy

- Use a supported .NET LTS release.
- Apply supported patch updates promptly.
- Keep ASP.NET Core, Entity Framework Core, and database-provider major versions compatible.
- Record major upgrades in ADRs or upgrade notes when they affect architecture or behavior.
- Avoid unnecessary framework-specific packages when built-in platform capabilities are sufficient.

## Why ASP.NET Core was selected

ASP.NET Core provides a strong combination of cross-platform deployment, mature web APIs, authentication, dependency injection, structured configuration, testing support, OpenAPI generation, real-time communication, and production diagnostics.

It runs on Linux and in Linux containers, making it suitable for the Lubuntu personal server and later cloud environments.

C# also gives the project a productivity advantage because the maintainer already has professional .NET experience. This reduces delivery risk while still allowing substantial learning in distributed synchronization, security, PostgreSQL, Linux operations, containers, observability, and enterprise architecture.

The platform has an explicit support lifecycle. Using the active LTS release gives Fasty a predictable maintenance and upgrade policy.

## Why the alternatives were not selected

### Spring Boot

Spring Boot is a fully credible enterprise alternative. It supports standalone production-grade services and provides mature health, metrics, configuration, security, persistence, and testing ecosystems.

It was not selected because it does not offer a decisive product advantage for Fasty over ASP.NET Core, while adopting it would increase initial learning and development cost. It remains a valid reconsideration option if a future team is primarily JVM-based or an enterprise customer requires integration with an existing Spring ecosystem.

### NestJS

NestJS offers a structured TypeScript backend model, dependency injection, modules, and OpenAPI integration. TypeScript also has strong market relevance.

It was not selected because Fasty's backend is likely to contain synchronization-heavy transactional logic where ASP.NET Core and C# provide a stronger fit with the maintainer's experience and desired type-safe domain modeling. Choosing NestJS mainly for language-market breadth would add runtime and dependency-management complexity without solving a Fasty-specific problem better.

### Go

Go could produce a small, efficient, easily deployed service with strong concurrency primitives and excellent container characteristics.

It was not selected because Fasty would need to assemble more architectural and application-level facilities from separate libraries. Go remains attractive if measurements later show that memory usage, startup time, or very high connection concurrency have become dominant constraints.

### Rust

Rust offers excellent performance, memory safety, and low resource use.

It was not selected because it would significantly increase implementation time and complexity for authentication, persistence, migrations, and rapid product iteration. Fasty's initial risks concern synchronization correctness and product validation, not raw server performance.

Rust may still be useful later for a highly specialized component if profiling proves it necessary.

### Supabase or another backend-as-a-service

A backend-as-a-service could accelerate authentication, database access, storage, and realtime features. Supabase is especially attractive because it is PostgreSQL-based and can be self-hosted.

It was not selected as the primary backend because Fasty needs explicit control over synchronization semantics, idempotency, conflict handling, and long-term API boundaries. Direct client-to-database patterns would increase coupling between Flutter clients and persistence structures.

Self-hosted Supabase also introduces multiple operational services and leaves the maintainer responsible for security, upgrades, backups, monitoring, availability, and database operations. Managed Supabase may still be used for a disposable prototype or evaluated as infrastructure behind a Fasty-controlled API, but it is not the authoritative application architecture.

## Consequences

### Positive

- One mature backend platform covers API, authentication, notifications, configuration, and diagnostics.
- The service can run on Linux, Docker, the Lubuntu laptop, and common cloud platforms.
- Existing C# experience reduces implementation risk.
- Strong typing is well suited to synchronization commands, versions, and conflict rules.
- Built-in OpenAPI support helps keep the Flutter client contract explicit.
- SignalR provides an integrated path for online notifications.
- The .NET support policy provides predictable LTS maintenance windows.
- The architecture can later support enterprise identity, observability, and cloud deployment.

### Negative

- The project will use two principal application languages: Dart for clients and C# for the backend.
- Self-hosting still requires Linux, networking, database, security, and backup administration.
- ASP.NET Core features can encourage excessive framework coupling if domain rules are placed directly in controllers or persistence models.
- Entity Framework Core abstractions can hide inefficient queries unless SQL and database behavior are monitored.
- A custom backend requires more initial work than a backend-as-a-service.

### Risks and mitigations

#### Risk: over-engineered Clean Architecture

Mitigation: create boundaries only where they protect business logic, testability, or replaceable infrastructure. Avoid one-interface-per-class patterns and unnecessary mediator abstractions.

#### Risk: framework knowledge hides database fundamentals

Mitigation: review generated SQL, create explicit indexes, test migrations, and profile synchronization queries against realistic data volumes.

#### Risk: SignalR becomes the synchronization protocol

Mitigation: use SignalR only as a wake-up or invalidation channel. The durable sync API and PostgreSQL transactions remain authoritative.

#### Risk: resource use on the old laptop

Mitigation: begin with one API container and one PostgreSQL instance, measure actual CPU and memory use, disable unnecessary services, and use release-mode container images.

#### Risk: LTS version becomes unsupported

Mitigation: track the official .NET lifecycle, apply monthly patches, and schedule major-version upgrades before end of support.

## Validation

Before considering the backend foundation complete, a proof of concept must demonstrate:

1. An ASP.NET Core service running in a Linux container on a development machine.
2. The same container running on the Lubuntu laptop.
3. A documented OpenAPI endpoint callable from a small Flutter client.
4. PostgreSQL connectivity through a migration-managed persistence layer.
5. A transaction that stores a note and an associated synchronization change atomically.
6. An idempotent command that can be retried without creating duplicate data.
7. A SignalR notification that prompts another client to pull changes through the normal API.
8. Structured logs and health endpoints.
9. Automated unit and integration tests executed in CI.
10. Configuration and secrets supplied outside source control.

The decision should be reconsidered if the proof of concept reveals unacceptable Linux resource usage, missing Flutter interoperability, or a major platform constraint that cannot be resolved without fragile custom work.

## References

- .NET support policy: https://dotnet.microsoft.com/en-us/platform/support/policy/dotnet-core
- Install .NET on Linux: https://learn.microsoft.com/en-us/dotnet/core/install/linux
- Host ASP.NET Core in Docker: https://learn.microsoft.com/en-us/aspnet/core/host-and-deploy/docker/
- ASP.NET Core OpenAPI support: https://learn.microsoft.com/en-us/aspnet/core/fundamentals/openapi/overview
- ASP.NET Core SignalR overview: https://learn.microsoft.com/en-us/aspnet/core/signalr/introduction
- Spring Boot: https://spring.io/projects/spring-boot/
- NestJS documentation: https://docs.nestjs.com/
- Supabase self-hosting: https://supabase.com/docs/guides/self-hosting
