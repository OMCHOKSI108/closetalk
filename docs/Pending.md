# CloseTalk — Pending Features

> **Purpose:** Track every non-AI feature that still needs implementation. AI features excluded per scope.  
> **Legend:** `[ ]` = not started, `[~]` = partial, `[x]` = done  
> **Last updated:** 2026-05-11

---

## F1 — User Management

| ID | Feature | Status | Backend | Flutter |
|----|---------|--------|---------|---------|
| F1.4 | **Account Deletion** | [ ] | `DELETE /auth/account` — soft delete user, invalidate all sessions, mark as deleted_at | Account deletion button in Settings, confirmation dialog |
| F1.4a | Deletion: data cleanup | [ ] | Remove user from conversations, groups, contacts; anonymize messages | — |

## F2 — Contact Discovery & Privacy

| ID | Feature | Status | Backend | Flutter |
|----|---------|--------|---------|---------|
| F2.1 | **Hash-based Contact Discovery** | [ ] | `POST /contacts/discover` — accept SHA-256 hashed phone numbers, return matched users | Contact import screen with phone permission flow |
| F2.2 | **Last Seen Privacy** | [ ] | `GET/PUT /users/settings` — read/write privacy settings | `privacy_settings_screen.dart` — toggle visibility |
| F2.3 | **Profile Photo Privacy** | [ ] | Enforce `profile_photo_visibility` in profile queries | Same screen as F2.2 |
| F2.4 | **Read Receipts** | [ ] | Enforce `read_receipts` per-chat overrides in read status broadcasts | Toggle in Settings |
| F2.5 | **Group Add Permission** | [ ] | Check `group_add_permission` before allowing others to add user to group | — |
| F2.7 | **Block Enforcement** | [ ] | Check blocks table before message delivery, profile view, last_seen | Enforce in UI (hide blocked) |

## F3 — Messaging

| ID | Feature | Status | Backend | Flutter |
|----|---------|--------|---------|---------|
| F3.2 | **Media Pipeline (S3)** | [ ] | `POST /media/upload-url`, `POST /media/confirm`, Lambda for thumbnails/virus scan | Upload flow with progress, thumbnails, full-screen viewer |
| F3.8 | **Full-Text Search (Elasticsearch)** | [ ] | `search-service/` with Elasticsearch, index messages, relevance scoring, cross-chat search | `search_screen.dart` with filters, highlights, cross-chat results |
| F3.9 | **Chat History Export** | [ ] | `GET /export/chat/{chatId}` — JSON export | Export button in chat info / settings |
| F6.5 | **Message Mentions (@mentions)** | [ ] | Parse @mentions in message content, store mentioned_user_ids, notify mentioned users | Show @mention in blue, autocomplete in input bar |

## F5 — Group Chats

| ID | Feature | Status | Backend | Flutter |
|----|---------|--------|---------|---------|
| F5.7 | **Group Retention Policy Enforcement** | [ ] | Periodic job to delete messages older than `message_retention` per group | Display retention info in group settings |
| F5.8 | **Disappearing Messages UI** | [ ] | — (backend already handles disappear_after, cleanup goroutine runs) | Timer picker in group settings + chat detail, "Disappearing messages" indicator |

## F6 — Real-Time Features

| ID | Feature | Status | Backend | Flutter |
|----|---------|--------|---------|---------|
| F6.3 | **Push Notifications (FCM/APNs)** | [ ] | Wire `sendPushNotifications()` to actual FCM HTTP API / APNs | `notification_service.dart` — handle incoming push, show local notification, navigate on tap |
| F6.4 | **Chat Filters** | [~] | — | Preexisting: All / Unread / Personal / Groups. Missing: starred/bookmarked filter |

## F7 — Stories / Status

| ID | Feature | Status | Backend | Flutter |
|----|---------|--------|---------|---------|
| F7.3 | **Story View Tracking** | [ ] | `POST /stories/{id}/view` — record viewer, `GET /stories/{id}/views` — list viewers | Show view count + viewer list in story viewer |
| F7.4 | **Story DM Reply** | [ ] | Handle story reply as DM (create direct conversation + send message) | Reply button in story viewer → opens DM |
| F7.5 | **Story Privacy Settings** | [ ] | Check `status_privacy` + `close_friends` before returning stories | Story privacy selector in settings / story creator |
| F7.6 | **Story Mute** | [ ] | `POST /stories/mute/{userId}`, `POST /stories/unmute/{userId}` | Mute option on story ring in stories list |

## F8 — Broadcast & Channels

| ID | Feature | Status | Backend | Flutter |
|----|---------|--------|---------|---------|
| F8.1 | **Broadcast Lists** | [ ] | `POST /broadcasts`, `POST /broadcasts/{id}/send`, `GET /broadcasts` — create, send to members as individual DMs | `broadcast_list_screen.dart` — create list, send broadcast |
| F8.2 | **Channel Creation** | [ ] | `POST /channels` — create public/private channel, `POST /channels/{id}/subscribe`, `POST /channels/{id}/unsubscribe` | `channel_discover_screen.dart` |
| F8.3 | **Channel Messages** | [ ] | `POST /channels/{id}/messages` (admin), `GET /channels/{id}/messages` (subscribers) | `channel_screen.dart` — read-only for subscribers |
| F8.4 | **Channel Subscriber Management** | [ ] | `GET /channels/{id}/subscribers` — list + count | `channel_admin_screen.dart` |
| F8.5 | **Channel Discovery** | [ ] | `GET /channels/discover` — paginated public channels | Channel search / trending in discover screen |

## F9 — Voice & Video Calls

