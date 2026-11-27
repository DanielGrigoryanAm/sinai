# Sinai roadmap

Keep this short: what is done, what is planned, what was decided and why.
Update it when a feature lands or a plan changes.

## Recent changes

Newest first, one line per task (see the rule in `CLAUDE.md`).

- 2026-11-28 — Fixed a deleted chat flashing back: a list asked for before the backend deleted it could arrive after; the bloc now keeps deleted chats hidden until a list asked for after the deletion arrives, and Messages no longer reloads right on delete (`chat_bloc_backend.dart` `_gone`, `chats_screen.dart`). Not checked on a device.
- 2026-11-28 — Colors split: profile → Appearance → App colors (accent, background, cards; everywhere) and chat info → Chat colors (my messages, text; that chat only, saved per chat on the device in `theme/chat_colors_store.dart`, applied by `ChatColorsScope` around the chat screen). `ColorSlot.isChat`, shared `_ColorsScreen` in `app_colors_screen.dart`; `profile_screen.dart`, `chat_info_sheet.dart`, `chat_screen.dart`, `main.dart`. Not checked on a device.
- 2026-11-28 — Direct chats' info sheet no longer lists members; the other person's photo at its top opens their profile (`chat_info_sheet.dart`). Not checked on a device.
- 2026-11-27 — Other people's profiles: `PersonProfileScreen` (photo, tap for full screen; name; online / last seen, live from the chat). Opens from a member row in the chat info sheet, and in a direct chat from the other person's photo at the top of the sheet; member rows now show photos (`person_profile_screen.dart`, `chat_info_sheet.dart`). Not checked on a device.
- 2026-11-27 — Message field: the gold PNG photo/mic/send pictures replaced by Flaticon UIcons Regular rounded (`picture`, `microphone`, `paper-plane-top`) in the accent colour; the three glyphs were added to `UiconsRegular.ttf` from `@flaticon/flaticon-uicons` 3.3.1 (old glyphs unchanged), `assets/icons/` removed (`app_icons.dart` `photo`/`microphone`/`send`, `message_field.dart`, `pubspec.yaml`). Not checked on a device. Note: the bundled Uicons fonts are subsets of an older release with other codepoints; new glyphs keep the 3.3.1 codepoints.
- 2026-11-27 — Profile tidied into one style: photo and name on top, then sections (label, white rounded card with 52 px rows, caption) for the code (tap copies), the name (field with an inline Save), Account (Google row with a check) and a red Sign out row; new `common/settings_section.dart` (`SettingsSection`, `SettingsRow`), used by `profile_screen.dart` and `AccountSection` (`account_options.dart`). Not checked on a device.
- 2026-11-27 — Messages: "Search chats..." field is now the shared `RoundField` (same look and height as message search, clear button) instead of its own `_SearchField` (`chats_screen.dart`). Not checked on a device.
- 2026-11-27 — One back button everywhere: `CustomAppBar(showBackButton: true)` now draws the chat's edge tab (title and actions lined up with it, optional `bottom` for tabs), so New chat, Create chat, Profile, Phone get it; App colors and Media moved from plain `AppBar` to it. The photo viewer's close and the crop editor's Cancel stay (`custom_app_bar.dart`, `app_colors_screen.dart`, `chat_media_screen.dart`). Not checked on a device.
- 2026-11-27 — New message screen gets message search's top: the chat's back tab and the rounded field (with Paste while empty), now shared as `EdgeFieldBar` / `RoundField` in `common/round_field.dart` (`find_person_screen.dart`, `message_search_screen.dart`). Not checked on a device.
- 2026-11-27 — No double messages on retry: the outbox sends its `local-…` id as `clientId`; the backend (migration 0007, unique per sender) returns the first message for a repeat with 200 and no new event. The app swaps the "sending" copy by `clientId` instead of matching text (`outbox.dart`, `chats_api.dart`, `chat_message_model.dart`, `chat_bloc_backend.dart`; backend `internal/messages`). Smoke passes (76); deployed; not checked on a device.
- 2026-11-27 — Offline cache and outbox: the chats list and each chat's newest 60 messages are kept per account (`api/local_cache.dart`) and show at once, then refresh quietly; deleting/leaving a chat, sending text/photos/voice, editing, deleting messages and reactions apply on screen at once and go through `api/outbox.dart` (on disk, in order, retried with backoff and on socket reconnect; a 4xx drops the op and the screen reloads). Sign-out clears both. Wired in `chat_bloc_backend.dart`, `chats_api.dart`, `chat_message_model.dart` (`toJson`, `copyWith`), `main.dart`, `account_link.dart`. Not checked on a device.
- 2026-11-27 — Photo editor for profile and chat photos: after picking, `PhotoCropScreen` shows a clear circle over a dimmed photo; drag and pinch (double tap 1×/2×), the photo can't be made smaller than the circle or moved off it; Save crops the circle's square (≤600 px JPEG). `ChatAvatar` now clips with `ClipOval` and draws its ring on top (`photo_crop_screen.dart`, `chat_avatar.dart`, `profile_screen.dart`, `chat_info_sheet.dart`). Not checked on a device.
- 2026-11-27 — Message search screen: the chat's back tab (moved to `edge_tab.dart` as `EdgeTab`, shared with `chat_header.dart`) next to a rounded search field; "Type at least 2 letters" replaced by an empty state ("Search this chat" with a search mark), friendlier "Nothing found" / error texts (`message_search_screen.dart`). Not checked on a device.
- 2026-11-27 — Messages reloads its list quietly whenever it is on top again (router listener), so a chat just created, joined or opened by code shows without pulling to refresh (`chats_screen.dart`). Not checked on a device.
- 2026-11-27 — Sign out button drawn red (line, text, icon): `CustomButton.outline(color:)` (`custom_button.dart`, `profile_screen.dart`). Not checked on a device.
- 2026-11-27 — + menu buttons renamed "New chat" and "New message" (also the find screen's title and the empty-list hint) (`chats_screen.dart`, `find_person_screen.dart`). Not checked on a device.
- 2026-11-27 — Profile photo: tap the avatar in the profile to pick one from the gallery (or remove it); shown in the find-by-code card, the chats list and the header of direct chats. Backend: `POST /v1/me/uploads`, `PATCH /v1/me {photoUrl}`, files under `users/<id>/` readable by anyone signed in, photo URLs in members, peer, profile and sign-in (`internal/storage`, `internal/users`, `internal/chats`, `internal/auth`; app `profile_screen.dart`, `auth_api.dart`, `chat_watch.dart`). Smoke passes (74); deployed; not checked on a device.
- 2026-11-27 — Sign out in the profile (with a confirm): detaches the push token, stops the socket, ends the backend and Firebase sessions, clears drafts, back to onboarding (`account_link.dart` `signOut`, `profile_screen.dart`, `draft_store.dart`, `onboarding_prefs.dart`). Not checked on a device.
- 2026-11-27 — backend: deployed `feature/google-sign-in` (Google-only sign-in, personal codes, direct chats). Migrations 0005–0006 applied in production, all 22 users got distinct codes; `/v1/auth/guest` answers 404. Backup before it: `deploy/backups/sinai-before-direct-chats.dump` on the server. The app side waits for Daniel's APK test.
- 2026-11-27 — Local Docker (Colima) fixed by restarting it: its disk had gone read-only after the Mac ran out of space. Migrations 0005–0006 applied locally; smoke passes twice in a row (66 checks) after fixing it (`cmd/smoke`: new key id per run, the direct chat deleted at the end, Alice's socket checked). Colima's ext4 still asks for an fsck.
- 2026-11-27 — backend: direct chats — migration `0006_direct_chats.sql` (`chats.direct_key`, one chat per pair), `POST /v1/chats/direct {code}`, `GET /v1/users/{code}`; chats carry `direct`, the list a `peer`; direct chats can't be joined by code (`internal/chats`, `internal/users`, smoke). Not deployed.
- 2026-11-27 — App: + on Messages lifts two buttons, "Create or join a chat" (old screen) and "Message someone" → `FindPersonScreen`: type or paste a code, the person shows as a chat-row card with "Message", which opens the direct chat. Direct chats show the other person's name and photo; their info sheet hides the chat code and renaming (`new_chat_menu.dart`, `find_person_screen.dart`, `chats_screen.dart`, `chats_api.dart`, `chat_watch.dart`, `chat_info_sheet.dart`). Not checked on a device.
- 2026-11-27 — Personal code (like a username): backend migration `0005_user_codes.sql` gives every user a unique 8-character code (existing users too), returned as `code` in `/v1/me`; profile shows it under "YOUR CODE", tap copies (`users.go`, `auth_api.dart`, `profile_screen.dart`). Branch `feature/google-sign-in`, not deployed, not checked on a device.
- 2026-11-27 — backend: no anonymous accounts — `POST /v1/auth/guest` and `users.Create` removed, `/v1/auth/firebase` refuses tokens whose `sign_in_provider` is anonymous; smoke signs in via a fake Firebase on :9098 (`FIREBASE_TEST_CERTS_URL`) (`internal/auth`, `internal/users`, `internal/config`, `cmd/smoke`). Branch `feature/google-sign-in`, not deployed; `go test` and smoke pass.
- 2026-11-27 — App: no anonymous accounts — a leftover anonymous Firebase user is signed out at start (push token detached, backend session ended) and sees onboarding; profile → Account only shows the Google account (`main.dart`, `account_options.dart`). Not checked on a device.
- 2026-11-27 — Sign-in required: onboarding is now only "Continue with Google" (no name field, no anonymous sign-in, Restore screen removed); the backend finds the account by Firebase uid or makes one, name taken from Google (`onboarding_screen.dart`, `account_link.dart` `signInWith`, `account_options.dart`, `main.dart`, `onboarding_prefs.dart`, `auth_api.dart`, router). Not checked on a device.
- 2026-11-27 — Onboarding: gyro-floating mountain picture replaced by a plain 200 px circle with the same image (`onboarding_screen.dart`); `gyro_horizontal_background.dart` now unused. Not checked on a device.
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
