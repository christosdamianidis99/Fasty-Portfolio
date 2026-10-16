# ADR-0008 — Use Docker Compose and private Tailscale access for personal deployment

- Status: Accepted
- Date: 2026-07-23
- Decision owners: Fasty maintainers

## Context

Fasty's first real deployment will run on an always-on Lubuntu laptop for personal use. The deployment must be inexpensive, reproducible, secure enough for private daily use, easy to restore, and portable to a future VPS or managed container platform.

The server must host the ASP.NET Core API, PostgreSQL, and supporting infrastructure without exposing the laptop directly to the public internet during the personal phase.

## Decision drivers

- Reproducible local and server environments
- Low operational cost
- Private access from Android, Windows, and browser clients
- Minimal public attack surface
- Straightforward backup and restoration
- Compatibility with Linux and future cloud deployment
- Clear separation of application data, configuration, and secrets
- Ability to replace the personal server without redesigning the application

## Considered options

1. Docker Compose on Lubuntu with Tailscale private access
2. Native systemd services installed directly on Lubuntu
3. Public internet exposure through router port forwarding
4. Immediate deployment to a public VPS
5. Kubernetes or another production orchestrator
6. Backend-as-a-service hosting

## Decision

Fasty's personal deployment will use Docker Engine and Docker Compose on the Lubuntu laptop.

The initial runtime stack will contain:

- `fasty-api`: ASP.NET Core application
- `postgres`: PostgreSQL database
- `caddy`: reverse proxy and HTTPS boundary where required
- optional backup job or backup container
- optional monitoring components added only when justified

Remote access will use Tailscale. The personal deployment will not require inbound router port forwarding and will not expose PostgreSQL publicly.

The application will be treated as private-by-default:

- API and web access are limited to authenticated devices on the Tailscale network.
- PostgreSQL is reachable only through the private Docker network and, when necessary for administration, localhost or an explicitly protected path.
- No database port is published to the public network.
- The server firewall denies unnecessary inbound traffic.
- Public internet exposure requires a separate security review and deployment ADR.

Caddy will be the preferred reverse proxy because its configuration is small and it can manage HTTPS automatically when a valid DNS and certificate setup is available. For the earliest Tailscale-only deployment, either Caddy or Tailscale Serve may terminate HTTPS, but the application containers remain independent of the selected edge mechanism.

## Compose topology

A representative topology is:

```text
Android / Windows / Browser
            |
      Tailscale network
            |
     Caddy or Tailscale Serve
            |
        Fasty API
            |
       PostgreSQL
```

Docker Compose will define networks, persistent volumes, health checks, restart policies, environment configuration, and service dependencies.

The repository should eventually contain:

```text
infrastructure/
├── compose.yaml
├── compose.override.yaml.example
├── caddy/
│   └── Caddyfile
├── env/
│   └── .env.example
├── backup/
│   ├── backup.sh
│   └── restore.sh
└── README.md
```

Real secret files and generated backups must not be committed.

## Container rules

- Images must use pinned major or minor versions rather than unbounded `latest` tags.
- The API image must run as a non-root user where practical.
- Containers must have restart policies suitable for a personal server.
- Application logs must go to standard output and standard error.
- Persistent state must live in named volumes or documented host-mounted directories.
- PostgreSQL and attachment storage must never depend on the writable container layer.
- Health checks must distinguish process availability from application readiness.
- Configuration must come from environment variables, mounted configuration, or a secret mechanism.
- Development-only services and ports must not appear in the production Compose profile.

## Networking rules

- Only the reverse proxy or Tailscale edge is exposed to clients.
- The API listens on the internal Compose network.
- PostgreSQL listens only on the internal Compose network unless a temporary administrative override is explicitly enabled.
- SignalR and normal REST traffic pass through the same authenticated HTTPS origin when possible.
- CORS must use an explicit allowlist; wildcard origins are not permitted for authenticated production endpoints.
- Router port forwarding is not part of the personal deployment.

## Tailscale access

Tailscale will provide encrypted private connectivity between the server and approved devices.

Operational rules:

- Devices must be individually authenticated.
- Device access must be revocable from the Tailscale administration interface.
- Access-control rules should limit the Fasty service to the owner's devices.
- Tailscale identity does not replace Fasty application authentication.
- The API must continue to require valid Fasty credentials and authorization.
- Loss of the Tailscale connection must not affect offline note usage.

Tailscale Serve may be used to provide a private HTTPS endpoint during the personal phase. Fasty must not depend on Tailscale-specific headers or URLs inside domain or synchronization logic.

## HTTPS and reverse proxy

All authenticated traffic must use HTTPS, including traffic carried over Tailscale.

Caddy is the preferred general-purpose reverse proxy for:

- TLS termination
- HTTP-to-HTTPS redirection
- forwarding REST and SignalR traffic
- request-size limits for future attachments
- security headers
- access logging without sensitive payloads

The reverse proxy must support WebSocket upgrades for SignalR. Proxy timeouts must be configured so that long-lived connections do not become the source of synchronization correctness.

## Backups

The personal deployment must provide automated PostgreSQL backups using supported PostgreSQL tooling such as `pg_dump`.

Minimum backup policy for the personal alpha:

