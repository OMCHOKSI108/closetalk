# CloseTalk — API Reference

> Complete list of all REST API endpoints organized by service. Base path: `/api/v1`

---

## Auth Service (`/auth`)

| Method | Endpoint | Description | Req. ID | Auth |
|---|---|---|---|---|
| POST | `/auth/register` | Register with email + password | F1.1 | None |
| POST | `/auth/login` | Login with email/password | F1.2 | None |
| POST | `/auth/oauth` | OAuth callback (Google/Apple) | F1.1 | None |
| POST | `/auth/refresh` | Rotate refresh token, return new access token | F1.2 | Refresh |
| POST | `/auth/logout` | Invalidate current session | F1.2 | JWT |
| POST | `/auth/recover` | Verify recovery code, return session token | F1.7 | None |
| POST | `/auth/recover/email` | Request email recovery link | F1.7 | None |
| POST | `/auth/recover/verify` | Verify email recovery token | F1.7 | None |
| POST | `/auth/recover/trusted` | Request recovery from trusted device | F1.7 | JWT |
| PUT | `/auth/password` | Change password | N4.3 | JWT |
| POST | `/auth/mfa/enable` | Enable TOTP MFA | N4.3 | JWT |
| POST | `/auth/mfa/verify` | Verify MFA code | N4.3 | JWT |

## User Service (`/users`)

| Method | Endpoint | Description | Req. ID | Auth |
|---|---|---|---|---|
| GET | `/users/me` | Get current user profile | F1.3 | JWT |
| PUT | `/users/me` | Update profile (name, bio, avatar) | F1.3 | JWT |
| DELETE | `/users/me` | Delete account and all data | F1.4 | JWT |
| GET | `/users/search` | Search users by name/email/phone | F1.5 | JWT |
| GET | `/users/:id` | Get user profile (public) | F1.5 | JWT |
| POST | `/users/me/recovery-codes` | Generate new recovery codes | F1.6 | JWT |
| GET | `/users/me/recovery-codes/remaining` | Get remaining code count | F1.6 | JWT |

## Device Service (`/devices`)

| Method | Endpoint | Description | Req. ID | Auth |
|---|---|---|---|---|
| GET | `/devices` | List all linked devices | F1.9 | JWT |
| POST | `/devices/link` | Link new device (QR code flow) | F1.8 | JWT |
| POST | `/devices/revoke` | Revoke device by ID | F1.8 | JWT |
| PUT | `/devices/:id/name` | Rename a device | F1.9 | JWT |
| GET | `/devices/:id/sessions` | Get active sessions for device | F1.9 | JWT |

## Contacts & Privacy (`/contacts`, `/blocks`, `/privacy`)

| Method | Endpoint | Description | Req. ID | Auth |
|---|---|---|---|---|
| POST | `/contacts/discover` | Hash-based contact discovery | F2.1 | JWT |
| GET | `/contacts` | List user's contacts | F2.1 | JWT |
| POST | `/contacts/sync` | Sync contact hashes | F2.1 | JWT |
| POST | `/blocks/:user_id` | Block a user | F2.6 | JWT |
| DELETE | `/blocks/:user_id` | Unblock a user | F2.6 | JWT |
| GET | `/blocks` | List blocked users | F2.6 | JWT |
| GET | `/privacy/settings` | Get privacy settings | F2.2–F2.5 | JWT |
| PUT | `/privacy/settings` | Update privacy settings | F2.2–F2.5 | JWT |
| PUT | `/privacy/read-receipts/:chat_id` | Override read receipts per chat | F2.4 | JWT |

## Message Service (`/messages`)

