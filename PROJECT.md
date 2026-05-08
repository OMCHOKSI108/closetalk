# CloseTalk — Project Guide for Developers

> **Your entry point to building CloseTalk.** Use this guide alongside the docs folder as your reference library. Every doc has a specific purpose — this file tells you which one to open and when.

---

## Table of Contents

1. [Project Overview](#project-overview)
2. [What We're Building (5-Minute Summary)](#what-were-building-5-minute-summary)
3. [Docs Map — Which File for What](#docs-map--which-file-for-what)
4. [Prerequisites & Tools](#prerequisites--tools)
5. [VS Code Setup](#vs-code-setup)
6. [Project Structure](#project-structure)
7. [Development Workflow](#development-workflow)
8. [Running the App Locally](#running-the-app-locally)
9. [How Each Doc Helps You Day-to-Day](#how-each-doc-helps-you-day-to-day)
10. [Coding Conventions & Standards](#coding-conventions--standards)
11. [Testing Strategy](#testing-strategy)
12. [Deployment Pipeline](#deployment-pipeline)
13. [Performance Targets (Keep This Visible)](#performance-targets-keep-this-visible)
14. [Quick Reference Cards](#quick-reference-cards)

---

## Project Overview

CloseTalk is a **production-grade chat app** for 100,000 users — inspired by WhatsApp but rebuilt for 2026. We fix every major WhatsApp problem: TCP head-of-line blocking, phone-dependent multi-device, media quality loss, manual moderation, and hard-to-scale architecture.

**Stack at a glance:**

| Layer | Choice |
|---|---|
| Frontend | Flutter (Android, iOS, Web, macOS, Linux, Windows) |
| Backend | Node.js 25 or Go 1.26 on ECS Fargate |
| Transport | WebTransport (QUIC) + SSE/HTTP-3 + WebSocket fallback |
| Databases | Neon PostgreSQL (metadata) + ScyllaDB (messages) + Valkey (cache) + Elasticsearch (search) |
| AI | Amazon Bedrock AgentCore (moderation, assistant, translation) |
| Infra | AWS (Global Accelerator, CloudFront, S3, SQS, SNS, EventBridge) |

---

## What We're Building (5-Minute Summary)

Read these three docs first — in this order:

1. **`docs/whatsapp-gap-analysis.md`** — Understand what WhatsApp got wrong and what we fix. This is our product's reason for existing.
2. **`docs/product-vision.md`** — See what the final product looks and feels like from a user's perspective.
3. **`docs/architecture-flow.md`** — See the 19 Mermaid diagrams showing exactly how every flow works (auth, messaging, sync, etc.).

Then when you need details, open the relevant doc from the map below.

---

## Docs Map — Which File for What

```
PROJECT.md  ← YOU ARE HERE (entry point, start here)
│
├── docs/whatsapp-gap-analysis.md     → "Why are we building this?"
│                                       Read when: anyone asks why we chose X over Y.
│
├── docs/product-vision.md            → "What does the final app look like?"
│                                       Read when: you need user-facing feature details.
│
├── docs/architecture-flow.md         → "How does this feature work end-to-end?"
│                                       19 Mermaid sequence/flow diagrams.
│                                       Read when: implementing a feature (auth, message, search, etc.)
│
├── docs/architecture.md              → "What services exist and how do they connect?"
│                                       Read when: designing a new service or debugging cross-service issues.
│
├── docs/requirements.md              → "What are the exact requirements and priorities?"
│                                       Read when: writing code for a feature — check P0/P1/P2.
│
├── docs/planning.md                  → "What phase are we in and what's next?"
│                                       Read when: sprint planning or deciding what to work on.
│
├── docs/security.md                  → "How do we handle auth, encryption, compliance?"
│                                       Read when: implementing auth, storage, or preparing app store submission.
│
├── docs/multi-device-sync.md         → "How does device linking, sync, and revocation work?"
│                                       Read when: implementing multi-device features.
│
└── docs/closetalk-architecture.md    → "Full 2026 architectural standard document"
                                        Read when: you want the original research paper this project is based on.
```

---

## Prerequisites & Tools

### Required

| Tool | Version | Why |
|---|---|---|
| **Flutter SDK** | 3.11+ | Build the frontend for all platforms |
| **Dart** | 3.11+ | Flutter's language |
| **VS Code** | Latest | Recommended IDE |
| **Git** | 2.x | Version control |
| **Docker** | Latest | Run backend locally |
| **AWS CLI** | Latest | Deploy infrastructure |
| **GitHub CLI (`gh`)** | Latest | PRs, repo management |

### VS Code Extensions

Install these for CloseTalk development:

```
Name: Flutter
ID: Dart-Code.flutter
→ Flutter widget autocomplete, debug, hot reload

Name: Dart
ID: Dart-Code.dart-code
→ Dart language support

Name: Markdown Preview Mermaid Support
ID: bierner.markdown-mermaid
→ Preview the architecture flow diagrams in VS Code

Name: YAML
ID: redhat.vscode-yaml
→ YAML validation (pubspec.yaml, Dockerfiles)

Name: GitLens
ID: eamodio.gitlens
→ Git blame, history annotations

Name: Prettier
ID: esbenp.prettier-vscode
→ Code formatting

Name: Error Lens
ID: usernamehw.errorlens
→ Inline error display
```

### VS Code Settings (`.vscode/settings.json`)

```json
{
  "editor.formatOnSave": true,
  "editor.defaultFormatter": "esbenp.prettier-vscode",
  "dart.checkForNewVersions": false,
  "dart.openDevTools": "flutter",
  "files.autoSave": "onFocusChange",
  "editor.minimap.enabled": false,
  "workbench.colorTheme": "Default Dark+",
  "terminal.integrated.defaultLocation": "editor"
}
```

---

## VS Code Setup

### Step 1: Clone & Open

```bash
git clone https://github.com/OMCHOKSI108/closetalk.git
cd closetalk
code .
```

### Step 2: Install Flutter Dependencies

```bash
cd closetalk_app
flutter pub get
```

VS Code will auto-detect the Flutter project. You should see a Flutter debug configuration appear in the Run & Debug panel.

### Step 3: Verify Setup

```bash
flutter doctor          # Check Flutter installation
flutter devices         # List available devices (emulator, web, desktop)
```

### Step 4: Create a Branch for Your Feature

```bash
git checkout -b feat/your-feature-name
```

Branch naming convention:
- `feat/` — new feature (e.g., `feat/message-search`)
- `fix/` — bug fix (e.g., `fix/typing-indicator-delay`)
- `docs/` — documentation (e.g., `docs/api-reference`)
- `refactor/` — code refactoring (e.g., `refactor/auth-service`)

---

## Project Structure

```
closetalk/
│
├── closetalk_app/             ← FLUTTER APP (you'll spend most time here)
│   ├── lib/
│   │   ├── main.dart              ← App entry point
│   │   ├── app.dart               ← MaterialApp widget
│   │   ├── config/                ← App configuration, constants
│   │   ├── models/                ← Data models (User, Message, Chat, etc.)
│   │   ├── services/              ← API clients, WebTransport, auth
│   │   ├── providers/             ← State management (Riverpod / BLoC)
│   │   ├── screens/               ← Full page screens
│   │   │   ├── auth/              ← Login, signup, recovery
│   │   │   ├── chat/              ← Chat list, chat detail
│   │   │   ├── group/             ← Group create, manage
│   │   │   ├── status/            ← Stories, status
│   │   │   ├── channel/           ← Broadcast channels
│   │   │   ├── settings/          ← Privacy, profile, devices
│   │   │   └── search/            ← Full-text search
│   │   ├── widgets/               ← Reusable components
│   │   └── l10n/                  ← Localization files
│   ├── test/                      ← Unit and widget tests
│   ├── android/                   ← Android platform
│   ├── ios/                       ← iOS platform
│   ├── web/                       ← Web platform
│   ├── linux/                     ← Linux platform
│   ├── macos/                     ← macOS platform
│   └── windows/                   ← Windows platform
│
├── closetalk_backend/          ← BACKEND SERVICES (Node.js or Go)
│   ├── services/
│   │   ├── message-service/       ← Send, receive, history
│   │   ├── auth-service/          ← Login, register, JWT
│   │   ├── presence-service/      ← Online, typing, status
│   │   ├── media-service/         ← Upload URLs, thumbnails
│   │   ├── search-service/        ← Elasticsearch indexing + query
│   │   ├── status-service/        ← Stories/status CRUD
│   │   ├── channel-service/       ← Broadcast channels
│   │   ├── notification-service/  ← Push notifications
│   │   ├── moderation-service/    ← AI content filtering
│   │   └── ai-service/            ← Assistant, translation, summaries
│   ├── infrastructure/            ← Terraform, CloudFormation
│   └── tests/
│
├── closetalk_frontend/         ← ADMIN DASHBOARD (React or Flutter Web)
│   ├── pages/
│   │   ├── users/                ← User management
│   │   ├── moderation/           ← Moderation queue
│   │   ├── analytics/            ← Metrics, charts
│   │   ├── feature-flags/        ← Flag management
│   │   └── audit-log/            ← Audit trail
│   └── ...
│
└── docs/                        ← Full documentation library
    ├── architecture.md              ← System architecture
    ├── architecture-flow.md         ← 19 Mermaid flow diagrams
    ├── whatsapp-gap-analysis.md     ← Why we exist
    ├── product-vision.md            ← User-facing product description
    ├── requirements.md              ← All P0/P1/P2 requirements
    ├── planning.md                  ← Phased checklist
    ├── security.md                  ← Security, compliance, App Store
    ├── multi-device-sync.md         ← Multi-device protocol
    └── closetalk-architecture.md    ← Original PDF standard
```

---

## Development Workflow

```
1. Pick a task from docs/planning.md
       │
2. Open docs/requirements.md → find the requirement ID (e.g., F3.1)
       │
3. Open docs/architecture-flow.md → find the relevant flow diagram
       │
4. Open docs/architecture.md → understand which services are involved
       │
5. Write code (Flutter app / backend service)
       │
6. Write tests (unit + widget + integration)
       │
7. Run lint + format + test
       │
8. Commit → push → open PR
       │
9. Tag the PR with the requirement ID (e.g., "Closes F3.1")
```

### Example: Building Group Chat Creation

Let's walk through a real example so you understand how the docs connect.

**Step 1 — Check the checklist:**
Open `docs/planning.md` → Phase 3 → Group Chats → "Group chat (create, join, leave)"

**Step 2 — Check the requirements:**
Open `docs/requirements.md` → F3.1–F3.8. You see:
- F3.1: Users shall create groups with name, description, avatar (P1)
- F3.2: Users shall invite others via link or direct add (P1)
- F3.3: Admins shall add/remove members (P1)
- F3.5: Groups up to 1,000 members (P1)

**Step 3 — Understand the flow:**
Open `docs/architecture-flow.md` → the architecture diagrams show how Group Service connects to PostgreSQL (Neon) for group metadata, and how invites flow via deep links.

**Step 4 — Check the architecture:**
Open `docs/architecture.md` → Group Service is in the Application Layer, connected to Neon PostgreSQL.

**Step 5 — Write code:**
Now you know exactly what to build, what it connects to, and how it should behave.

**Step 6 — Test:**
```bash
cd closetalk_app
flutter test test/widgets/group_create_test.dart
```

---

## Running the App Locally

### Flutter App (Frontend)

```bash
cd closetalk_app

# Run on Android emulator
flutter run

# Run on iOS simulator
flutter run -d ios

# Run on Chrome (web)
flutter run -d chrome

# Run on Windows desktop
flutter run -d windows

# Run on macOS desktop
flutter run -d macos

# Run on Linux desktop
flutter run -d linux
```

### Hot Reload

Flutter's hot reload is your best friend:
- Save a file → changes appear in < 1 second
- State is preserved (no widget rebuild)
- If hot reload doesn't work, use hot restart (Cmd+Shift+F5)

### Backend (Locally with Docker)

```bash
cd closetalk_backend

# Start all services
docker-compose up

# Start a specific service
docker-compose up auth-service message-service

# Run tests
docker-compose run --rm test
```

### Backend (Without Docker)

```bash
cd closetalk_backend/services/auth-service
npm install    # if Node.js
npm run dev

# or
go mod tidy    # if Go
go run .
```

---

## How Each Doc Helps You Day-to-Day

### When starting a new feature:
1. `docs/planning.md` → Is this in the plan? What phase?
2. `docs/requirements.md` → What are the exact requirements and priority?
3. `docs/architecture-flow.md` → What's the flow? (find the Mermaid diagram)
4. `docs/architecture.md` → What services do I need to touch?
5. `docs/multi-device-sync.md` → (if multi-device) How does sync work?

### When fixing a bug:
1. `docs/architecture-flow.md` → Trace the flow to find where the bug is
2. `docs/architecture.md` → Check which service/DB is involved
3. `docs/requirements.md` → Confirm the expected behavior

### When reviewing a PR:
1. `docs/requirements.md` → Does this meet the requirement?
2. `docs/architecture-flow.md` → Does the implementation match the flow?
3. `docs/security.md` → Are there security implications?
4. `docs/planning.md` → Does this belong in the current phase?

### When preparing for app store submission:
1. `docs/security.md` → PlayStore & App Store Compliance section
2. Go through the checklist: privacy policy, data safety, permissions, etc.

### When asked "why did we choose X over Y?":
1. `docs/whatsapp-gap-analysis.md` → This doc exists exactly for this question

---

## Coding Conventions & Standards

### Flutter / Dart

```dart
// DO: Use named constructors
const Message.fromJson(Map<String, dynamic> json)
    : id = json['id'],
      content = json['content'];

// DO: Use const constructors where possible
const SizedBox(height: 16);

// DO: Prefer immutable models (freezed or manual)
@immutable
class User {
  final String id;
  final String displayName;
}

// DON'T: Use `var` for everything — be explicit with types
// DON'T: Use `dynamic` unless absolutely necessary
// DON'T: Use `print()` — use `log()` from `package:logging`
```

### State Management

- Use **Riverpod** or **BLoC** (decide early, stick to it)
- Keep business logic in providers/blocs, not in widgets
- One provider/bloc per feature module

### Naming

| Convention | Example |
|---|---|
| Files: `snake_case` | `message_service.dart` |
| Classes: `PascalCase` | `class MessageService` |
| Functions: `camelCase` | `void sendMessage()` |
| Variables: `camelCase` | `final messageContent` |
| Constants: `camelCase` | `static const maxRetries = 3` |
| Private: `_camelCase` | `void _handleResponse()` |

### Git Commit Style

Follow the existing commit style (see `git log`). Pattern:

```
type(scope): brief description

- Bullet point details
- Reference issues/requirements
```

Types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`

Examples:
```
feat(groups): implement group creation with invite links

- GroupService handles create/join/leave
- Shareable invite links with expiry
- Closes F3.1, F3.2
```

```
fix(messages): resolve typing indicator delay on poor networks

- WebTransport datagram now sends every 200ms instead of 500ms
- Buffered events are flushed on connection restore
```

---

## Testing Strategy

| Test Type | What | When | Command |
|---|---|---|---|
| **Unit tests** | Test models, services, utilities | Every PR | `flutter test test/unit/` |
| **Widget tests** | Test individual widgets in isolation | Every PR | `flutter test test/widgets/` |
| **Integration tests** | Test full user flows | Before release | `flutter test test/integration/` |
| **Golden tests** | Visual regression tests | Before release | `flutter test --update-goldens` |

### Requirements

```bash
# Run all Flutter tests
cd closetalk_app
flutter test

# Run with coverage
flutter test --coverage
genhtml coverage/lcov.info -o coverage/html

# Run a specific test file
flutter test test/widgets/chat_list_test.dart

# Run backend tests
cd closetalk_backend
npm test            # Node.js
go test ./...       # Go
```

---

## Deployment Pipeline

```
Git push → GitHub Actions
    │
    ├── Lint (flutter analyze, go vet, npm lint)
    ├── Test (flutter test, go test, npm test)
    ├── Build (flutter build, docker build)
    ├── Scan (Trivy for vulnerabilities)
    │
    ├── ✅ Staging (auto-deploy on main branch)
    │       └── E2E tests
    │
    └── ✅ Production (manual approval)
            └── Smoke tests
```

See `docs/architecture.md` → Deployment Architecture section for the full pipeline.

---

## Performance Targets (Keep This Visible)

When you write code, keep these numbers in mind:

| Action | Target |
|---|---|
| Message deliver (same region) | < 50ms p99 |
| Message deliver (global) | < 100ms p99 |
| Typing indicator | < 20ms |
| API response (non-real-time) | < 200ms p95 |
| Search across 50K messages | < 500ms p95 |
| App cold start | < 2 seconds |
| Image load (from CDN) | < 1 second |
| Story load | < 1 second |
| Link new device | < 10 seconds |
| Media upload (presigned URL) | < 50ms |

---

## Quick Reference Cards

### Where to Put New Code

```
Flutter screens          → closetalk_app/lib/screens/{feature}/
Flutter widgets          → closetalk_app/lib/widgets/
Flutter services         → closetalk_app/lib/services/
Flutter models           → closetalk_app/lib/models/
Backend services         → closetalk_backend/services/{service-name}/
Backend infrastructure   → closetalk_backend/infrastructure/
Admin dashboard pages    → closetalk_frontend/pages/{feature}/
Documentation            → docs/{topic}.md
```

### Useful VS Code Shortcuts

| Shortcut | Action |
|---|---|
| `F5` | Start debug |
| `Ctrl+Shift+F5` | Hot restart |
| `Ctrl+S` | Hot reload (auto) |
| `Ctrl+Shift+P` → "Flutter: Select Device" | Change target device |
| `Ctrl+Shift+P` → "Dart: Open DevTools" | Flutter DevTools suite |
| `Ctrl+\`` | Toggle terminal |
| `Alt+Up/Down` | Move line up/down |

### Daily Commands

```bash
# Start coding day
git pull
cd closetalk_app && flutter pub get
code .

# Before committing
flutter analyze                          # Lint check
flutter test                             # Run tests
git add -A && git commit -m "type: msg"  # Commit

# Before pushing
git pull --rebase                        # Sync with main
flutter test                             # Re-run tests
git push
```

---

## Need Help?

1. Check the relevant doc (see [Docs Map](#docs-map--which-file-for-what))
2. Search the codebase: `rg "keyword"` or VS Code global search
3. Open an issue on GitHub
4. Ask in the team chat

---

*This project guide is your map. The docs folder is your reference library. Keep both open while you code.*
