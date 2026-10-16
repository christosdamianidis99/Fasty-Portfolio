# Fasty — Initial Scope

## Purpose

This document defines the boundaries of the first personal version of Fasty. Its purpose is to keep the project focused while preserving a clear path toward a public and enterprise-ready product.

## In scope for the personal MVP

### Account access

- Register a personal account
- Sign in and sign out
- Maintain authenticated sessions securely
- Use the same account on multiple devices
- Revoke a device session later in the personal phase

### Notes

- Create a note
- Edit a note
- Delete a note
- Restore a recently deleted note
- Autosave changes locally
- Display creation and modification timestamps
- Support plain text initially

### Local-first behavior

- Store notes locally on every device
- Open and edit notes without a network connection
- Queue local changes while offline
- Continue using the application if the backend is temporarily unavailable

### Synchronization

- Push local changes to the server
- Pull remote changes incrementally
- Synchronize across multiple devices
- Retry failed operations safely
- Avoid duplicate operations
- Represent deletions using tombstones
- Detect conflicting edits
- Preserve conflicting content for recovery
- Show a basic synchronization state

### Finding and organizing notes

- Search note titles and content
- Pin notes
- Sort by modification date
- Add simple tags or folders only after core synchronization is stable

### Data safety

- Encrypt network communication
- Restrict every note to its owner
- Create automated database backups
- Document and test restoration
- Provide a basic data export

### Initial platforms

- Android
- Windows
- Web

## Explicitly out of scope for the personal MVP

- Real-time collaborative editing
- Multi-user shared notes
- Team workspaces
- Organization administration
- Role-based permissions
- Enterprise SSO
- SCIM provisioning
- AI generation or summarization
- OCR
- Handwriting recognition
- Public publishing
- Advanced rich-text layout
- Tables and spreadsheet-like blocks
- Browser extensions
- Email or calendar integration
- Plugin systems
- Microservices
- End-to-end encryption
- Paid subscriptions

## Deferred but likely personal features

These features may be introduced after synchronization is proven reliable:

- Markdown
- Checklists
- Note history
- Attachments
- Tags and folders
- Reminders
- Dark mode
- Biometric application lock
- Better export options

## Scope change rule

A new feature should enter the MVP only when it is necessary to prove one of the following:

1. Cross-device synchronization works reliably.
2. Offline usage is practical.
3. User data is protected and recoverable.
4. Fasty can replace the owner's current personal notes application.

All other feature ideas should be recorded in the roadmap rather than added immediately.