| Method | Endpoint | Description | Req. ID | Auth |
|---|---|---|---|---|
| POST | `/messages` | Send a message | F3.1 | JWT |
| GET | `/messages/:chat_id` | Paginated message history | F3.1 | JWT |
| PUT | `/messages/:id` | Edit message (within 15min) | F3.6 | JWT |
| DELETE | `/messages/:id` | Delete message (within 15min) | F3.7 | JWT |
| POST | `/messages/:id/react` | Add/remove emoji reaction | F3.5 | JWT |
| POST | `/messages/:id/reply` | Reply to a message (thread) | F3.4 | JWT |
| POST | `/messages/:id/bookmark` | Bookmark a message | F3.10 | JWT |
| DELETE | `/messages/:id/bookmark` | Remove bookmark | F3.10 | JWT |
| GET | `/bookmarks` | List all bookmarked messages | F3.10 | JWT |
| POST | `/messages/schedule` | Schedule a message for later | F10.1 | JWT |
| GET | `/messages/scheduled` | List scheduled messages | F10.1 | JWT |
| DELETE | `/messages/scheduled/:id` | Cancel scheduled message | F10.1 | JWT |
| POST | `/messages/:id/translate` | Translate message inline | F10.2 | JWT |
| GET | `/messages/export/:chat_id` | Export chat history (JSON/HTML) | F3.9 | JWT |
| POST | `/messages/:id/report` | Report a message for moderation | F11.3 | JWT |

## Group Service (`/groups`)

| Method | Endpoint | Description | Req. ID | Auth |
|---|---|---|---|---|
| POST | `/groups` | Create group | F5.1 | JWT |
| GET | `/groups/:id` | Get group details | F5.1 | JWT |
| PUT | `/groups/:id` | Update group settings (name, avatar, desc) | F5.1 | JWT |
| DELETE | `/groups/:id` | Delete group (admin only) | F5.1 | JWT |
| POST | `/groups/:id/invite` | Generate invite link | F5.2 | JWT |
| POST | `/groups/join` | Join group via invite link | F5.2 | JWT |
| POST | `/groups/:id/members` | Add member (admin only) | F5.3 | JWT |
| DELETE | `/groups/:id/members/:user_id` | Remove member (admin only) | F5.3 | JWT |
| PUT | `/groups/:id/members/:user_id/role` | Promote/demote admin | F5.3 | JWT |
| POST | `/groups/:id/leave` | Leave group | F5.4 | JWT |
| POST | `/groups/:id/pin` | Pin a message | F5.6 | JWT |
| DELETE | `/groups/:id/pin` | Unpin message | F5.6 | JWT |
| PUT | `/groups/:id/settings` | Update retention, disappearing messages | F5.7–F5.8 | JWT |
| POST | `/groups/:id/summarize` | Generate AI summary | F12.2 | JWT |
| GET | `/groups/:id/messages` | Paginated group message history | F5.5 | JWT |

## Poll Service (`/polls`)

| Method | Endpoint | Description | Req. ID | Auth |
|---|---|---|---|---|
| POST | `/polls` | Create poll in chat | F10.3 | JWT |
| POST | `/polls/:id/vote` | Vote on poll | F10.3 | JWT |
| GET | `/polls/:id/results` | Get live poll results | F10.3 | JWT |
| DELETE | `/polls/:id` | Delete poll (admin only) | F10.3 | JWT |

## Status / Stories Service (`/status`)

| Method | Endpoint | Description | Req. ID | Auth |
|---|---|---|---|---|
| POST | `/status` | Create status update | F7.1 | JWT |
| GET | `/status/updates` | Get status updates from contacts | F7.2 | JWT |
| GET | `/status/:id` | Get single status | F7.2 | JWT |
| GET | `/status/:id/views` | Get viewers of a status | F7.3 | JWT |
| POST | `/status/:id/view` | Mark status as viewed | F7.3 | JWT |
| POST | `/status/:id/reply` | Reply to status via DM | F7.4 | JWT |
| DELETE | `/status/:id` | Delete own status | F7.1 | JWT |
| PUT | `/status/privacy` | Update status privacy settings | F7.5 | JWT |
| PUT | `/status/mute/:user_id` | Mute status from a contact | F7.6 | JWT |