| ID | Feature | Status | Backend | Flutter |
|----|---------|--------|---------|---------|
| F9.3 | **Group Voice/Video Calls** | [ ] | Signaling for multi-participant (broadcast SDP/ICE to all participants) | Multi-participant call UI, grid layout |
| F9.5 | **Picture-in-Picture (PiP)** | [ ] | — | PiP mode for ongoing calls (Android native, iOS) |

## F10 — Advanced Messaging

| ID | Feature | Status | Backend | Flutter |
|----|---------|--------|---------|---------|
| F10.1 | **Scheduled Messages** | [ ] | `POST /messages/schedule`, `GET /messages/scheduled`, `DELETE /messages/scheduled/{id}`, cron Lambda to send due messages | Schedule button in chat input, date/time picker, scheduled message list |
| F10.3 | **Polls (Backend)** | [ ] | `POST /polls`, `POST /polls/{id}/vote`, `GET /polls/{id}/results` — proper poll storage and vote counting | Wire existing PollContent / PollCreatorSheet to backend API |
| F10.5 | **GIF Search Integration** | [ ] | Server-side Tenor/Giphy proxy with API key | GIF search tab in sticker picker |
| F10.6 | **Disappearing Messages UI** | [ ] | — | Timer picker UI in chat header + group settings |
| F10.7 | **Per-Chat Message Retention** | [ ] | Enforce retention policy per conversation | Display in chat info |
| F10.8 | **Voice Messages** | [~] | Works (local filesystem). Missing: S3 storage, waveform optimization | Works. Missing: waveform visualization |

## F13 — Admin Dashboard

| ID | Feature | Status | Backend | Flutter |
|----|---------|--------|---------|---------|
| F13.1 | **Admin Login** | [ ] | Admin auth (separate from user auth, or admin guard on existing JWT) | Admin login screen |
| F13.2 | **User Management** | [ ] | `GET /admin/users` — search/list, `PUT /admin/users/{id}/disable` — disable/enable | User list with search, disable/enable toggle |
| F13.3 | **Moderation Dashboard** | [~] | Backend queue endpoints done. Missing: analytics, bulk actions | `moderation_screen.dart` exists, missing: stats, filters |
| F13.4 | **Analytics Dashboard** | [ ] | `GET /admin/analytics` — DAU/MAU, messages/day, signups, retention | Charts, date range picker |
| F13.5 | **Feature Flag Console** | [ ] | `GET /admin/flags`, `PUT /admin/flags/{id}` — list, toggle, rollout %, kill switch | Flag list, toggle, rollout slider |
| F13.6 | **Audit Log Viewer** | [ ] | `GET /admin/audit-log` — paginated admin action log | Log viewer with search/filter |

## F14 — Webhooks & Bot API

| ID | Feature | Status | Backend | Flutter |
|----|---------|--------|---------|---------|
| F14.1 | **Webhook Registration** | [ ] | `POST /webhooks`, `GET /webhooks`, `DELETE /webhooks/{id}` — register per-event webhooks | — |
| F14.2 | **Event Delivery** | [ ] | EventBridge → SQS → Lambda → POST to webhook URL, retry with backoff | — |
| F14.3 | **Bot API** | [ ] | Bot auth tokens, `POST /bots/messages` — send as bot, `GET /bots/chats` — list chats | — |

## F15 — Platform Support

| ID | Feature | Status | Backend | Flutter |
|----|---------|--------|---------|---------|
| F15.5 | **Internationalization (i18n)** | [ ] | — | `.arb` files for en, hi (Hindi), es (Spanish), ar (Arabic); language switcher in Settings |
| F15.6 | **RTL Support** | [ ] | — | Enable RTL in MaterialApp, test with Arabic, fix layout issues |

## Security / Quality-of-Life (unlabeled)

| Feature | Status | Notes |
|---------|--------|-------|
| **App Lock (PIN/Biometrics)** | [ ] | local_auth package, PIN fallback, auto-lock on app background |
| **Rich Text Formatting** | [ ] | Bold, italic, code blocks in message input |
| **Mute / Quiet Hours** | [ ] | Per-chat mute with time range, global quiet hours in Notification Preferences |
| **Message Self-Destruct** | [ ] | True self-destruct timer (different from disappearing: delete after read once) |
| **Chat Wallpaper / Theme** | [ ] | Per-chat custom wallpaper, bubble color customization |
| **Message Effects** | [ ] | Confetti, fireworks, etc. for specific messages (birthday, etc.) |

---

## Backend Infrastructure

| Feature | Status | Notes |
|---------|--------|-------|
| **Feature Flag System** | [ ] | Centralized flag store in Valkey, flag evaluation middleware, admin API |
| **WebTransport over QUIC** | [ ] | Replace WebSocket with proper WebTransport/QUIC (architecture requires this) |
| **Message Broker (SQS/SNS)** | [ ] | Durable queue for async processing: moderation, notifications, media |

---

## Implementation Order

1. **Batch A** (Backend APIs — high priority, foundational):
   - Account Deletion, Privacy Settings API, Block Enforcement, Contact Discovery
   - Polls Backend, Scheduled Messages, Broadcast Lists, Channels
   - Story features, Mentions, Feature Flags

2. **Batch B** (Flutter screens for Batch A):
   - Privacy Settings, Account Deletion UI, Contact Discovery
   - Scheduled Messages UI, Broadcasts UI, Channels UI
   - Polls integration, Story features UI, Mentions input

3. **Batch C** (Infrastructure):
   - Push Notifications (FCM/APNs)
   - S3 Media Pipeline
   - Full-Text Search
   - Webhooks & Bot API

4. **Batch D** (UX Polish):
   - App Lock, i18n/RTL, Chat Filters
   - Rich Text, Mute/Quiet Hours
   - Admin Dashboard
   - Group Voice/Video Calls, PiP
