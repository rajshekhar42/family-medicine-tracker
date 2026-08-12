# AGENTS.md

This file guides any AI coding agent (or human contributor) working in this repository. Read it before generating, editing, or refactoring code. When in doubt, favor the conventions here over generic defaults.

---

## 1. Tech Stack

| Layer | Choice |
|---|---|
| Framework | Flutter (Dart) |
| Authentication | Firebase Auth (Google Sign-In) |
| Remote data store | Google Sheets, accessed via the Google Drive/Sheets API |
| Local storage | SQLite (via `sqflite` or `drift`) |
| State management | Riverpod (preferred) — Bloc acceptable only if already established in a feature |
| Dependency injection | Riverpod providers / `get_it` for non-widget-tree services |

Offline-first is a core assumption: SQLite is the source of truth on-device; Google Sheets (via the Drive API) is the sync/remote layer, not a live dependency the UI blocks on.

---

## 2. Core Design Principles

Apply these consistently, in priority order:

1. **Single Responsibility** — a class/widget/function does one thing. If a widget both fetches data, transforms it, and renders UI, split it.
2. **Separation of Concerns** — UI never talks to SQLite or the Google Sheets API directly. It goes through a repository interface.
3. **Dependency Inversion** — domain/business logic depends on abstractions (repository interfaces), not concrete data sources. Concrete `SqliteX` / `GoogleSheetsX` implementations are injected.
4. **DRY, but not premature** — extract shared logic once it's used a second time, not before.
5. **KISS / YAGNI** — no speculative abstraction layers for features that don't exist yet.
6. **Immutability by default** — models/entities are immutable (`final` fields, `copyWith`), especially anything crossing an isolate or stored in state.
7. **Fail loud in dev, fail soft in prod** — see Error Handling below.

---

## 3. Architecture

Clean Architecture, three layers per feature:

```
presentation  →  domain  →  data
   (UI,           (entities,     (repositories impl,
   widgets,        use cases,     local/remote
   providers)      repo          datasources)
                   interfaces)
```

Rules:
- **Presentation** depends on **domain** only (never imports `data/`).
- **Domain** has zero Flutter/Google API/SQLite imports — pure Dart. This is what makes business logic testable without a device/emulator.
- **Data** implements domain's repository interfaces and is the only layer allowed to import `sqflite`, `googleapis` (Sheets/Drive), etc.

---

## 4. Folder Structure

Feature-first, with shared code in `core/`:

```
lib/
├── core/
│   ├── constants/
│   ├── errors/               # Failure/Exception types
│   ├── theme/
│   ├── utils/                # date/time, formatters, validators
│   └── di/                   # provider overrides, service locator setup
│
├── features/
│   └── <feature_name>/                 e.g. medications, profiles, history
│       ├── data/
│       │   ├── datasources/
│       │   │   ├── <feature>_local_datasource.dart    # sqflite/drift queries
│       │   │   └── <feature>_remote_datasource.dart   # Google Sheets/Drive API calls
│       │   ├── models/                # DTOs with fromMap/toMap, fromJson/toJson
│       │   └── repositories/
│       │       └── <feature>_repository_impl.dart
│       ├── domain/
│       │   ├── entities/              # plain Dart classes, no serialization concerns
│       │   ├── repositories/          # abstract interfaces
│       │   └── usecases/              # one class per use case, single `call()` method
│       └── presentation/
│           ├── providers/             # Riverpod providers/notifiers
│           ├── screens/
│           └── widgets/
│
├── app.dart                # MaterialApp, routing, top-level providers
└── main.dart               # bootstrapping only (Firebase Auth init, Google API client init, DB open, runApp)
```

A new feature always gets its own folder with this internal shape — don't bolt feature logic onto an existing unrelated feature folder for convenience.

---

## 5. Data Layer & Sync Strategy

Since every feature here straddles local (SQLite) and remote (Google Sheets, via the Drive API) storage, follow this pattern by default unless a feature is explicitly local-only or remote-only:

- **SQLite is the source of truth for the UI.** Screens read from local DB via the repository; they never wait on a network call to render.
- **Every syncable table carries sync metadata:**
  - `updated_at` (UTC epoch millis, not local time — see Timezones below)
  - `is_dirty` (bool) — set on local write, cleared once pushed to the Google Sheet
  - `remote_row_ref` (nullable) — set once the record has a corresponding row in the Google Sheet (e.g. the sheet's primary-key column value, per the schema's ID convention)
- **Sync direction:** local write → mark dirty → background sync pushes dirty rows to the Google Sheet via the Sheets API → on success, clear dirty flag and store `remote_row_ref`. Google Sheets has no push-based realtime listener like Firestore, so pulling remote changes is poll-based: trigger a pull sync on app resume and on a periodic timer, read the sheet, and upsert into SQLite. Never let the same field be written by both directions in the same sync pass (avoid write loops).
- **Conflict resolution:** default to last-write-wins on `updated_at` unless a feature's spec says otherwise. If a feature needs merge-level resolution (e.g. concurrent edits from two family members to the same record), that must be called out explicitly in the feature's design notes before implementation — don't silently assume last-write-wins for shared/multi-user data.
- **Multi-profile data:** every local table for user-owned data includes a `profile_id` foreign key. Queries are always scoped by the active profile; there is no implicit "current user" global — pass `profile_id` explicitly through the repository/use case call, don't read it from a singleton inside the data layer.
- **Timezones:** store all timestamps in UTC in both SQLite and the Google Sheet. Convert to the profile's stored timezone only at the presentation layer, using a single shared utility (`core/utils/`), never ad hoc `DateTime` math scattered across widgets.

