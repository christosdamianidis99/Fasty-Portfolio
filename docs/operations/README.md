# Operations — local development and portfolio evaluation

Fasty runs an ASP.NET Core API and PostgreSQL via [Docker Compose](../../infrastructure/compose.yaml). The setup below is for **isolated developer testing**, not for exposing a production note-taking service.

## Safe local principles

- Use `infrastructure/.env.example` as a template and populate a new ignored `infrastructure/.env` with freshly generated test credentials.
- Keep `FASTY_API_BIND=127.0.0.1`. Do not publish PostgreSQL ports to the host.
- Use disposable, empty database volumes and separate test data folders. Never mount a personal user-data directory.
- Do not reuse production tokens, Google OAuth secrets, SMTP passwords, admin-recovery keys, or signing certificates.
- Local HTTP is appropriate only on the development machine. A network-facing service requires HTTPS, reviewed authentication, monitoring protection, and abuse controls.
- When deleting a **disposable test environment only**, first verify the compose project and Docker volume names; `docker compose down -v` destroys persistent data and must never be run against the user's personal or production environment.

## Local smoke check

~~~bash
cd infrastructure
cp .env.example .env
# Edit .env with newly generated values and loopback binding before continuing.
docker compose config --quiet
docker compose up -d --build
curl --fail http://127.0.0.1:8080/health
curl --fail http://127.0.0.1:8080/health/ready
~~~

When finished, `docker compose down` stops containers while retaining the database volume. See the root [README](../../README.md) for Flutter client commands.

## Deployment gaps

A real user-facing deployment needs a documented backup and restore drill, data export/deletion procedures, HTTPS, verified authorization, restricted admin diagnostics, logging and secret-handling review, dependency maintenance, and a runtime acceptance matrix. The portfolio repository makes **no production-readiness guarantee**.
