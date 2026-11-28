# Sinai — Flutter messenger

Chats joined by a 6-letter code, with photos, voice, reactions, games
(chess, checkers, tic-tac-toe) and YouTube watched together. Android and
iOS. The owner is Daniel; he speaks Russian (answer and ask in Russian),
commits with "закоммить", and tests on his own phone with a release APK.

Plans, history and open ideas: `docs/ROADMAP.md` (read when asked "what's
next" or before a bigger feature). Backend: `../sinai-go` (its own
`CLAUDE.md`).

## Stack

- Flutter, `flutter_bloc`, `auto_route` (routes in `lib/router/app_router.dart`;
  regenerate with `flutter pub run build_runner build --delete-conflicting-outputs`,
  then delete the stray `lib/gen/fonts.gen.dart`).
- Own Go backend over HTTPS + WebSocket: `lib/api/` (`ApiConfig.baseUrl`
  defaults to `https://5-222-26-206.sslip.io`, override with
  `--dart-define=API_BASE_URL=...`).
- Firebase only for: Auth (Google only; phone is built but off; no anonymous accounts),
  Messaging (push), Remote Config (update banner). Firestore, Realtime Database, Storage
  and Cloud Functions are emptied and locked (deny-all rules).
- Media in Cloudflare R2 via signed URLs from the backend.

## Map of `lib/`

- `main.dart` — start: Firebase, signs out leftover anonymous accounts, backend session
  (`AuthApi`), `LiveSocket`, update check, router, `toastOverlay`.
- `api/` — `ApiClient` (tokens, refresh), `LiveSocket` (events
  `{type, chat, data}`), `ChatsApi`, `chat_watch.dart` (live chat view:
  members, presence, `game`, `watch`, `serverTime`).
- `auth/` — `AuthRepository` (Google, phone, link/sign-in),
  `account_link.dart` (`linkOrSwitch`: add a way to sign in, or move to
  the account that owns it).
- `common/` — `toast.dart` (`showToast(msg, kind:)`, use it, not
  SnackBar), `emoji_text.dart` (colour emoji font; Inter has a black ❤),
  `app_icons.dart`, `feature_flags.dart`, buttons, app bar, dialogs.
- `features/chat/` — the chat screen.
  - `widgets/chat_header.dart` — the **notch**: droplet under the status
    bar, pulled down to show the icon menu (`notch_menu.dart`), a game
    board (`chat_games.dart`, `chess_game.dart`, `checkers_game.dart`,
    `tic_tac_toe.dart`) or the YouTube player; pulled further with the
    video open → full screen. Hops every 10 s when a game/video waits.
    One side margin for its content: `_notchInset`.
  - `widgets/watch_together.dart` — shared YouTube: `WatchState` (server
    clock sync), `WatchStore` (PATCH `{watch}`), one player per chat moved
    between notch and `WatchFullscreen` by GlobalKey (no reload),
    `videoHold` (pause while recording voice), end → rewind + pause.
  - `widgets/link_player.dart` — YouTube/Vimeo player inside a message.
  - `widgets/message_bubble.dart`, `message_field.dart` (voice recording),
    `reactions.dart`, `message_menu.dart`, `forward.dart`.
- `features/start_chat/bloc/` — `ChatBloc` (+ `chat_bloc_backend.dart`):
  chats list, messages, sending.
- `features/account/account_options.dart` — profile "Account" section and
  `RestoreScreen`. `features/phone/` — phone linking (flag off).
- `features/update/app_update.dart` — Remote Config `min_build`,
  `latest_build`, `update_url_android|ios`, `update_message`: banner or
  blocking screen. Build number = `+N` in `pubspec.yaml`.
- `ios/Runner/AppDelegate.swift` — channels `sinai/clipboard` (copied
  URL) and `sinai/setup` (`googleSignInReady`, guards a native crash).

## Rules and gotchas

- **After every finished task**, add one line to "Recent changes" at the
  top of `docs/ROADMAP.md`: date, what changed, files, and what is not
  verified yet. Keep only the last ~15 lines there; move older ones into
  "Done" as a short summary. Update "Planned" and "Decisions" when they
  change. Include the ROADMAP edit in the task's commit.

- Commit only when asked; branch `development`; end commit messages with
  the Co-Authored-By line. Push only when asked.
- Don't build/run the simulator unless asked; `flutter analyze` is enough.
  When running against the production backend, **never** send messages or
  start games in real chats — use the test chat "Test YouTube"
  (code 4U4QJV, only Daniel in it).
- Release builds tree-shake icon fonts: every glyph must be a `const
  IconData` somewhere, even when drawn as text (see `chess_game.dart`).
- The app is portrait-only; only `WatchFullscreen` turns to landscape.
- iOS draws web views (YouTube) above Flutter overlays: put controls
  next to the video, not over it.
- Toasts and the update gate sit above the navigator: no `Tooltip`
  there (no Overlay).
- Never paste secrets into chat; Daniel puts keys in files himself.
- Disk on the Mac is small (~6 GB free): clean `build/`, Xcode
  DerivedData and old Gradle when it fills up.
- Android build: Gradle 9.1.0 / AGP 9.0.1 / Kotlin 2.3.20 on Homebrew JDK
  17.0.15 (`flutter config --jdk-dir`); Android Studio's JDK 17.0.9 crashes.
- `dart format` touches unrelated files: format only the files you edited.

## Commands

```bash
flutter analyze lib
flutter build apk --release            # build/app/outputs/flutter-apk/app-release.apk
flutter build ios --simulator --debug  # then launch build/ios/iphonesimulator/Runner.app
```
