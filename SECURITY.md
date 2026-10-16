# Security policy and scope

**Fasty is a portfolio/learning project, not a hosted service or production-ready authentication platform.** Its code, configuration, and deployment model must be reviewed and hardened before any Internet-facing use.

## Reporting

Please avoid posting credentials, real private notes, session tokens, or user data in a public issue. Contact the repository owner privately through their GitHub profile before disclosing any suspected vulnerability. No paid support, vulnerability response SLA, or security certification is offered.

## Safeguards and known limitations

- Environment variables and local `.env` files hold database, JWT, email, recovery-admin, and OAuth secrets; never commit them.
- The default example Compose API bind is localhost-only. A secure public service would require HTTPS, network controls, abuse/rate limiting, backup/restore drills, and an authorization review.
- Android's release manifest disables cleartext HTTP; the debug manifest permits local emulator HTTP only. Do not treat development settings as production deployment guidance.
- Assisted password recovery is implemented for developer/test environments. Recovery administration must remain disabled unless intentionally configured and secured.
- Notes and workspace synchronization currently use last-write-wins strategies, not conflict-free collaborative editing; concurrent edits can lose changes.
- Run the service only in an isolated developer environment unless you have completed a separate security and operations review.

For local-only configuration and tests, see [development and testing](docs/development/testing.md). This repository is not a managed public API.
