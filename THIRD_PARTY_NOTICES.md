# Third-party notices and asset provenance

Fasty's original application code is licensed under MIT (see [LICENSE](LICENSE)). Its external dependencies and assets may have different licenses and attribution requirements; the MIT license does not supersede them.

- **SQLite database engine:** SQLite's core code is in the public domain; see [SQLite copyright information](https://www.sqlite.org/copyright.html). The bundled `client/web/sqlite3.wasm` must still be traced to its build/package source when redistributing a binary.
- **Flutter/Dart packages and .NET libraries:** Dependency manifests (`client/pubspec.yaml`, `client/pubspec.lock` and backend project files) identify third-party packages. Their licenses apply individually. Refer to the upstream package distributions.
- **Fasty logo, splash screens and generated application icons:** The branding files under `client/assets/branding/` and generated platform resources under `client/android`, `client/ios`, `client/macos`, `client/web`, and `client/windows` require confirmation of original authorship or redistribution rights. They are not independently licensed by this notice.

Do not assume that code licensing grants rights to third-party names, trademarks, illustrations, or other materials. For a commercial redistribution, independently confirm the origin and permissions for bundled assets and perform an appropriate legal review.
