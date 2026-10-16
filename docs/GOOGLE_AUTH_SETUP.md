# Google authentication setup

Fasty accepts Google ID tokens for sign-in and for linking a Google identity to an existing account. The Flutter client supports Android through Google's native sign-in SDK and Windows/Linux through a system browser and a local loopback callback. Password sign-in remains available.

## Google Cloud clients

In [Google Auth Platform Clients](https://console.cloud.google.com/auth/clients), choose or create the project and complete the app registration. Keep the audience in Testing while validating the beta and add the Google accounts that will test sign-in under [Audience](https://console.cloud.google.com/auth/audience).

Create these OAuth clients in the same Google Cloud project:

1. **Android client** registered for `com.christosdamianidis.fasty` with the signing certificate SHA fingerprints for each build you test or release.
2. **Web application client** for Android's `serverClientId`. Use this web client ID as `FASTY_GOOGLE_SERVER_CLIENT_ID`.
3. **Desktop application client** for Windows/Linux. Use its client ID as `FASTY_GOOGLE_DESKTOP_CLIENT_ID`. The desktop flow uses the system browser, an ephemeral `127.0.0.1` callback, state validation, and PKCE.

The backend validates the token signature and audience. The Compose configuration maps `FASTY_GOOGLE_SERVER_CLIENT_ID` and `FASTY_GOOGLE_DESKTOP_CLIENT_ID` to the backend's accepted audiences. Set those IDs in the server's ignored `infrastructure/.env`, then set `FASTY_GOOGLE_ENABLED=true` and redeploy the API. Google auth stays disabled while `FASTY_GOOGLE_ENABLED=false`. Do not put a desktop client secret in the Flutter app.

For local API runs outside Compose, use `Authentication__Google__Enabled=true`, `Authentication__Google__ClientIds__0=<web-client-id>`, and `Authentication__Google__ClientIds__1=<desktop-client-id>` as environment variables.

To see the Android debug signing fingerprints for the current machine, run:

```bash
keytool -list -v -alias androiddebugkey \
  -keystore ~/.android/debug.keystore -storepass android -keypass android
```

Register release signing fingerprints separately. The debug fingerprint is not suitable for a release APK.

Pass the client IDs at Flutter build or run time:

```bash
flutter run -d android \
  --dart-define=FASTY_GOOGLE_SERVER_CLIENT_ID=<web-client-id>

flutter run -d windows \
  --dart-define=FASTY_GOOGLE_DESKTOP_CLIENT_ID=<desktop-client-id>
```

Use the same `--dart-define` values for release builds. On Ubuntu, use `-d linux` with the desktop client ID for development. Without the appropriate client ID, the UI explains that Google sign-in is not configured and leaves password sign-in available.

## Manual checks

With real Google client IDs and a reachable backend, verify these flows on Android and Windows:

- A new Google identity signs in and creates one Fasty account.
- A second Google sign-in reuses that account and its notes.
- A Google identity with the email of an existing password account receives the linking guidance, then can sign in with the password and link Google in Settings.
- Linking a Google identity with a different email fails without changing the current Fasty session.
- Closing or denying the Google browser prompt leaves the current Fasty session unchanged.
