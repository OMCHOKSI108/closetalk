# CloseTalk — Product Vision

## What Is CloseTalk?

CloseTalk is a **high-performance, cross-platform real-time communication application** — a modern chat app built for 2026 and beyond. It combines the speed and reliability of cloud-native infrastructure with AI-powered features to deliver a messaging experience that is fast, safe, and intelligent.

## Target Audience

- **Primary**: Individuals and teams who want a private, feature-rich messaging app
- **Secondary**: Communities and groups (up to 1,000 members per group)
- **Scale**: From small friend groups to communities of 100,000 registered users

## What the Final Product Looks Like

### User-Facing Experience

**Login & Onboarding**
- Open the app → see a clean auth screen
- Sign up with email, phone, or "Continue with Google/GitHub/Apple"
- Set up your profile: avatar (with AI-generated option), display name, optional bio
- Sync your contacts to find friends already on CloseTalk

**Chat List**
- A clean, left-side panel (or bottom tab on mobile) showing recent conversations
- Each chat shows: contact/group name, last message preview, timestamp, unread badge
- Search bar to filter chats or search across all messages
- Floating action button to start a new chat

**One-to-One Chat**
- Open a conversation → see a thread of messages with smooth scroll
- Send text, emoji reactions, images, voice notes, files, and video
- Real-time typing indicator ("Name is typing...") — appears instantly via WebTransport
- Double-tick read receipts and delivery status
- Reply to specific messages (threaded view)
- Edit or delete messages within 15 minutes
- Pin important messages to the top

**Group Chat**
- Create a group with a name, avatar, and description
- Invite members via shareable link or direct add
- Admin controls: add/remove members, promote admins, change group settings
- @mention members to notify them specifically
- Supports up to 1,000 members with smooth scrolling and search
- AI-powered group summaries: get a daily/weekly digest of what you missed
- Pinned messages and shared media gallery

**Real-Time Presence**
- See who's online with green dot indicators
- Typing indicators — works even on slow connections (QUIC protocol)
- Read receipts shown per-message

**Voice & Video Calling**
- One-to-one voice and video calls (WebRTC)
- Group calls (up to 8 participants)
- Picture-in-picture mode on mobile
- Works seamlessly alongside messaging

**AI Assistant**
- A personal AI assistant accessible from any chat
- Has persistent memory — remembers past conversations and preferences
- Can summarize group conversations, suggest replies, answer questions
- Content moderation runs silently in the background — keeps the platform safe

**Settings & Profile**
- Profile editing
- Notification preferences (per-chat or global)
- Privacy controls: last-seen visibility, read receipts on/off, block list
- Theme: light/dark/ system
- Multi-device: messages sync across phone, tablet, desktop, and web
- Export chat history
- Account deletion with full data purge

### Visual Design

- **Clean, minimal UI** — material design with modern flat aesthetics
- **Consistent across all platforms** — Flutter ensures pixel-perfect parity
- **Smooth animations** — message send, transitions, typing indicators
- **Dark mode** — easy on the eyes, auto-switches based on system preference
- **Responsive layout** — adapts seamlessly from phone to tablet to desktop

### Performance That Feels Instant

| Action | Feel |
|---|---|
| Open app | < 2 seconds cold start |
| Message send → delivered | < 50ms (same region) |
| Message send → delivered | < 100ms (global) |
| Typing indicator appears | < 20ms |
| Image load | < 1 second (CDN-cached) |
| Search across 10K messages | < 500ms |

### What Makes CloseTalk Different

1. **Built on 2026 standards** — WebTransport/QUIC, not WebSockets from 2011
2. **AI-native** — moderation, assistant, summaries are first-class features, not bolt-ons
3. **Cost-efficient from day one** — MVP runs on $5–$10/month with serverless
4. **Truly cross-platform** — one Flutter codebase for 6 platforms
5. **Privacy-first** — Row Level Security at the DB level, Zero-Trust architecture

## Screenshots & Mockups

Concept screenshots are available in `docs/1.png` through `docs/4.png`.

## Success Metrics

| Metric | MVP Target | Growth Target |
|---|---|---|
| Registered users | 1,000 | 100,000 |
| Daily active users | 100 | 10,000 |
| Messages per day | 5,000 | 500,000 |
| Message delivery (p99) | < 100ms | < 50ms |
| Uptime | 99.9% | 99.99% |
| App store rating | 4.0+ | 4.5+ |
| Monthly infra cost | $5–$10 | ~$990 |
