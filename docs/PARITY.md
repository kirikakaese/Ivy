# Feature Parity Matrix

Every feature must work on iOS (iPhone and iPad) and macOS before it counts as done. Every pull request that touches a feature updates this table.

Status values: `planned`, `in progress`, `done`, `removed`, `disabled` (temporarily off on both platforms, with a reason).

## Foundation and upstream

| Feature | Phase | iPhone | iPad | macOS | Notes |
|---|---|---|---|---|---|
| Builds and launches | 1 | done | done | done | macOS via Mac Catalyst, iPad interface; Apple Silicon only |
| Ivy branding (name, icon, bundle IDs) | 1 | done | done | done | Placeholder icon and green palette |
| "Ivy" in upstream strings that name the app | 1 | done | done | done | Reviewed rule list, applied at build time |
| Alternate app icons | 1 | disabled | disabled | disabled | Hidden until Ivy has its own variants |
| All upstream locales (47) | 1 | done | done | done | |
| Custom string table with English fallback | 2 | done | done | done | English and German |
| RTL layouts | 1 | done | done | done | As upstream |
| Per-app language setting | 1 | done | done | done | System setting |
| Registration (primary) | 2 | done | – | – | Primary is the iPhone; without push, Signal asks for a captcha |
| Linking (secondary) | 2 | – | done | done | The Mac always links, like the iPad |
| Send and receive messages | 2 | done | done | done | |
| Upstream messaging, media, calls, groups | 2 | done | done | done | As upstream |
| Notifications | 2 | done | done | done | No Apple push: macOS keeps a live connection; iOS in the foreground and through Background App Refresh |
| Launch at login | 2 | – | – | done | Settings > Notifications > Open at Login |
| App icon / Dock unread badge | 2 | done | done | done | As upstream |
| Client identity | 2 | done | done | done | Reports the upstream release, set in `Config/Ivy.xcconfig` |
| Stories | 2 | removed | removed | removed | Hidden; the synced account setting is left unchanged |
| Payments | 2 | removed | removed | removed | Hidden; the profile keeps its payment address |
| Donation prompts | 2 | removed | removed | removed | Settings rows, badge sheet button and donation megaphones |
| Local-only diagnostics | 2 | done | done | done | Debug logs are exported, never uploaded |
| About, license, privacy statement | 2 | done | done | done | Settings > Help > About Ivy; Help points to Ivy's issue tracker |

## Platform differences

Upstream features that exist on the Mac in a reduced form, because the underlying Apple API does not exist there. Code paths are marked with `// Ivy:` comments.

| Feature | macOS behavior |
|---|---|
| Device transfer and quick restore | Uses MultipeerConnectivity only; Wi-Fi Aware is iPhone and iPad only |
| Multitasking camera access | Not needed; the Mac camera works while other windows are in front |
| Limited contact access picker | Not shown; contact access is all or nothing |
| Quick Look support check | Skipped; Quick Look shows a generic view for files it cannot render |
| File protection classes | The strictest iOS classes are not available; FileVault encrypts the files instead |

## Organization

| Feature | Phase | iPhone | iPad | macOS | Notes |
|---|---|---|---|---|---|
| Chat folders (official format) | 3a | done | done | done | Synced as storage service `ChatFolderRecord`; tabs above the chats, a sidebar when the chat list is next to a chat |
| Folder unread badge | 3a | done | done | done | Number of chats with unread messages |
| Folder icon and color | 3b | planned | planned | planned | |
| Folder reordering and bulk actions | 3a | done | done | done | Mark all as read, mute, unmute |
| Suggested folders | 3a | done | done | done | Unread, 1:1 chats, groups |
| Per-folder pins | 3b | planned | planned | planned | |
| Pinned chat reordering | 3a | done | done | done | Drag and drop, plus Move Up and Move Down |
| Ivy data store and device sync | 3b | planned | planned | planned | |
| Ivy data export and import | 3b | planned | planned | planned | |
| Remind me in… (messages and chats) | 3b | planned | planned | planned | |

## Productivity

| Feature | Phase | iPhone | iPad | macOS | Notes |
|---|---|---|---|---|---|
| Tasks | 4 | planned | planned | planned | |
| Calendar views | 4 | planned | planned | planned | |
| Events from messages and date detection | 4 | planned | planned | planned | |
| ICS export, import and sending | 4 | planned | planned | planned | |
| Home tab | 4 | planned | planned | planned | |
| Navigation and start tab setting | 4 | planned | planned | planned | |

## Integrations

| Feature | Phase | iPhone | iPad | macOS | Notes |
|---|---|---|---|---|---|
| Apple Calendar and Reminders (one-way) | 5 | planned | planned | planned | |
| Apple Calendar and Reminders (two-way) | 5 | planned | planned | planned | |
| Widgets | 5 | planned | planned | planned | |
| Menu bar extra / Control Center control | 5 | planned | planned | planned | Agreed equivalents |
| Shortcuts and Siri | 5 | planned | planned | planned | |
| Keyboard shortcuts | 5 | – | planned | planned | iPhone has no hardware keyboard support |
| Share extension | 5 | planned | planned | planned | |

## Extras

| Feature | Phase | iPhone | iPad | macOS | Notes |
|---|---|---|---|---|---|
| Scheduled messages | 6 | planned | planned | planned | |
| Starred messages | 6 | planned | planned | planned | |
| Chat notes | 6 | planned | planned | planned | |
| Voice note speed and transcription | 6 | planned | planned | planned | On-device only |
| Hidden chats | 6 | planned | planned | planned | |
| Ivy passcode and app lock | 6 | planned | planned | planned | |
| Instant lock | 6 | planned | planned | planned | |
| Duress passcode and decoy mode | 6 | planned | planned | planned | |
| Metadata trimming | 6 | planned | planned | planned | |

## Release

| Feature | Phase | iPhone | iPad | macOS | Notes |
|---|---|---|---|---|---|
| Accessibility review | 7 | planned | planned | planned | |
| Signed and notarized builds | 7 | planned | planned | planned | |
| Sparkle updates | 7 | – | – | planned | Platform-only distribution mechanism |