## Broadcast & Channel Service (`/broadcasts`, `/channels`)

| Method | Endpoint | Description | Req. ID | Auth |
|---|---|---|---|---|
| POST | `/broadcasts` | Create broadcast list | F8.1 | JWT |
| GET | `/broadcasts` | List broadcast lists | F8.1 | JWT |
| POST | `/broadcasts/:id/send` | Send broadcast message | F8.1 | JWT |
| POST | `/channels` | Create channel | F8.2 | JWT |
| GET | `/channels/:id` | Get channel details | F8.2 | JWT |
| PUT | `/channels/:id` | Update channel settings | F8.2 | JWT |
| POST | `/channels/:id/subscribe` | Subscribe to channel | F8.3 | JWT |
| POST | `/channels/:id/unsubscribe` | Unsubscribe from channel | F8.3 | JWT |
| POST | `/channels/:id/messages` | Send channel message (admin only) | F8.2 | JWT |
| GET | `/channels/:id/messages` | Get channel messages | F8.2 | JWT |
| GET | `/channels/:id/subscribers` | Get subscriber list (admin only) | F8.5 | JWT |
| GET | `/channels/discover` | Discover public channels | F8.3 | JWT |

## Media Service (`/media`)

| Method | Endpoint | Description | Req. ID | Auth |
|---|---|---|---|---|
| POST | `/media/upload-url` | Get presigned upload URL | F3.2 | JWT |
| POST | `/media/confirm` | Confirm upload complete | F3.2 | JWT |
| GET | `/media/:media_id` | Get media (signed CDN URL) | F3.2 | JWT |
| GET | `/media/:media_id/thumbnail` | Get thumbnail by size | F3.2 | JWT |
| DELETE | `/media/:media_id` | Delete media | F3.2 | JWT |
| POST | `/stickers` | Upload custom sticker | F10.4 | JWT |
| GET | `/stickers/packs` | List available sticker packs | F10.4 | JWT |
| GET | `/gifs/search` | Search GIFs (Tenor/Giphy proxy) | F10.5 | JWT |
| GET | `/gifs/trending` | Trending GIFs | F10.5 | JWT |

## Presence Service (`/presence`)

| Method | Endpoint | Description | Req. ID | Auth |
|---|---|---|---|---|
| PUT | `/presence/status` | Update presence/typing status | F6.1–F6.2 | JWT (WT) |
| GET | `/presence/:user_id` | Get user's presence status | F6.2 | JWT |

## Voice & Video Calling (`/calls`)

| Method | Endpoint | Description | Req. ID | Auth |
|---|---|---|---|---|
| POST | `/calls/offer` | Send SDP offer for call | F9.1 | JWT |
| POST | `/calls/answer` | Send SDP answer | F9.1 | JWT |
| POST | `/calls/ice-candidate` | Exchange ICE candidate | F9.1 | JWT |
| POST | `/calls/end` | End a call | F9.1 | JWT |
| POST | `/calls/group` | Create group call | F9.3 | JWT |

## Search Service (`/search`)

| Method | Endpoint | Description | Req. ID | Auth |
|---|---|---|---|---|
| GET | `/search` | Full-text search across messages | F3.8 | JWT |
| GET | `/search/users` | Search users | F1.5 | JWT |

## Sync Service (`/sync`)

| Method | Endpoint | Description | Req. ID | Auth |
|---|---|---|---|---|
| GET | `/sync/messages` | Incremental message sync (cursor-based) | F4.3 | JWT |
| GET | `/sync/status` | Sync status updates | F4.2 | JWT |
| GET | `/sync/contacts` | Sync contacts | F4.2 | JWT |

## AI Service (`/ai`)