- At least one automated logical backup per day
- A retention window covering multiple historical days
- Backups stored outside the active PostgreSQL data volume
- At least one copy stored on another physical device or trusted remote storage
- Encryption for backups that leave the server
- Documented restoration commands
- Periodic restoration tests into a clean PostgreSQL instance

A backup is not considered valid merely because a file exists. The project must test that it can restore the database and access expected notes.

Future attachment storage will require a separate backup policy. Database backups alone will not protect media objects.

## Updates and maintenance

The personal server requires regular maintenance:

- Apply Lubuntu security updates.
- Keep Docker Engine, Compose, Tailscale, Caddy, PostgreSQL, and .NET images supported and patched.
- Review container image updates before deployment.
- Back up before database upgrades or risky migrations.
- Use version-controlled EF Core migrations.
- Document rollback procedures for application deployments.
- Never auto-upgrade PostgreSQL across major versions without a tested migration plan.

Automated unattended upgrades may be used for operating-system security fixes, but application and database upgrades should remain controlled.

## Deployment process

The initial deployment process will be manual but reproducible:

1. Pull an approved Git commit or release.
2. Review environment and image changes.
3. Create a current database backup.
4. Build or pull pinned images.
5. Run database migrations using an explicit deployment step.
6. Start the Compose stack.
7. Verify health and readiness endpoints.
8. Perform a synchronization smoke test from a client.
9. Preserve the previous image tag for rollback.

Directly building unreviewed code on the server is discouraged after the proof-of-concept stage. CI-produced images should be introduced before public beta.

## Observability

The personal alpha must include:

- Structured API logs
- Container health status
- Basic disk-space monitoring
- Database backup success or failure reporting
- A readiness endpoint covering critical dependencies
- A liveness endpoint that does not create heavy database load

Metrics and alerting systems may be added later, but backup failures and low disk space must not remain silent.

Sensitive note contents, access tokens, refresh tokens, passwords, and attachment payloads must not be written to logs.

## Power and hardware limitations

The Lubuntu laptop is not production-grade infrastructure. The personal deployment accepts:

- Possible downtime during power or network failure
- No formal service-level objective
- Limited CPU, memory, storage, and upload bandwidth
- Dependence on the physical laptop and home connection

Mitigations include automatic container restart, tested backups, storage monitoring, and a documented process for restoring the stack on another machine.

A battery-backed laptop provides some protection against brief power interruptions, but this is not a substitute for remote backups.

## Cloud migration path

The deployment must remain portable. Moving to a VPS or managed platform should primarily involve replacing infrastructure configuration, not application code.

Expected future substitutions include:

- Lubuntu Docker host → VPS or managed container service
- Self-hosted PostgreSQL → managed PostgreSQL
- Local attachment directory → S3-compatible object storage
- Tailscale-only endpoint → public domain, WAF, rate limiting, and public TLS
- Local backup scripts → managed backups plus independent export copies

The application must not embed hostnames, Tailscale addresses, local filesystem paths, or Docker-specific assumptions in domain logic.

## Rejected options

### Native systemd deployment

Native services could reduce container overhead, but they make setup, dependency isolation, and migration to another host less reproducible.

### Public router port forwarding

This creates unnecessary public exposure during the personal phase and requires more security hardening, monitoring, DNS, certificate, and abuse protection work.

### Immediate VPS hosting

A VPS is a valid future target, but the personal Lubuntu machine is sufficient to validate the product while keeping costs low.

### Kubernetes

Kubernetes would add substantial operational complexity without solving a current scaling or availability requirement.

### Tailscale as the only security layer

Private networking reduces exposure but does not replace application authentication, authorization, secure token handling, auditing, or backups.

## Consequences

### Positive

- Low-cost private deployment
- Reproducible infrastructure
- No inbound router configuration
- Reduced public attack surface
- Straightforward movement to another Docker host
- Clear separation between application and infrastructure
- Ability to test realistic backup and restore operations early

### Negative

- The owner is responsible for patching and operations.
- Availability depends on a consumer laptop and home network.
- Tailscale must be installed on each approved device.
- Browser access is limited to devices with suitable private-network access.
- Docker and PostgreSQL still require maintenance and monitoring.

### Risks and mitigations

- **Disk failure:** maintain encrypted off-device backups and test restoration.
- **Home outage:** preserve full offline client operation and synchronize later.
- **Misconfigured exposure:** avoid router forwarding and verify listening ports.
- **Secret leakage:** use ignored environment files or a secret store; scan commits.
- **Database corruption or failed migration:** back up before changes and test migrations.
- **Container image compromise:** use trusted registries, pinned versions, and update review.
- **Single-host failure:** document restoration to a replacement Linux host.

## Validation

Before the personal alpha is considered complete:

1. A clean Lubuntu host can start the stack from documented instructions.
2. Android and Windows clients can reach Fasty through Tailscale.
3. No service is reachable through an unintended public port.
4. REST and SignalR work through the selected HTTPS edge.
5. Restarting the laptop automatically restores the stack.
6. PostgreSQL data survives container recreation.
7. An automated backup is produced and copied off-device.
8. A backup restores successfully into a clean database.
9. The deployment can be recreated on a second Linux machine.
10. The application remains usable offline during server downtime.

## References

- Docker Engine installation documentation
- Docker Compose plugin documentation
- Tailscale Linux installation and Serve documentation
- Caddy reverse proxy and automatic HTTPS documentation
- PostgreSQL backup and restore documentation
