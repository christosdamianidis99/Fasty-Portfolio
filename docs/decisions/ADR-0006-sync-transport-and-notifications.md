# ADR-0006 — Use REST/OpenAPI for durable synchronization and SignalR for notifications

- Status: Accepted
- Date: 2026-07-22
- Decision owners: Fasty maintainers

## Context

Fasty needs reliable cross-device synchronization across Android, Windows, and web. Devices may be offline, suspended, restarted, or disconnected for long periods. The synchronization mechanism must therefore remain correct without a persistent connection.

At the same time, active devices should receive remote changes quickly when another device edits a note.

## Decision drivers

- Durable and retry-safe synchronization
- Support for offline and suspended clients
- Explicit, testable API contracts
- Compatibility with Flutter on Android, Windows, and web
- Efficient near-real-time updates for active devices
- Simple self-hosting on Lubuntu
- Future cloud and enterprise scalability
- Clear separation between correctness and latency optimization

## Considered options

1. REST/OpenAPI only with periodic polling
2. SignalR as the complete synchronization channel
3. REST/OpenAPI for durable synchronization plus SignalR notifications
4. GraphQL subscriptions and mutations
5. gRPC streaming
6. Direct database realtime subscriptions

## Decision

Fasty will use versioned HTTPS REST endpoints as the authoritative synchronization interface and OpenAPI as the machine-readable contract.

SignalR will be used only as an optional notification channel. A notification means that newer server changes may be available and the client should run the normal pull synchronization process.

SignalR messages will not be treated as durable events, acknowledgements, or the source of truth.

## Authoritative synchronization API

The durable protocol will include operations conceptually similar to:

```http
POST /api/v1/sync/push
GET  /api/v1/sync/changes?after={cursor}&limit={limit}
GET  /api/v1/sync/bootstrap
```

The exact endpoint design may evolve, but the following rules are mandatory:

- Requests and responses are documented through OpenAPI.
- Push requests carry stable operation identifiers.
- Pull requests use server-generated cursors.
- Responses are paginated.
- Retrying the same operation is safe.
- Authentication and authorization apply to every request.
- Error responses use a stable documented format.
- The server does not require an active SignalR connection.

## SignalR notification model

Authenticated clients may connect to a SignalR hub after login.

A server notification should contain minimal non-sensitive information, for example:

```json
{
  "type": "changes_available",
  "latestCursor": 1948
}
```

On receipt, the client schedules or coalesces a normal synchronization run.

The notification should not contain full note text, attachment data, refresh tokens, or authoritative synchronization state.

## Client behaviour

Clients trigger synchronization when:

- The application starts or resumes
- Network connectivity returns
- A local operation enters the outbox
- A SignalR notification is received
- The user requests manual synchronization
- A low-frequency safety interval elapses while the app is active

Multiple triggers must be coalesced so that only one synchronization session operates on the same local account database at a time.

## Reconnection behaviour

After a SignalR reconnect, the client must perform an incremental pull from its last durable local cursor. It must not assume that no notifications were missed during disconnection.

If SignalR is unavailable, synchronization continues through startup, resume, connectivity, outbox, manual, and safety-poll triggers.

## API versioning

Public HTTP APIs will be versioned explicitly, initially through a path prefix such as:

```text
/api/v1/
```

Breaking changes require a new API version and a documented compatibility and deprecation policy before public release.

OpenAPI documents are generated in CI and treated as reviewable artifacts. Unexpected contract changes should fail contract verification.

## Serialization

JSON over HTTPS will be the initial wire format because it is easy to inspect, document, test, and consume from Flutter.

MessagePack or other binary formats may be evaluated later only when measurements show a meaningful benefit. Binary formats must not change the authoritative synchronization semantics.

## Security

- All remote transport uses TLS outside local development.
- SignalR connections require the same authenticated identity model as the REST API.
- Hub groups and connection routing must be based on server-validated identity, never client-supplied user IDs.
- Notifications contain minimal metadata.
- Rate limiting and connection limits will be added before public deployment.
- Access tokens must not be placed in logs.

## Observability

The system should measure:

- Push and pull request counts and latency
- Changes returned per synchronization page
- Duplicate operation retries
- Conflict rates
- SignalR connection and reconnection counts
- Notification-to-pull delay
- Synchronization failures by category
- Clients operating without SignalR

Logs should use correlation identifiers without recording note content or secrets.

## Consequences

### Positive

- Synchronization correctness does not depend on persistent connections.
- Active devices can receive updates quickly.
- The API is explicit, testable, and client-language independent.
- SignalR outages degrade latency rather than correctness.
- The backend can be self-hosted or moved to cloud infrastructure without redesigning the protocol.

### Negative

- Two communication mechanisms must be implemented and observed.
- The client needs trigger coalescing and reconnect logic.
- REST payloads may be less compact than specialized binary protocols.
- API versioning and contract compatibility require discipline.

### Risks

- Clients may trigger excessive sync runs. Mitigation: debounce and serialize synchronization sessions.
- Notifications may leak metadata. Mitigation: use minimal generic payloads and server-derived routing.
- SignalR support may vary across Flutter platforms. Mitigation: validate Android, Windows, and web early; retain polling and lifecycle triggers as fallback.
- Generated clients may hide important protocol behaviour. Mitigation: keep synchronization semantics documented independently of generated code.

## Validation

The proof of concept must demonstrate:

1. Device A creates a note and pushes it through REST.
2. Device B receives a SignalR notification and pulls the note through REST.
3. Device B disconnects from SignalR, misses several changes, reconnects, and catches up using its stored cursor.
4. The entire synchronization flow still works when SignalR is disabled.
5. Duplicate and out-of-order notifications do not create duplicate data.
6. OpenAPI generation runs automatically and the Flutter client can consume the documented contract.

## Reconsideration triggers

Revisit this decision if:

- Flutter platform support for SignalR is insufficient and cannot be addressed safely.
- Measurements show REST serialization or polling overhead is a material bottleneck.
- Real-time collaborative editing becomes a validated requirement.
- Enterprise network restrictions require a different notification strategy.

## References

- ASP.NET Core OpenAPI documentation
- ASP.NET Core SignalR documentation
- ADR-0005 — Local-first synchronization architecture
