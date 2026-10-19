# Ivy – Project Specification

Status: agreed in Phase 0 (Discovery). Changes to this document go through a pull request.

## 1. Overview

Ivy is an independent, privacy-respecting messenger for iPhone, iPad and Mac that is compatible with the Signal network. It is a fork of [Signal-iOS](https://github.com/signalapp/Signal-iOS) that adds quality-of-life features for organizing conversations and turning messages into reminders, tasks and calendar entries.

Goals:

- Full compatibility with the Signal network, using upstream Signal-iOS and libsignal unchanged wherever possible.
- One feature set on all platforms. A feature is done only when it works on iOS (iPhone and iPad) and macOS.
- Custom features kept separate from upstream code so upstream releases can be merged quickly.
- Public source code and public builds.

Non-goals:

- Changing the Signal protocol or running our own Signal server.
- Distribution through the App Store.

## 2. Platforms and distribution

| Topic | Decision |
|---|---|
| iOS devices | iPhone and iPad |
| Minimum iOS | Same as upstream at the tracked release (currently iOS 15.0; re-checked on each upstream merge) |
| macOS | Mac Catalyst build of the same app, Apple Silicon only |
| Minimum macOS | The lowest version supported by the Catalyst build of the tracked upstream release (determined in Phase 1) |
| Build tools | The Xcode version upstream uses (Xcode 26.6 at Signal-iOS 8.32) |
| Apple developer account | Paid account (pending). Until it exists, builds are made locally with Xcode |
| iOS distribution | Public source code with build and install instructions; ad-hoc builds for known testers once the paid account exists. Alternative channels (for example EU alternative marketplaces) may be evaluated later |
| macOS distribution | Developer ID signed and notarized direct download from GitHub Releases |
| macOS updates | Sparkle, with a signed update feed hosted on GitHub Releases and no usage data collection |
| Repository | Public on GitHub |
| CI | GitHub-hosted macOS runners build and test both the iOS and the macOS app on every push and pull request |

## 3. Architecture

- **Mac Catalyst.** The macOS app is the Catalyst build of the iOS app. All business logic and nearly all UI are shared. Platform-specific code is limited to menus, windowing, menu bar extra, Dock, login item and keyboard handling.
- **Early Catalyst check.** Phase 1 starts by proving that libsignal, RingRTC/WebRTC and all other dependencies build for Catalyst. If calls or any other dependency cannot be made to work, the project pauses for a decision before continuing.
- **Isolation of custom code.** Custom features live in separate Ivy modules and folders (for example `Ivy/` and `IvyKit/`). Changes inside upstream files are kept to small, clearly marked integration points (a comment `// Ivy:` on each touched spot) so that conflicts during upstream merges are easy to find.
- **Ivy data store.** Data that only Ivy knows about (reminders, tasks, calendar events, folder extras, per-folder pins, starred messages, chat notes, schedules) is stored in a separate local database next to the upstream database, encrypted at rest the same way upstream data is.

## 4. Accounts and devices

- The Ivy app on the iPhone is the **primary device** and registers the phone number.
- The Ivy app on the Mac and on the iPad are **linked devices**.
- Development and testing use a **separate test phone number**, never a personal account.
- Multiple accounts and account switching are not planned.
- Usernames, phone number privacy, registration lock / PIN and device transfer stay as upstream.

## 5. Use of Signal's servers

- Ivy connects to Signal's production servers. Signal does not support third-party clients; accounts can be rate-limited or blocked and the API can change without notice. This risk is accepted.
- **Client identity.** Ivy reports the exact upstream Signal-iOS version it is built on, in the same form as the upstream client, never a newer or invented version. Network behavior stays identical to that upstream version; only local features and UI differ. The identity is defined in one place so it can be changed with a one-line edit.
- **Exception:** Ivy-to-Ivy device sync (section 9.6) sends additional end-to-end encrypted sync messages between the user's own devices. Their content is unreadable to the server and they are ignored by official clients.
- Because the server stops accepting outdated clients and upstream builds expire after about 90 days, timely upstream merges (section 7) are mandatory.

## 6. Notifications

Signal's servers send Apple push notifications only to the official app, so Ivy does not receive them.

| Platform | Strategy |
|---|---|
| macOS | Keeps a live connection while running. Launch at login and a menu bar extra keep it running; notifications arrive in real time |
| iOS / iPadOS | Live connection while the app is in the foreground, plus Background App Refresh. Delivery while in the background is delayed and not guaranteed |
| All | Reminders, task due dates and calendar alerts are local notifications and are reliable on all platforms |

A self-hosted relay (similar to MollySocket) or a hybrid setup with the official app may be evaluated later as a separate decision.

## 7. Upstream strategy

- Base: the latest **stable** Signal-iOS release at the start of Phase 1 (betas excluded).
- History: upstream git history is kept. Upstream commits keep their original authors; every commit made for Ivy uses the project identity.
- Cadence: every upstream stable release, at least monthly.
- Merges happen on a dedicated branch and pull request per upstream release, with CI green on both platforms.
- When an upstream change breaks a custom feature, the merge PR fixes it or, if that is not possible in a reasonable time, the feature is temporarily disabled on **both** platforms and the parity matrix records it.
- If upstream later implements a feature Ivy already has (for example chat folders on iOS), Ivy switches to the upstream implementation where possible and keeps only its extras.
- The upstream sync procedure is documented in the repository (Phase 1).

## 8. Localization

- All locales shipped by upstream Signal-iOS are supported, using upstream's official translation files (`Localizable.strings`, `.stringsdict`, `InfoPlist.strings` and other localized resources). At Signal-iOS 8.32 this is 47 locales:
  ar, be, bg, bn, ca, cs, da, de, el, en, es, fa, fi, fr, ga, gu, he, hi, hr, hu, id, it, ja, ko, lt, mr, ms, nb, nl, pl, pt_BR, pt_PT, ro, ru, sk, sr, sv, th, tr, ug, uk, ur, vi, yue, zh_CN, zh_HK, zh_TW.
- A sync script and documentation pull translations from the tracked upstream release.
- **Custom strings** live in a separate table (`Ivy.strings` / `Ivy.stringsdict` per locale) that upstream syncs never touch. English is required for every custom string; other languages are added when translations are supplied. Missing translations fall back to English.
- **Language selection** uses Apple's per-app language setting (iOS Settings and macOS System Settings). No custom in-app switcher.
- **Right-to-left** languages (ar, fa, he, ug, ur) get mirrored layouts, correct alignment and correct icon mirroring. RTL is verified with screenshots and pseudo-locales, since the maintainer tests English and German.
- Plurals use `.stringsdict`; numbers, dates and times use the system formatters for the active locale.
- The app name is "Ivy" in every language.

## 9. Features

### 9.1 Upstream features

All standard Signal features stay as upstream unless listed below.

**Removed or hidden:** Stories, Payments (MobileCoin), donation prompts and donation flows.

**Kept:** release-notes megaphones and all other messaging, media, calls, groups, notification, appearance and accessibility features.

### 9.2 Branding and About

- Name: Ivy. Bundle ID prefix: `io.github.kirikakaese` (main app `io.github.kirikakaese.ivy`).
- Own placeholder icon and color palette, clearly distinct from Signal's. Neither the Signal name nor Signal's logo or brand colors are used in the app identity.
- The About screen shows the app name, version, the upstream version it is based on, "kiri" as maintainer, the AGPLv3 notice with a link to the source code, the upstream copyright notices, a short privacy statement, and the notice that Ivy is not affiliated with Signal.

### 9.3 Folders

- Based on Signal's official chat folder format (storage service `ChatFolderRecord`), so folders sync between Ivy devices through Signal and stay compatible with official clients that support folders.
- Options per folder (official format): included chats, excluded chats, all 1:1 chats, all group chats, only unread, show muted chats.
- Ivy extras (stored in the Ivy data store and synced via section 9.6): icon or emoji, color, per-folder pins.
- Unread badge per folder.
- Folders can be reordered.
- Bulk actions: mark folder read, mute folder.
- Suggested folders on first use (for example Unread, 1:1, Groups).
- UI: scrollable folder chips above the chat list on iPhone and a narrow iPad; on the Mac and a wide iPad the folders are part of the sidebar, below the sections.

### 9.4 Pinned chats

- Pinned chats can be rearranged by drag and drop (touch, mouse and trackpad), plus "Move up" / "Move down" actions in the context menu for accessibility.
- The order is stored in the official account record and syncs to all devices.
- The pin limit stays at Signal's limit of 4.
- Per-folder pins (section 9.3) are an Ivy extra on top.

### 9.5 Remind me in…

- Available for individual messages and for whole chats.
- Presets: 20 minutes, 1 hour, 3 hours, later today, tonight, tomorrow morning, next week, custom date and time (with optional repeat).
- When a reminder fires: local notification that opens the exact message or chat, chat marked unread, chat temporarily moved to the top, notification actions "Snooze 1 h", "Tomorrow" and "Done".
- Visible in: a reminders list, an indicator on the message or chat, the calendar, and a marker in the chat list.
- Reminders sync to all Ivy devices (section 9.6); a reminder fires once per device and is marked done everywhere when handled on one.

### 9.6 Ivy data sync

- Ivy-only data syncs between the user's Ivy devices with end-to-end encrypted sync messages sent through Signal to the user's own devices. No third-party service is involved.
- Conflicts are resolved per field with "last edit wins".
- A newly linked device receives a full copy of the Ivy data.
- Encrypted export and import of all Ivy data is available as a backup.
- Before relying on it, tests confirm that official clients on the same account ignore these messages.

### 9.7 Tasks

- A task can be created from any message (or from scratch). Tasks are private and never sent to chat partners.
- Fields: title (prefilled from the message text, editable), notes, due date with reminder, lists or tags, priority, subtasks.
- A task links back to its message.
- If the source message is deleted or disappears, the task stays but the quoted message content and the link are removed.

### 9.8 Calendar

- Shows tasks with due dates, reminders, and events.
- Events can be created from messages (linked back to the message). On-device date detection offers "Add to calendar" for dates in messages.
- Views: agenda list, day, week, month, and a compact "today" overview.
- Export and sync with other apps:
  - ICS export and import.
  - One-way sync to Apple Calendar and Reminders (EventKit).
  - Two-way sync with Apple Calendar and Reminders.
  - Sending an event as an `.ics` attachment in a chat (official Signal users receive a normal file).
- Data written to Apple Calendar or Reminders leaves Signal's end-to-end encryption; the app states this when the user enables it.

### 9.9 Home tab and navigation

- Main sections: **Home · Chats · Calendar · Calls**. iPhone uses a tab bar; iPad and Mac use a sidebar with the same sections.
- Home contains: today's agenda, open tasks (overdue and upcoming, with quick check-off), unread counts by folder, important unread messages, and quick actions (new message, new task, new event, new reminder).
- Important unread messages: @mentions and replies to the user, unread messages in pinned chats, messages from a user-chosen list of contacts, and messages whose reminder has fired.
- Start tab: Chats by default, configurable in settings.

### 9.10 Platform integrations

Each integration exists on both platforms or has an agreed equivalent.

| Integration | iOS / iPadOS | macOS |
|---|---|---|
| Widgets (today, tasks, unread) | Home Screen and Lock Screen widgets | Desktop and Notification Center widgets |
| Quick access | Control Center control and widgets | Menu bar extra (unread count, today agenda, quick task) |
| Shortcuts and Siri | App Intents: add task, remind me, show today | Same App Intents |
| Keyboard shortcuts | iPad hardware keyboard | Menu commands and shortcuts |
| Share extension | Share to Ivy | Share to Ivy |
| Launch at login | Not applicable (background refresh instead) | Login item |
| Unread badge | App icon badge | Dock badge |

### 9.11 Messaging extras

- **Scheduled messages.** The schedule syncs to all Ivy devices; the first online Ivy device sends the message at the scheduled time, with de-duplication so it is sent once. When only the iPhone is available, sending may be delayed.
- **Starred messages.** Bookmark messages; a list is available from Home.
- **Chat notes.** Private notes per chat.
- **Voice notes.** Remembered playback speed and on-device transcription only (no audio leaves the device).

### 9.12 Privacy extras

- **Hidden chats.** Chats hidden behind Face ID / Touch ID or the Ivy passcode. Their notifications show a generic "New message" without name or content.
- **Stronger app lock.** An optional Ivy passcode in addition to Face ID / Touch ID; on Mac, locking on sleep and screen lock.
- **Instant lock.** A quick action, gesture or shortcut that locks Ivy immediately.
- **Duress passcode and decoy mode.** Entering the duress passcode opens a decoy mode that shows several fake local-only chats plus a designated chat containing a wipe button. Wiping deletes all Ivy data on the device. Decoy chats never send anything to the network.
- **Metadata trimming.** Options such as always stripping image metadata and turning link previews off by default.

### 9.13 Finding and focus

- **Search with filters.** One search across chats, tasks, events and chat notes, with filters for person, chat, date, and "has link", "has photo" or "has file". Runs on the device.
- **Library.** Every link, file and photo from all chats in one place, sorted by chat or type, with the same filters.
- **Waiting on you.** Questions the user was asked and hasn't answered appear on Home. Detection runs on the device and only looks at recent messages in one-to-one chats and groups where the user was mentioned or replied to.
- **Focus per folder.** Each folder can have notification hours (for example Work only on weekdays 9–18). Ivy can follow Apple's Focus: a Focus can be linked to folders that may notify while it is on.
- **Quiet summary.** Muted chats can collect into one summary notification at a time the user chooses, instead of separate badges.
- **Snooze a chat.** Hide a chat until a chosen time (later today, tomorrow, Monday). It comes back marked unread. Snoozes sync to all Ivy devices.

### 9.14 Writing and planning

- **Drafts.** All unfinished messages across chats in one list on Home.
- **Snippets.** Reusable texts (address, "on my way") inserted with a short trigger such as `;addr`. Synced to all Ivy devices.
- **Plan from the calendar.** Dragging a draft or a new message onto a time in the calendar schedules it (builds on scheduled messages).
- **Shared plans.** In a group, propose an event with time options; members answer with a tap and the agreed time lands in everyone's Ivy calendar. Other Signal apps receive a normal message with an `.ics` file and the options as text.
- **Task from a voice note.** A voice note to yourself (Note to Self) can become a task; the text is transcribed on the device.
- **Weekly review.** A screen, offered once a week at a chosen time: open and overdue tasks, next week's events, chats waiting for an answer.

### 9.15 Mac and privacy additions

- **Multiple windows (Mac and iPad).** Open a chat in its own window; windows remember their chat.
- **Quick reply from the menu bar (Mac).** The menu bar extra shows the latest messages and lets the user answer without opening the main window.
- **Global hotkey (Mac).** A system-wide shortcut, chosen in Settings, brings Ivy to the front or opens a new message.
- **Lock a chat.** Single chats can require Face ID, Touch ID or the Ivy passcode to open, separate from hidden chats.
- **Disappearing messages per folder.** A folder can set the disappearing messages timer for the chats in it; changing a chat's timer works as in Signal and is visible to the other members.
- **Link previews per chat.** Link previews can be turned off for single chats.

### 9.16 Diagnostics

- No crash reporter and no analytics.
- Debug log upload to Signal's servers is disabled; debug logs can only be exported locally by the user.

## 10. Quality and process

- **Tests:** upstream tests pass on both platforms; every custom feature has unit tests; custom screens get UI or snapshot tests.
- **CI:** both apps build and all tests pass on every push and pull request. A failure on either platform blocks the pull request.
- **Parity:** `docs/PARITY.md` lists every feature with its status on iOS and macOS and is updated in every pull request that touches features.
- **Pull requests:** one branch and one pull request per phase, containing a summary, the iOS/macOS parity status, the translation status and a verification checklist for iPhone, iPad and Mac. The maintainer reviews and merges every pull request.
- **Reports:** short summaries plus charts for the phase roadmap, the parity matrix, translation coverage and CI status.
- **Documentation:** specification, parity matrix, building, upstream sync, translation sync and a maintenance guide.

## 11. Legal

- **License:** AGPLv3. The source code stays public; the About screen links to it and shows the license and upstream copyright notices.
- **Trademark:** own name and icon; "compatible with the Signal network" is the only reference to Signal in branding contexts, together with a non-affiliation notice in the app and the README.
- **Export compliance:** documentation of the encryption export status for public distribution (Phase 7).
- **Privacy statement:** a short statement of what Ivy sends and stores (Phase 2, updated as features are added).

## 12. Phase plan

Each phase is one branch and one pull request. The next phase starts after the previous pull request is merged.

| Phase | Goal |
|---|---|
| 0 – Discovery | Specification, parity matrix and phase plan |
| 1 – Foundation | Ivy builds and runs, rebranded, on iPhone, iPad and Mac in all upstream languages: upstream import, rebrand, Catalyst, CI for both platforms, translation handling, documentation. The custom string table is added in Phase 2 together with the first Ivy strings |
| 2 – Working messenger | Register, link, send and receive on both platforms with the agreed notification strategy; removals; custom string table; client identity; local-only diagnostics; About, privacy statement and non-affiliation notice |
| 3a – Chat folders | Folders in the official format with tabs and sidebar, unread badges, reordering, bulk actions, suggested folders; pinned chat reordering |
| 3b – Ivy data | Ivy data store with device sync and export/import, folder icon and color, per-folder pins, "Remind me in…" |
| 4a – Tasks | Tasks from messages or from scratch, with notes, due date and reminder, lists, priority and subtasks; synced with the Ivy data store |
| 4b – Calendar | Events, calendar views, date detection in messages, ICS export, import and sending |
| 4c – Home and navigation | Home tab and the new navigation: Home, Chats, Calendar, Calls; start tab setting |
| 5a – Apple Calendar and Reminders | One-way and two-way sync of events and tasks with Apple Calendar and Reminders |
| 5b – Widgets and quick access | Widgets, menu bar extra and Control Center control, share extension |
| 5c – Shortcuts and keyboard | Shortcuts and Siri, keyboard shortcuts |
| 6a – Extras | Scheduled messages, starred messages, chat notes, voice note features, hidden chats, decoy mode and duress passcode, app lock, metadata trimming |
| 6b – Finding and focus | Search with filters, library, waiting on you, focus per folder, quiet summary, snoozing chats |
| 6c – Writing and planning | Drafts, snippets, planning from the calendar, shared plans, tasks from voice notes, weekly review |
| 6d – Mac and privacy additions | Multiple windows, quick reply from the menu bar, global hotkey, locked chats, disappearing messages per folder, link previews per chat |
| 7 – Polish and release | Accessibility, performance, upstream merge rehearsal, signing, notarization, Sparkle, user documentation and maintenance guide |

If a phase turns out larger than expected, work stops and a split is proposed before continuing.

## 13. Open items

To be decided at the start of the phase that needs them:

- iPadOS version on the test iPad (9th generation) – Phase 1.
- Exact minimum macOS version for the Catalyst build – Phase 1.
- Placeholder icon and palette review – Phase 1.
- Content and setup of decoy chats – Phase 6.
- Whether to evaluate a self-hosted notification relay – after Phase 2.
