# Sinai roadmap

Keep this short: what is done, what is planned, what was decided and why.
Update it when a feature lands or a plan changes.

## Recent changes

Newest first, one line per task (see the rule in `CLAUDE.md`).

- 2026-11-27 — Messages screen: plus and profile icons drawn without a circle (`PlusIcon`, `ProfileIcon` in `app_icons.dart`), new-chat button 64→56 (`chats_screen.dart`). Not checked on a device.
- 2026-11-27 — Play/pause icons centred (glyphs sit left in the font): `PlayPauseIcon` in `app_icons.dart`, used in voice bubble, media screen, watch-together controls. Not checked on a device.
- 2026-11-27 — CLAUDE.md rule: log every finished task here.
- 2026-11-27 — CLAUDE.md, docs/ROADMAP.md, sinai-go/CLAUDE.md written.
- 2026-11-27 — Colour emoji font for messages and reactions
  (`common/emoji_text.dart`); red heart not yet checked on Android.
- 2026-11-27 — Chess pieces kept in release builds (`chess_game.dart`);
  not yet checked on the phone.
- 2026-11-26 — Google sign-in (`features/account/`, `auth/`); full sign-in
  not yet tried on a device.

## Done

- Moved from Firebase (Firestore) to the own Go backend (`../sinai-go`):
  chats, messages, photos and voice (R2), online status and typing, games,
  push, quick reactions. Old and new app versions don't see each other.
- Notch: icon menu (games, YouTube), game boards, YouTube watch-together
  synced through the server, pull-to-full-screen with a progress bar.
- YouTube/Vimeo players inside messages; "Watch together" under YouTube
  links; paste button reads copied URLs natively on iOS.
- White bottom toasts (`showToast`) instead of snack bars.
- Update banner / blocking screen via Firebase Remote Config.
- Keep the account with Google (profile → Account; onboarding → Restore).
- Gradle 9.1 / AGP 9.0.1 / Kotlin 2.3.20.

## Decisions

- **No Apple sign-in**: an account made with Apple can't be restored after
  moving to Android.
- **No email + password**: anyone could make endless accounts with made-up
  emails. Only real identities (Google, later Telegram).
- **No phone sign-in for now**: every SMS costs money (`FeatureFlags.phoneSignIn`).
- **No WhatsApp sign-in**: there is no "Sign in with WhatsApp"; codes via
  WhatsApp Business API are paid.
- The app still signs in anonymously first, so accounts can be made by
  reinstalling; Google is a way to restore, not a gate.

## Planned / ideas

- Telegram sign-in: bot + Login Widget, verified by the Go backend, which
  issues a Firebase custom token; link it like Google.
- Check Google sign-in end to end on both phones (configs are in place;
  Android needs the release key's SHA-1 once there is a real signing key).
- Own release signing key for Android (now signed with the debug key).
- Real bundle/package IDs instead of `com.example.sinai` / `com.example.sinay`.
- Move app plugins to AGP's built-in Kotlin once Firebase and other
  plugins support it (now `android.builtInKotlin=false`).
- More link players (Twitch, Rutube…), if wanted.

## Not verified yet

- Red heart emoji on Android, chess pieces in the release APK (fixed,
  waiting for Daniel's phone check).
- Pausing video while recording voice; the game-starts-while-menu-open fix
  (needs a second person).
