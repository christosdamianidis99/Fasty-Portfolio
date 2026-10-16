# Fasty — Product Vision

## Product overview

Fasty is a cross-platform, local-first note-taking application designed to provide fast, reliable, and secure access to personal notes from any supported device.

A user should be able to create or edit a note on one device and access the updated note from another device shortly afterwards. The application should remain usable while offline and synchronize changes when connectivity becomes available again.

The initial version will be developed for personal use. However, the system will be designed professionally so it can later evolve into a public and enterprise-ready product without requiring a complete architectural rewrite.

## Vision statement

Fasty aims to provide a dependable, privacy-conscious, and responsive note-taking experience across mobile, desktop, and web platforms.

The product will prioritize:

- Reliable cross-device synchronization
- Offline availability
- Fast note editing
- Data ownership and exportability
- Security and privacy
- Simple organization
- Long-term maintainability

## Initial primary user

The initial primary user is the developer and owner of Fasty, using one authenticated account across multiple devices.

The application should support everyday activities such as:

- Writing quick notes from a phone
- Editing longer notes from a desktop computer
- Accessing notes through a browser
- Organizing study notes
- Storing programming ideas
- Maintaining project notes
- Creating personal checklists
- Accessing notes without an internet connection

## Long-term target users

Fasty may later serve:

- Individual consumers
- Students
- Software developers
- Researchers
- Small teams
- Businesses
- Enterprise organizations
- Privacy-conscious users
- Organizations requiring self-hosted deployment

These users are not part of the first release, but their potential requirements should be considered when making architectural decisions.

## Core value proposition

> A user can safely create, edit, and access notes from any supported device, even without an active internet connection, while Fasty reliably synchronizes changes across devices.

The application should feel immediate because normal note operations are performed locally. The server exists to synchronize, back up, and distribute data; it should not be required for every interaction.

## Product principles

### Local-first

Notes should be stored locally on each device. Fasty should remain functional when the server is unavailable, the device is offline, the connection is unstable, or synchronization is delayed.

### Reliable synchronization

Synchronization is a core product capability. The system should avoid data loss, retry safely, detect conflicts, synchronize incrementally, handle deletions correctly, and avoid duplicate operations.

### Privacy and security

Each user must only access their own data unless they deliberately share it. Security should cover authentication, authorization, encrypted transport, token storage, database isolation, backups, logging, and dependencies.

### Simplicity

Fasty should first become excellent at writing, storing, finding, synchronizing, and recovering notes. It should not initially attempt to reproduce every feature of large workspace products.

### Data ownership

Users should be able to export their data using standard formats such as Markdown, plain text, JSON, and ZIP archives. The internal format should not create unnecessary lock-in.

### Professional maintainability

The system should use clear module boundaries, automated tests, documented architecture decisions, reproducible deployment, version-controlled database migrations, continuous integration, monitoring, and tested backup procedures.

## Initial supported platforms

The first personal version will prioritize:

- Android
- Windows
- Web

The architecture should remain compatible with iOS, macOS, and Linux.

## Initial deployment model

For personal use, the backend may run on an always-on Lubuntu laptop using containers, PostgreSQL, a reverse proxy, private network access, and automated backups.

The application architecture must not depend on this machine. The same backend should later be deployable to a VPS, managed container platform, public cloud, or enterprise environment.

## Initial non-goals

The first development phase will not include:

- Real-time collaborative editing
- Shared team workspaces
- Enterprise administration
- Single Sign-On
- AI features
- OCR or handwriting recognition
- Public note publishing
- Complex document layout
- End-to-end encryption
- Browser extensions
- Calendar or email integrations
- Plugin marketplace
- Microservices

## Success criteria

The first personal release succeeds when:

1. The user can log in from Windows and Android.
2. A note created on one device appears on another.
3. Notes can be created and edited offline.
4. Offline changes synchronize after reconnection.
5. Retries do not create duplicate notes.
6. Conflicting edits do not silently destroy content.
7. Notes remain available while the backend is temporarily unavailable.
8. The server can be backed up and restored successfully.
9. Deployment is reproducible and documented.
10. Fasty is usable as the owner's regular personal notes application.
