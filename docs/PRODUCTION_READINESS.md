# CloseTalk Production Readiness

This is the launch gate for a public Android Play Store release. Do not treat this as marketing polish; these are reliability, privacy, and safety requirements for a consumer chat app.

## Release Targets

| Area | Minimum | Target |
| --- | --- | --- |
| Crash-free users | 99.0% | 99.5%+ |
| Crash-free sessions | 99.5% | 99.9% |
| User-perceived ANR | < 0.47% | < 0.3% |
| Startup crash rate | < 0.1% | < 0.03% |
| Message delivery success | > 99% | > 99.5% |
| Average API latency | < 500 ms | < 300 ms |
| Push notification success | > 98% | > 99% |

## Must Pass Before Public Launch

- App starts cold in under 2 seconds on a mid-range Android device.
- Normal chat flows have no crashes: login, contact request, accept/reject, send text, send media, group join, group mute, logout.
- A user accepting a contact request creates a direct conversation visible to both users immediately.
- Messages are idempotent: retrying send cannot create duplicates.
- Messages survive reconnect, background/foreground, app restart, and slow network.
- Media uploads show progress, support retry, validate type/size server-side, and clean cache.
- Push notifications deep-link to the correct chat, respect mute settings, and group correctly.
- Access tokens refresh automatically on 401 once, then safely logout if refresh fails.
- Account deletion, block user, report user, and privacy settings work end to end.
- No debug banner, no noisy debug logs in release, release signing configured.
- Privacy policy published and Play Store data safety form matches actual collection.

## Monitoring Required

- Crash monitoring: Firebase Crashlytics or Sentry.
- Product analytics: DAU/MAU, retention, message sends, delivery failures, notification opens.
- Backend monitoring: API latency, error rate, DB load, websocket connections, queue failures, storage growth.
- Alerts: elevated 5xx, websocket disconnect spike, push failure spike, DB CPU/storage thresholds.

## Backend Gates

- HTTPS everywhere.
- JWT expiration and refresh rotation.
- Rate limiting for auth, search, contact requests, messages, media, and group joins.
- Server-side authorization on every user/group/message/media mutation.
- PostgreSQL indexes for contact lists, conversations, message pagination, group membership, and search.
- Backups tested by restore, not only scheduled.
- Websocket scaling plan using Redis/pubsub or equivalent fanout.
- Object storage and CDN for media.

## Android Play Store Gates

- Android Vitals below bad-behavior thresholds:
  - User-perceived crash rate under 1.09%.
  - User-perceived ANR rate under 0.47%.
- Runtime permissions requested only at point of use:
  - Notifications, camera, microphone, photos/storage, location.
- Clear privacy policy covering chat content, contacts, analytics, notifications, media, camera/mic, deletion.
- Background work must be justified and battery-safe.

## Test Matrix

- Airplane mode while sending.
- Reconnect after app background.
- Token expiry during chat send.
- Slow 2G/3G network.
- Duplicate tap on send.
- Media upload interruption.
- Large chat pagination.
- Large group member list.
- Blocked user attempts to message.
- Muted chat notification behavior.
- App killed and relaunched from notification.
- Low battery mode.

## Current Codebase Notes

- `closetalk_app/lib/main.dart` now has a top-level guarded zone and disables the debug banner.
- A real crash backend still needs to be connected in `_reportError`.
- Contact accept currently creates a direct conversation and the chat list includes accepted contacts before first message.
- Mock users are seeded through backend migrations and runtime DB bootstrap for local/demo testing.
