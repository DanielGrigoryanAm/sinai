# Sinai roadmap

Keep this short: what is done, what is planned, what was decided and why.
Update it when a feature lands or a plan changes.

## Recent changes

Newest first, one line per task (see the rule in `CLAUDE.md`).

- 2026-11-28 — Security (app + backend): Redis rate limits (`internal/ratelimit`: per address 1200/min, per user 300/min, sign-in 30/min per address, messages 60/min, new chats 20/h, uploads 120/h and 2 GB/day); wrong chat/personal codes (join, direct, `/v1/users/{code}`) stopped after 20/h, 60/day per user and 60/h per address (429 + Retry-After) — guessing a chat is no longer feasible. Upload URLs sign the file's size and type (app sends `size`; storage refuses anything else); migration 0008 `uploads` + hourly sweep delete files nothing used after 48 h. Game JSON ≤4 KB, depth ≤4, `by` set by the server; watch only `{videoId, playing, position}`. WebSocket: ≤8 connections per user, ≤20 events / 10 s. Local SeaweedFS now checks signatures (`dev-s3.json`). Smoke passes (86). Not deployed; not checked against R2 or on a device. Old app builds can't upload until updated (raise `min_build` after the release).
- 2026-11-28 — Own profile: a tap on the photo opens it full screen as uploaded (square, `ImageViewerScreen`: zoom, save); the Choose / Remove sheet is now on the camera badge only; with no photo, a tap on the letter picks one (`profile_screen.dart`). Not checked on a device.
- 2026-11-28 — Back on Messages from another screen, the search no longer takes focus by itself and opens the keyboard: it is unfocused when the screen leaves or returns to the top, and focus given in the first 0.7 s after returning is dropped (`chats_screen.dart`, `focusNode` on `RoundField`). Not checked on a device.
- 2026-11-28 — The profile button on Messages shows the user's photo (person icon without one or while it loads). The profile (photo, code, name, quick reactions) is cached in `LocalCache` as `me` and shown at once, then refreshed from the backend; `AuthApi.current` notifier, updated by `me`/`rename`/`setPhoto`/`removePhoto`/`setQuickReactions`/sign-in (`auth_api.dart`, `chats_screen.dart`, `profile_screen.dart`, `quick_reactions_store.dart`). Not checked on a device.
- 2026-11-28 — New chat and Create a chat screens redone in the profile's style: titled bars, sections with 52 px rows, the code/name typed in the row with an inline Paste / Join / Create; "Create a chat" row with the plain plus (no circle). Joining now replaces the screen with the chat (`start_chat_screen.dart`, `create_chat_screen.dart`, `SettingsRowAction`/`SettingsField` in `settings_section.dart`). Not checked on a device.
- 2026-11-28 — Chat's photo menu (Choose from gallery / Take a photo): icons in the accent colour, like the profile's photo menu (`message_field.dart`). Not checked on a device.
- 2026-11-28 — Fixed a deleted chat flashing back: a list asked for before the backend deleted it could arrive after; the bloc now keeps deleted chats hidden until a list asked for after the deletion arrives, and Messages no longer reloads right on delete (`chat_bloc_backend.dart` `_gone`, `chats_screen.dart`). Not checked on a device.
- 2026-11-28 — Colors split: profile → Appearance → App colors (accent, background, cards; everywhere) and chat info → Chat colors (my messages, text; that chat only, saved per chat on the device in `theme/chat_colors_store.dart`, applied by `ChatColorsScope` around the chat screen). `ColorSlot.isChat`, shared `_ColorsScreen` in `app_colors_screen.dart`; `profile_screen.dart`, `chat_info_sheet.dart`, `chat_screen.dart`, `main.dart`. Not checked on a device.
- 2026-11-28 — Direct chats' info sheet no longer lists members; the other person's photo at its top opens their profile (`chat_info_sheet.dart`). Not checked on a device.
- 2026-11-27 — Other people's profiles: `PersonProfileScreen` (photo, tap for full screen; name; online / last seen, live from the chat). Opens from a member row in the chat info sheet, and in a direct chat from the other person's photo at the top of the sheet; member rows now show photos (`person_profile_screen.dart`, `chat_info_sheet.dart`). Not checked on a device.
- 2026-11-27 — Message field: the gold PNG photo/mic/send pictures replaced by Flaticon UIcons Regular rounded (`picture`, `microphone`, `paper-plane-top`) in the accent colour; the three glyphs were added to `UiconsRegular.ttf` from `@flaticon/flaticon-uicons` 3.3.1 (old glyphs unchanged), `assets/icons/` removed (`app_icons.dart` `photo`/`microphone`/`send`, `message_field.dart`, `pubspec.yaml`). Not checked on a device. Note: the bundled Uicons fonts are subsets of an older release with other codepoints; new glyphs keep the 3.3.1 codepoints.
- 2026-11-27 — Profile tidied into one style: photo and name on top, then sections (label, white rounded card with 52 px rows, caption) for the code (tap copies), the name (field with an inline Save), Account (Google row with a check) and a red Sign out row; new `common/settings_section.dart` (`SettingsSection`, `SettingsRow`), used by `profile_screen.dart` and `AccountSection` (`account_options.dart`). Not checked on a device.
- 2026-11-27 — Messages: "Search chats..." field is now the shared `RoundField` (same look and height as message search, clear button) instead of its own `_SearchField` (`chats_screen.dart`). Not checked on a device.
- 2026-11-27 — One back button everywhere: `CustomAppBar(showBackButton: true)` now draws the chat's edge tab (title and actions lined up with it, optional `bottom` for tabs), so New chat, Create chat, Profile, Phone get it; App colors and Media moved from plain `AppBar` to it. The photo viewer's close and the crop editor's Cancel stay (`custom_app_bar.dart`, `app_colors_screen.dart`, `chat_media_screen.dart`). Not checked on a device.
- 2026-11-27 — New message screen gets message search's top: the chat's back tab and the rounded field (with Paste while empty), now shared as `EdgeFieldBar` / `RoundField` in `common/round_field.dart` (`find_person_screen.dart`, `message_search_screen.dart`). Not checked on a device.

