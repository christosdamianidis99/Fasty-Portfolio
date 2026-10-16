# ADR-0010 — Authentication and secure token storage

- Status: Accepted
- Date: 2026-07-23
- Decision owners: Fasty maintainers

## Context

Fasty requires one account to work securely across Android, Windows, and web clients. Authentication must support offline application use without weakening server-side authorization, device-level session revocation, future password reset and MFA, and a later migration to an external OpenID Connect provider if the product becomes public or enterprise-facing.

Authentication material must not be exposed through logs, browser storage vulnerable to JavaScript access, source control, or unprotected application files.

## Decision drivers

- Secure browser and native-client session handling
- Per-device session visibility and revocation
- Compatibility with ASP.NET Core and PostgreSQL
- Reasonable complexity for the personal MVP
- Future migration to standards-based identity providers
- Protection against token theft, replay, and credential stuffing
- Clear separation between authentication and authorization

## Considered options

1. ASP.NET Core Identity with separate browser-cookie and native-token flows
2. Self-issued JWT access and refresh tokens without ASP.NET Core Identity
3. External identity provider from the first release
4. One long-lived bearer token per installation
5. Tailscale identity as the only application identity

## Decision

Fasty will use ASP.NET Core Identity for local account and credential management during the personal and early public phases.

### Browser clients

The browser client will use a server-issued session cookie configured with:

- `HttpOnly`
- `Secure`
- an appropriate `SameSite` policy
- short inactivity and absolute lifetime limits
- anti-forgery protection for state-changing requests

Authentication tokens, session identifiers, and refresh tokens must not be stored in `localStorage` or `sessionStorage`.

### Android, Windows, and other installed clients

Installed clients will use:

- short-lived bearer access tokens
- longer-lived, opaque refresh tokens
- one refresh-token family per device session
- refresh-token rotation on every successful refresh
- reuse detection that revokes the affected token family

Refresh tokens will be stored only as one-way hashes on the server. The plaintext refresh token exists only when issued to the client.

### Client-side token storage

- Android will use platform-backed secure storage based on Android Keystore.
- Windows will use an operating-system-protected credential store.
- iOS and macOS will use Keychain when those platforms are added.
- Linux will use an appropriate desktop secret service when supported.
- The web client will rely on secure cookies rather than JavaScript-readable token storage.

Access tokens may be held in memory. Installed clients may persist only the minimum credential material required for session recovery, using platform-protected storage.

### Device sessions

The server will maintain a device-session record containing at least:

- session identifier
- user identifier
- device identifier
- display name and platform
- refresh-token family identifier
- hashed current refresh token
- creation, last-used, expiry, and revocation timestamps
- optional coarse security metadata such as application version

Users will later be able to list and revoke device sessions. Password changes, account recovery, suspected compromise, or explicit “sign out everywhere” actions may revoke all sessions.

### Password handling

Passwords will be processed through ASP.NET Core Identity's supported password hasher. Fasty will not implement custom password hashing or store reversible passwords.

The authentication system will support configurable password, lockout, and rate-limit policies. Login and recovery responses must avoid revealing whether an account exists.

### Authorization

Authentication establishes identity; it does not grant access to every resource.

Every note, synchronization, attachment, and administrative operation must perform server-side authorization based on the authenticated user and, later, organization/workspace membership. Client-supplied owner identifiers are never trusted as authorization evidence.

### Transport and secrets

- Authentication traffic requires HTTPS.
- Tokens, passwords, recovery codes, and cookie values must never appear in logs.
- Signing, encryption, and ASP.NET Core Data Protection keys must persist outside ephemeral containers.
- Persisted key material must be access-restricted and protected at rest.
- Production secrets must remain outside Git and container images.

### Future federation

If Fasty becomes public or enterprise-facing, authentication may move to or integrate with an OpenID Connect provider. Domain authorization and Fasty device-session concepts must remain sufficiently independent to allow this migration.

## Consequences

### Positive

- Browser credentials are protected from direct JavaScript access.
- Native clients receive a practical token flow without long-lived access tokens.
- Device sessions can be revoked independently.
- Refresh-token reuse can reveal likely token theft.
- ASP.NET Core Identity avoids custom credential handling.
- The design supports later MFA and federated identity.

### Negative

- Browser and native clients use different credential transport mechanisms.
- Refresh-token rotation and reuse detection require careful transactional implementation.
- Platform-specific secure storage integrations must be validated separately.
- Cookie authentication requires CSRF protections and same-origin deployment planning.

### Risks

- Incorrect cookie or CORS configuration could expose sessions. Mitigation: explicit origin allowlists, secure defaults, integration tests, and security review.
- Device secure-storage plugins may behave differently across platforms. Mitigation: platform-specific validation and failure handling.
- Persisted cryptographic keys could be lost during deployment. Mitigation: include them in protected operational backup and restoration procedures.
- A custom identity system could grow beyond safe scope. Mitigation: rely on framework primitives and reconsider an external identity provider before public launch.

## Validation

The proof of concept must demonstrate:

1. Browser login uses a secure HttpOnly cookie and no credential appears in browser storage.
2. Android or Windows login receives an access token and rotating refresh token.
3. A refresh token cannot be successfully reused after rotation.
4. Revoking one device session does not revoke unrelated devices.
5. Revoked credentials cannot call REST or establish an authorized SignalR connection.
6. Password hashes, plaintext tokens, and secrets do not appear in logs or database fields intended for plaintext data.
7. Data Protection keys survive container replacement.
8. Authorization tests prove that one user cannot access another user's notes or attachments.

## References

- Microsoft Learn: ASP.NET Core Identity configuration
- Microsoft Learn: Identity API authorization for web API backends
- Microsoft Learn: ASP.NET Core Data Protection and key persistence
- OWASP Authentication Cheat Sheet
- OWASP Session Management Cheat Sheet
- OWASP OAuth 2.0 Cheat Sheet