| Method | Endpoint | Description | Req. ID | Auth |
|---|---|---|---|---|
| POST | `/ai/ask` | Ask AI assistant | F12.1 | JWT |
| POST | `/ai/translate` | Translate message | F10.2 | JWT |
| POST | `/ai/summarize` | Generate summary | F12.2 | JWT |

## Admin Service (`/admin`)

| Method | Endpoint | Description | Req. ID | Auth |
|---|---|---|---|---|
| POST | `/admin/login` | Admin login (separate auth) | F13.1 | None |
| GET | `/admin/users` | List/search users | F13.1 | Admin |
| GET | `/admin/users/:id` | View user details | F13.1 | Admin |
| PUT | `/admin/users/:id/status` | Enable/disable user | F13.1 | Admin |
| GET | `/admin/moderation/queue` | List flagged messages | F13.2 | Admin |
| POST | `/admin/moderation/:id/approve` | Approve flagged message | F13.2 | Admin |
| POST | `/admin/moderation/:id/remove` | Remove flagged message | F13.2 | Admin |
| POST | `/admin/moderation/:id/ban-user` | Ban user for message | F13.2 | Admin |
| GET | `/admin/analytics/dau` | DAU/MAU analytics | F13.4 | Admin |
| GET | `/admin/analytics/messages` | Messages per day | F13.4 | Admin |
| GET | `/admin/analytics/signups` | New signups per day | F13.4 | Admin |
| GET | `/admin/analytics/retention` | Retention cohorts | F13.4 | Admin |
| GET | `/admin/health` | System health status | F13.3 | Admin |
| GET | `/admin/feature-flags` | List all feature flags | F13.5 | Admin |
| PUT | `/admin/feature-flags/:id` | Update feature flag | F13.5 | Admin |
| GET | `/admin/audit-log` | View audit log | F13.6 | Admin |

## Webhook Service (`/webhooks`)

| Method | Endpoint | Description | Req. ID | Auth |
|---|---|---|---|---|
| POST | `/webhooks` | Register webhook endpoint | F14.1 | Admin |
| GET | `/webhooks` | List registered webhooks | F14.1 | Admin |
| DELETE | `/webhooks/:id` | Delete webhook | F14.1 | Admin |
| GET | `/webhooks/:id/logs` | View webhook delivery logs | F14.1 | Admin |
| POST | `/webhooks/keys` | Generate API key | F14.3 | Admin |
| DELETE | `/webhooks/keys/:id` | Revoke API key | F14.3 | Admin |
| GET | `/webhooks/keys` | List API keys | F14.3 | Admin |

---

## WebSocket / WebTransport Events

These are pushed server→client via WebTransport (primary) or WebSocket (fallback).

| Event | Direction | Transport | Description |
|---|---|---|---|
| `message.new` | Server → Client | Stream | New message received |
| `message.updated` | Server → Client | Stream | Message edited/deleted |
| `message.status` | Server → Client | Stream | Status change (sent→delivered→read) |
| `message.reaction` | Server → Client | Stream | Emoji reaction added |
| `typing.start` | Server → Client | Datagram | User started typing |
| `typing.stop` | Server → Client | Datagram | User stopped typing |
| `presence.online` | Server → Client | Datagram | User came online |
| `presence.offline` | Server → Client | Datagram | User went offline |
| `presence.cursor` | Server → Client | Datagram | Cursor position |
| `call.incoming` | Server → Client | Stream (high priority) | Incoming call |
| `call.accepted` | Server → Client | Stream | Call answered |
| `call.ended` | Server → Client | Stream | Call ended |
| `call.ice-candidate` | Server → Client | Stream | ICE candidate |
| `notification.push` | Server → Client | N/A (APNs/FCM) | Push notification |
| `device.revoked` | Server → Client | Stream | Device remotely logged out |
| `status.new` | Server → Client | Stream | New status available |
| `sync.required` | Server → Client | Stream | Client behind, trigger sync |
| `moderation.flagged` | Server → Client | Stream | Message flagged (shown to sender) |
