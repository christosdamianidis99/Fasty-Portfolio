# ADR-0001: Use Flutter for the cross-platform client

- **Status:** Accepted
- **Date:** 2026-07-22
- **Decision owners:** Fasty project maintainers
- **Scope:** Client applications for Android, Windows, web, and future iOS, macOS, and Linux support

## Context

Fasty is a local-first notes application whose defining requirement is access to the same synchronized notes from different kinds of devices.

The first personal version prioritizes:

- Android
- Windows
- Web

The architecture should also preserve a practical path toward:

- iOS
- macOS
- Linux

The client technology must support a responsive note editor, offline persistence, background synchronization, secure credential storage, adaptive layouts, automated testing, and long-term maintainability.

This decision is not based only on the maintainer's existing experience. The selected framework should also be suitable for a polished market-facing product and provide meaningful professional learning value.

## Decision drivers

The framework is evaluated against the following criteria:

1. First-class support for Android, Windows, and web.
2. A credible path to iOS, macOS, and Linux.
3. High code sharing across user interface, domain logic, and synchronization logic.
4. Strong offline database support.
5. Ability to build adaptive mobile and desktop interfaces.
6. Performance suitable for a note editor and large note collections.
7. Mature testing, profiling, accessibility, and internationalization tooling.
8. Sustainable ecosystem and active maintenance.
9. Reasonable access to platform-specific APIs.
10. Suitability for a solo developer and a possible future team.
11. Professional and market-relevant learning value.

## Options considered

### Option A: Flutter

Flutter provides supported deployment targets for Android, iOS, Windows, macOS, Linux, and modern web browsers. The same Dart codebase can share application logic, UI components, local persistence, networking, and much of the synchronization implementation.

#### Advantages

- Covers all of Fasty's planned platforms with one primary framework.
- Android, Windows, web, Linux, macOS, and iOS are directly represented in the official platform matrix.
- Strong custom UI and adaptive-layout capabilities.
- Mature local SQLite ecosystem.
- Good automated testing and profiling tools.
- Platform channels allow native Android, iOS, Windows, macOS, and Linux integration where required.
- Existing maintainer experience reduces initial delivery risk.
- Dart remains separate from the ASP.NET Core backend, reinforcing a clear client/server boundary.

#### Disadvantages

- Dart has a smaller general employment market than TypeScript, JavaScript, C#, Java, or Kotlin.
- Some third-party packages vary in quality across desktop and web.
- Browser applications may require platform-specific handling for local storage, secure session management, and background behavior.
- A highly platform-native visual appearance may require deliberate design work.

### Option B: Kotlin Multiplatform with Compose Multiplatform

Compose Multiplatform supports sharing UI and logic across Android, iOS, desktop, and web. Android, iOS, and desktop are stable; the Kotlin/Wasm web target remains beta at the time of this decision.

#### Advantages

- Excellent alignment with the maintainer's Java and Android background.
- Kotlin is highly relevant for modern Android development.
- Strong coroutines and type system.
- Ability to share logic while retaining native platform integration.
- Stable Android, iOS, and desktop targets.
- Strong educational value in native and multiplatform engineering.

#### Disadvantages

- The web target remains beta, while browser access is a core Fasty requirement.
- Cross-platform library support is less uniform than Flutter's for some client concerns.
- Desktop and web product delivery may require more platform-specific work.
- The project could be exposed to greater tooling and interoperability complexity for a solo developer.

#### Conclusion

This is the strongest alternative and should be reconsidered if Fasty later deprioritizes web or if Compose Multiplatform web reaches stable maturity before major implementation begins.

### Option C: React Native with React Native Web and desktop platforms

React Native is centered on Android and iOS. Windows and macOS are partner-maintained out-of-tree platforms, while web support is provided separately through React Native Web.

#### Advantages

- Large JavaScript and TypeScript ecosystem.
- Strong employment relevance.
- Mature Android and iOS community.
- Potential reuse of React knowledge for web development.

#### Disadvantages

- Fasty's complete platform matrix is assembled from multiple related projects rather than one uniformly supported framework.
- Windows, macOS, web, and Linux support do not have the same core status as Android and iOS.
- More platform-specific configuration and testing would be expected.
- Linux desktop is not a straightforward first-class target.

#### Conclusion

React Native is attractive for a mobile-first product, but less suitable for Fasty's equally important desktop and browser requirements.

### Option D: Tauri 2 with a web frontend

Tauri 2 supports Windows, macOS, Linux, Android, and iOS using a web frontend and a Rust-based native application layer.

#### Advantages

