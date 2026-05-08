# CloseTalk — Product Vision

## What Is CloseTalk?

CloseTalk is a **production-grade cross-platform communication app** that fixes every major problem WhatsApp users have faced over the last decade — built with 2026 cloud-native architecture, AI-powered features, and privacy-first design.

Not WhatsApp-lite. WhatsApp-smarter.

## Target Audience

- **Primary**: Individuals and teams who want a private, feature-rich messaging app
- **Secondary**: Communities and groups (up to 1,000 members per group)
- **Scale**: From small friend groups to communities of 100,000 registered users

## What Makes CloseTalk Different (vs WhatsApp Problems Fixed)

| WhatsApp Problem | CloseTalk Fix |
|---|---|
| Slow on weak networks (TCP HoL blocking) | WebTransport over QUIC — 0-RTT, no head-of-line blocking |
| Phone must stay online for desktop to work | True multi-device — each device connects independently |
| Uploads raw address book to servers | Hash-based contact discovery — we never see your contacts |
| Re-compresses media, destroys quality | Direct S3 uploads — original quality preserved |
| 256 person group limit | Groups up to 1,000 with ScyllaDB hot partition handling |
| Reactive spam reporting | Real-time AI moderation before message is delivered |
| No disappearing messages (until 2021) | Flexible: 5s / 30s / 5m / 1h / 24h — per chat |
| No cross-chat search | Full-text search across all chats with AI relevance |
| No public API or bots | EventBridge webhooks + Bot API |
| Hard to scale (Erlang/Mnesia) | Cloud-native disaggregated — auto-scale at infrastructure level |

## What the Final Product Looks Like

### Login & Onboarding
- Open the app → clean auth screen with email/phone/OAuth
- **Account recovery setup**: 10 one-time recovery codes displayed, forced to save
- **Privacy-preserving contact sync**: Find friends without uploading your address book
- Profile setup: avatar (AI-generated option), display name, bio

### Chat List
- Clean conversation list with last message preview, timestamp, unread badge
- **Multi-device sync**: same chats on phone, tablet, desktop — all in real-time
- Search bar to filter chats or full-text search across all messages
- **Bookmarks tab**: important messages saved across all devices

### One-to-One Chat
- Send text, emoji reactions, images, voice notes, files, video
- **Typing indicators via WebTransport** — appears instantly (<20ms), even on slow networks
- Double-tick read receipts (configurable on/off)
- Reply, edit (within 15min), delete for everyone
- **Disappearing messages**: off / 5s / 30s / 5m / 1h / 24h per chat
- **Inline translation**: tap any message to translate via AI
- **Schedule message**: write now, send later
- **Bookmark** important messages

### Group Chat
- Create with name, avatar, description — up to 1,000 members
- Invite via shareable link or direct add
- Admin controls: add/remove, promote admins, change settings
- @mention notifications, pinned messages, shared media gallery
- **In-chat polls**: create, vote, live results
- **Message retention**: off / 30d / 90d / 1yr per group
- AI-powered group summaries (daily/weekly digest)
- **Message translation**: auto-detect and translate group messages

### Stories / Status
- Post photo, video, or text that disappears in 24 hours
- View contacts' stories in ranked order (most recent first)
- See who viewed your story
- Reply to stories via DM
- Privacy controls: My Contacts / Close Friends / Public
- Mute status updates from specific contacts

### Broadcast & Channels
- **Broadcast lists**: send message to multiple contacts at once (each receives as DM)
- **Channels**: one-to-many broadcast with subscribers
- Channel admin tools: moderate, remove, see subscriber analytics

### Real-Time Presence
- Online/offline status with privacy controls (Nobody / Everyone / Contacts / Contacts Except)
- Typing indicators via WebTransport datagrams
- Read receipts (global on/off + per-chat override)

### Voice & Video Calling
- One-to-one voice and video (WebRTC with STUN/TURN)
- Group calls up to 8 participants
- AI-powered noise suppression
- Picture-in-picture mode on mobile

### AI Assistant
- Personal AI assistant with persistent memory (remembers past conversations)
- Summarize group conversations, suggest replies, answer questions
- Translate messages inline
- Content moderation runs silently in background

### Settings & Privacy (Granular Controls)
- **Last seen**: Nobody / Everyone / My Contacts / My Contacts Except
- **Profile photo**: Nobody / Everyone / My Contacts
- **Read receipts**: Global on/off + per-chat
- **Group add**: Everyone / My Contacts / My Contacts Except
- **Block list**: block/unblock, syncs across all devices
- **Disappearing messages**: per-chat default
- **Message retention**: per-chat auto-delete

### Multi-Device (Native, Not Retrofitted)
- Link up to 5 devices (phone, tablet, desktop, web)
- **Phone NOT required to stay online** — each device connects independently
- Messages sync in real-time across all devices
- New device syncs history from server
- Remote logout any device from settings

### Admin Dashboard (Web)
- **User management**: search, view, disable accounts
- **Moderation queue**: review flagged messages, approve/remove/ban
- **System health**: service status, latency, error rates, uptime
- **Analytics**: DAU/MAU, retention, messages/day, signups, top features
- **Feature flags**: toggle features on/off, gradual rollout
- **Audit logs**: all admin actions with timestamps
- **Webhook management**: create/revoke API keys, view webhook logs

### Visual Design
- Clean, minimal material design — consistent across all 6 platforms
- Smooth animations: message send, transitions, typing indicators
- Dark mode: light / dark / system (auto-switch)
- Responsive layout: phone → tablet → desktop
- **Multi-language**: English + Hindi + 5 more at launch, RTL support

### Performance That Feels Instant

| Action | Feel |
|---|---|
| Open app | < 2 seconds cold start |
| Message send → delivered | < 50ms (same region) |
| Message send → delivered | < 100ms (global) |
| Typing indicator appears | < 20ms |
| Image load | < 1 second (CDN-cached) |
| Search across 50K messages | < 500ms |
| Story load | < 1 second |
| Link new device | < 10 seconds (history sync) |

## Screenshots & Mockups

Concept screenshots available in `docs/1.png` through `docs/4.png`.

## Success Metrics

| Metric | MVP Target | Growth Target |
|---|---|---|
| Registered users | 1,000 | 100,000 |
| Daily active users | 100 | 10,000 |
| Messages per day | 5,000 | 500,000 |
| Message delivery (p99) | < 100ms | < 50ms |
| Uptime | 99.9% | 99.99% |
| App store rating | 4.0+ | 4.5+ |
| Multi-device users | 10% | 40% |
| Monthly infra cost | $5–$10 | ~$990 |
