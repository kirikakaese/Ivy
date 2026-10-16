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
| Custom string table with English fallback | 2 | planned | planned | planned | Added with the first Ivy strings |
| RTL layouts | 1 | done | done | done | As upstream |
| Per-app language setting | 1 | done | done | done | System setting |
| Registration (primary) | 2 | planned | – | – | Primary is the iPhone |
| Linking (secondary) | 2 | – | planned | planned | |
| Send and receive messages | 2 | planned | planned | planned | |
| Upstream messaging, media, calls, groups | 2 | planned | planned | planned | As upstream |
| Notifications | 2 | planned | planned | planned | macOS live connection; iOS foreground and background refresh |
| Launch at login | 2 | – | – | planned | Platform-only; iOS uses background refresh |
| App icon / Dock unread badge | 2 | planned | planned | planned | |
| Client identity | 2 | done | done | done | Reports the upstream release, set in `Config/Ivy.xcconfig` |
| Stories | 2 | removed | removed | removed | |
| Payments | 2 | removed | removed | removed | |
| Donation prompts | 2 | removed | removed | removed | |
| Local-only diagnostics | 2 | planned | planned | planned | |
| About, license, privacy statement | 2 | planned | planned | planned | |

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
| Chat folders (official format) | 3 | planned | planned | planned | Tabs on iPhone, sidebar on iPad and Mac |
| Folder icon, color, unread badge | 3 | planned | planned | planned | |
| Folder reordering and bulk actions | 3 | planned | planned | planned | |
| Suggested folders | 3 | planned | planned | planned | |
| Per-folder pins | 3 | planned | planned | planned | |
| Pinned chat reordering | 3 | planned | planned | planned | |
| Ivy data store and device sync | 3 | planned | planned | planned | |
| Ivy data export and import | 3 | planned | planned | planned | |
| Remind me in… (messages and chats) | 3 | planned | planned | planned | |

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
