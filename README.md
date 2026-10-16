# Fasty

**Offline-first notes and visual workspaces, built with Flutter, ASP.NET Core, and PostgreSQL.**

Fasty is a full-stack engineering portfolio project exploring durable offline editing, cross-device synchronization, account security, and platform-specific user experiences. It uses Flutter on Android and desktop targets and a .NET 10 API backed by PostgreSQL. This repository contains source code for local evaluation, not a hosted production SaaS.

> **Status:** Source-available engineering portfolio. This is not a hosted service, security-certified product, or production-ready deployment. Android, Windows, and web compile smoke tests and 226 Flutter / 164 backend automated tests passed on the reviewed source snapshot; native multi-device acceptance remains incomplete.

## What it demonstrates

- **Local-first storage:** notes are stored in a local SQLite database using Drift and remain editable without a network connection.
- **Synchronization:** a persistent outbox, retry handling, deletion and restoration, and sync-state visibility across clients.
- **Cross-platform Flutter UI:** visual desktop workspaces, mobile note cards, Markdown, checklists, search, filtering, pinning, and theme preferences.
- **Full-stack identity:** registration, login, token refresh, session management, optional Google account linking, and private-beta password recovery.
- **Backend engineering:** ASP.NET Core REST endpoints, EF Core migrations, PostgreSQL, containerized services, and observability tools.
- **Testing:** Flutter repository/synchronization tests and .NET backend/integration tests (including PostgreSQL-backed tests in CI).

## Architecture

| Layer | Implementation |
| --- | --- |
| Client | Flutter / Dart (Android, Windows, Linux source targets; other targets are unverified) |
| Local persistence | SQLite + Drift |
| Backend | ASP.NET Core / .NET 10, modular API |
| Server persistence | PostgreSQL + Entity Framework Core |
| Authentication | ASP.NET Core Identity, JWT access tokens, refresh sessions; optional Google Sign-In |
| Infrastructure | Docker Compose for API + PostgreSQL |
| Validation | Flutter analysis/tests, .NET tests, platform smoke builds |

Conceptually:

~~~text
Flutter app (local SQLite + outbox)
              |
       REST API (HTTPS recommended outside local development)
              |
       ASP.NET Core service
              |
         PostgreSQL
~~~

For details, see [architecture](docs/architecture/README.md), [synchronization semantics](docs/architecture/synchronization.md), and the [decision records](docs/decisions/README.md).

## Running locally (developer evaluation)

**Requirements:** Flutter with Dart 3.8+ support, Docker with Compose, and optionally .NET SDK 10 for API tests. These instructions assume a trusted development machine and a fresh, disposable database; they do not use the personal beta server.

1. Copy `infrastructure/.env.example` to `infrastructure/.env`. Set `FASTY_DB_PASSWORD` and `FASTY_JWT_SIGNING_KEY` to **different, long, randomly generated values** (for example, generate each using `openssl rand -hex 32`). They are intentionally blank in the example, and Compose will refuse to start without them. Keep `.env` out of Git.
2. Set `FASTY_API_BIND=127.0.0.1`; set both host data directories to writable directories on your own machine. **Do not copy private-server paths, addresses, or production credentials.**
3. Run the API and database:

   ~~~bash
   cd infrastructure
   docker compose up -d --build
   curl http://127.0.0.1:8080/health
   curl http://127.0.0.1:8080/health/ready
   ~~~

4. In another terminal, start a client:

   ~~~bash
   cd client
   flutter pub get
   flutter run -d linux --dart-define=FASTY_API_BASE_URL=http://127.0.0.1:8080
   ~~~

   Replace `linux` with `windows` when using Windows. An Android emulator normally reaches its development host via `http://10.0.2.2:8080`, but binding Docker only to loopback may require additional emulator/network setup. A physical Android device needs an explicitly configured, reachable API endpoint.

The backend applies EF Core migrations at startup. **Do not point this example at any existing database**. Localhost HTTP is for development only. No production deployment or public account service is provided by this repository.

## Running tests

~~~bash
cd client
flutter pub get
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze
flutter test

cd ../backend
dotnet test tests/Fasty.Api.Tests/Fasty.Api.Tests.csproj
~~~

Some backend integration tests require a separate disposable PostgreSQL instance and `FASTY_TEST_DATABASE` connection string; see [testing guide](docs/development/testing.md) and [CI workflow](.github/workflows/flutter-ci.yml).

## Known limitations

- **Last-write-wins:** note conflict resolution uses client timestamps; simultaneous edits can overwrite one another. Workspace state is not a CRDT or conflict-free collaborative editor.
- **Security/deployment:** Android release variants disable cleartext HTTP; debug builds can use localhost/emulator HTTP. This source repository does not include the hardening, HTTPS infrastructure, and operational controls required for Internet-facing deployment.
- **Platforms:** automated compilation is not the same as end-to-end validation on every supported device. Web/Apple targets are not confirmed as public releases.
- **Operations:** this is not a hosted public service. Backup/restore, security review, production HTTPS, user-support, and release management must be completed before any real-world deployment.

## Project resources

- [Testing and real-device verification](docs/development/testing.md)
- [R3 checkpoint: historical test evidence](docs/R3_CHECKPOINT_2026-09-30.md)
- [Portfolio engineering highlights](docs/portfolio/ENGINEERING_HIGHLIGHTS.md)
- [Product roadmap (historical planning)](docs/product/roadmap.md)

## License

Fasty's original code is available under the [MIT License](LICENSE) (copyright © 2026 Christos Damianidis). Third-party dependencies and bundled assets retain their own applicable rights. Review [third-party notices](THIRD_PARTY_NOTICES.md). A license is not a warranty of security or production suitability.

## Credits

Built as an independent engineering and learning project. Contributions, issue handling, and long-term maintenance are not currently promised.