- Small desktop binaries and low resource usage.
- Strong security model and explicit native capabilities.
- Allows the use of a mainstream web stack such as TypeScript with React, Vue, or Svelte.
- Introduces Rust, which has strong systems-programming value.
- Strong desktop story.

#### Disadvantages

- Browser deployment is not the same artifact as the packaged Tauri application and still requires a separately considered web application.
- Mobile plugin and integration coverage is less mature than Flutter's overall mobile ecosystem.
- Requires managing web frontend concerns plus Rust and native platform integration.
- Increased complexity for a solo developer before synchronization itself is solved.

#### Conclusion

Tauri is a strong candidate for a desktop-first product or a future specialized Fasty desktop client, but it is not selected as the primary shared client framework.

### Option E: .NET MAUI

.NET MAUI supports Android, iOS, macOS through Mac Catalyst, and Windows. It does not provide a direct Linux desktop target or a normal browser deployment target.

#### Advantages

- Excellent reuse of the maintainer's C# and .NET knowledge.
- Shared codebase across supported mobile and desktop targets.
- Strong integration with the planned ASP.NET Core backend ecosystem.
- Native platform access and Microsoft tooling.

#### Disadvantages

- No direct web target for the same application.
- No official Linux desktop target.
- Supporting web would require a separate Blazor application or hybrid architecture.
- Sharing the client stack with the backend would reduce the opportunity to learn a distinct client ecosystem.

#### Conclusion

.NET MAUI is viable for a Windows-and-mobile-oriented product, but it does not satisfy Fasty's browser and Linux ambitions as cleanly as Flutter.

## Decision

Fasty will use **Flutter with Dart** as its primary cross-platform client framework.

The initial implementation will target:

1. Android
2. Windows
3. Web

The project will preserve compatibility with future iOS, macOS, and Linux builds, but those platforms will not block the first personal release.

The selection is based primarily on platform coverage, code sharing, local-first suitability, solo-developer efficiency, and the ability to produce a polished adaptive interface.

## Consequences

### Positive consequences

- Fasty can share most client code across its required platforms.
- The local data model and synchronization engine can be implemented once for native clients, with web-specific persistence adaptations where necessary.
- Android and Windows can be delivered without maintaining separate UI projects.
- The project gains a direct path to Linux, macOS, and iOS.
- The maintainer can focus effort on synchronization reliability and product quality rather than duplicating applications.

### Negative consequences

- Dart becomes a required project language.
- Web-specific constraints must be treated explicitly rather than assuming identical native behavior.
- Package selection must be checked against every supported target.
- Platform-specific capabilities may require native plugins or platform channels.
- The UI must be intentionally adaptive; a mobile layout simply stretched onto desktop is unacceptable.

## Implementation constraints

The following rules apply to the future Flutter project:

- Business and synchronization logic must not depend directly on widgets.
- The UI must read from local persistence rather than directly from remote API responses.
- Platform-specific implementations must be hidden behind interfaces.
- Every dependency must be evaluated for Android, Windows, and web support before adoption.
- Web persistence and authentication behavior must receive a separate design review.
- Android and Windows are the first native validation targets.
- Accessibility, keyboard navigation, window resizing, and responsive layouts are required engineering concerns.

## Validation plan

Before committing to the complete client architecture, a small technical proof of concept must demonstrate:

1. A Flutter project running on Android, Windows, and web.
2. A shared note model and repository interface.
3. Local persistence on Android and Windows.
4. An explicitly chosen browser persistence approach.
5. Communication with a minimal backend endpoint.
6. Automated tests running in continuous integration.
7. A basic adaptive note-list layout on phone and desktop widths.

Failure to achieve these goals without major platform-specific duplication will trigger a review of this ADR.

## Revisit conditions

This decision should be reviewed if:

- Flutter drops or materially weakens support for a required platform.
- A critical local database or editor capability cannot be implemented reliably.
- Browser requirements become dominant and Flutter web proves unsuitable.
- Compose Multiplatform web becomes stable and offers a clearly superior architecture before significant client code exists.
- Enterprise customers require deeply native platform behavior that cannot be delivered economically with Flutter.

## References

- Flutter supported deployment platforms: https://docs.flutter.dev/reference/supported-platforms
- Kotlin Multiplatform platform stability: https://kotlinlang.org/docs/multiplatform/supported-platforms.html
- Compose Multiplatform FAQ: https://kotlinlang.org/docs/multiplatform/faq.html
- React Native out-of-tree platforms: https://reactnative.dev/docs/0.78/out-of-tree-platforms
- Tauri 2 overview: https://v2.tauri.app/start/
- .NET MAUI supported platforms: https://learn.microsoft.com/en-us/dotnet/maui/supported-platforms