## Done

- 2026-11-26…27 (from Recent changes): Google-only sign-in, no anonymous
  accounts (app and backend), sign out; personal 8-character codes and
  direct chats (migrations 0005–0006); profile photos and the photo crop
  editor; offline cache and outbox with `clientId` against double
  messages (migration 0007); message search screen, shared `EdgeTab` /
  `RoundField`; colour emoji font; chess pieces kept in release builds;
  CLAUDE.md and this roadmap.
- Moved from Firebase (Firestore) to the own Go backend (`../sinai-go`):
  chats, messages, photos and voice (R2), online status and typing, games,
  push, quick reactions. Old and new app versions don't see each other.
- Notch: icon menu (games, YouTube), game boards, YouTube watch-together
  synced through the server, pull-to-full-screen with a progress bar.
- YouTube/Vimeo players inside messages; "Watch together" under YouTube
  links; paste button reads copied URLs natively on iOS.
- White bottom toasts (`showToast`) instead of snack bars.
- Update banner / blocking screen via Firebase Remote Config.
- Keep the account with Google (profile → Account).
- Gradle 9.1 / AGP 9.0.1 / Kotlin 2.3.20.

## Decisions

- **No Apple sign-in**: an account made with Apple can't be restored after
  moving to Android.
- **No email + password**: anyone could make endless accounts with made-up
  emails. Only real identities (Google, later Telegram).
- **No phone sign-in for now**: every SMS costs money (`FeatureFlags.phoneSignIn`).
- **No WhatsApp sign-in**: there is no "Sign in with WhatsApp"; codes via
  WhatsApp Business API are paid.
- **Signing in is the gate**: no account without Google (later Telegram),
  no anonymous accounts in the app or the backend. The same Google
  account always brings the same Sinai account back. Anonymous accounts
  left from older versions are signed out; their data stays in the DB.
- The backend went live before the app release (almost no users yet):
  old app versions can no longer make accounts or sign in anonymously.

## Planned / ideas

- Security, left from the 2026-11-28 review: SSH without passwords on
  the server, database backups copied off the server, Firebase App Check,
  the Vimeo web view kept on Vimeo; maybe the owner approving new members.
  After the release with signed uploads, raise `min_build`.
- Profiles, next: more than photo and name (bio, a Message button for
  group members, shared media), maybe opened straight from a direct
  chat's header.
- Direct chats, next: what "Delete chat" means there (now the one who
  opened it deletes it for both, the other only leaves).
- Turn off the Anonymous provider in the Firebase console after the
  release (Daniel).
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

- `test/live/chat_bloc_backend_test.dart` still signs in through the removed `/v1/auth/guest`; needs the fake-Firebase sign-in the smoke test uses.

- Red heart emoji on Android, chess pieces in the release APK (fixed,
  waiting for Daniel's phone check).
- Pausing video while recording voice; the game-starts-while-menu-open fix
  (needs a second person).