---

## 6. State Management

- One `Notifier`/`StateNotifier` (Riverpod) per screen or cohesive UI concern — not one giant app-wide state object.
- Providers live in the feature's `presentation/providers/` folder, not in `core/`, unless genuinely cross-feature (e.g. active profile, auth state).
- Widgets read state via `ref.watch`; they trigger actions via `ref.read(...).method()`. Widgets never construct repositories or datasources directly.
- Async state uses `AsyncValue` (loading/data/error) rather than nullable fields plus a separate `isLoading` bool.

---

## 7. Naming Conventions

| Item | Convention | Example |
|---|---|---|
| Files | `snake_case.dart` | `medication_repository_impl.dart` |
| Classes | `UpperCamelCase` | `MedicationRepositoryImpl` |
| Variables/functions | `lowerCamelCase` | `getActiveMedications()` |
| Abstract repository interfaces | `<Feature>Repository` | `MedicationRepository` |
| Implementations | `<Feature>RepositoryImpl` | `MedicationRepositoryImpl` |
| Use cases | verb-first, single responsibility | `GetActiveMedications`, `MarkDoseTaken` |
| Riverpod providers | `<thing>Provider` | `medicationListProvider` |
| SQLite tables/columns | `snake_case` | `medicine_log`, `taken_at` |
| Google Sheet tab names | `PascalCase`, matching the schema/column headers — keep consistent app-wide | `Medicines`, `Schedule`, `MedicineLog` |

---

## 8. Error Handling

- Domain layer returns `Either<Failure, T>` (or a sealed `Result` type) from use cases — no throwing exceptions across layer boundaries.
- Data layer catches SDK-specific exceptions (`SqfliteException`, `FirebaseAuthException`, Google API client exceptions from the Sheets/Drive calls) at the datasource boundary and maps them to domain `Failure` types. Presentation code never catches a Firebase, Google API, or SQLite exception directly.
- User-facing errors are always mapped to a readable message; raw exception text/stack traces never reach the UI.
- Log unexpected errors (not user-input validation errors) through a single logging utility in `core/`, not scattered `print()`/`debugPrint()` calls.

---

## 9. Testing

- **Domain layer:** unit tests, no mocks needed beyond repository interfaces (fakes/mocks via `mocktail` or similar). This layer should have the highest coverage since it holds the actual business rules.
- **Data layer:** test repository implementations against an in-memory SQLite instance; mock the Google Sheets/Drive datasource.
- **Presentation:** widget tests for critical flows (add medication, take/skip dose, sync conflict banner if applicable). Don't chase 100% widget coverage — prioritize logic-heavy widgets over pure layout.
- New use cases and repository methods should ship with at least one test in the same PR, not as a follow-up.

---

## 10. Code Style & Linting

- Follow `flutter_lints` / `very_good_analysis` — don't disable lint rules inline without a comment explaining why.
- Prefer `const` constructors wherever possible.
- No business logic inside `build()` methods — extract to a provider, use case, or plain helper function.
- Keep widget files focused: if a `build()` method exceeds ~100 lines or nests more than 3–4 levels of widgets, extract sub-widgets.

---

## 11. Git & Commit Conventions

- Conventional commits: `feat:`, `fix:`, `refactor:`, `test:`, `chore:`, `docs:`.
- One feature/fix per PR where reasonably possible; avoid bundling unrelated refactors with feature work.
- Commit messages describe *why*, not just *what*, when the change isn't self-evident from the diff.

---

## 12. Guidelines Specifically for AI Agents Working in This Repo

- **Before adding a new dependency**, check if an existing one in `pubspec.yaml` already covers the need.
- **Before creating a new file**, check whether the folder structure above already has an obvious home for it — don't invent new top-level folders without strong reason.
- **When editing the data layer**, confirm which direction (local→remote or remote→local) a change affects, and don't introduce a path where the same field can be overwritten by both directions in the same sync pass.
- **When touching anything date/time-related**, use `core/utils` conversion helpers — never call `DateTime.now()` directly inside domain or data layers (inject a clock/time provider so logic stays testable).
- **Never hardcode a `profile_id`** or assume a single-user context — this app is explicitly multi-profile.
- **Don't silently change conflict-resolution behavior** for synced data; flag it if a feature seems to need something beyond last-write-wins.
- **Match existing patterns in the nearest sibling feature** before introducing a new pattern — consistency across features matters more than local optimization.

For any temporary files you are creating for your work, create it only in the 'tmp' folder and do not polute the workspace.

