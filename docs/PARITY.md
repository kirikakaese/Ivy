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
| Chat folders (official format) | 3a | done | done | done | Synced as storage service `ChatFolderRecord`; chips above the chats on iPhone and a narrow iPad, in the sidebar on the Mac and a wide iPad |
| Folder unread badge | 3a | done | done | done | Number of chats with unread messages |
| Folder emoji and color | 3b | done | done | done | Stored in the Ivy data store |
| Folder reordering and bulk actions | 3a | done | done | done | Mark all as read, mute, unmute |
| Suggested folders | 3a | done | done | done | Unread, 1:1 chats, groups |
| Per-folder pins | 3b | done | done | done | Up to 4 per folder, above the other pinned chats |
| Pinned chat reordering | 3a | done | done | done | Drag and drop, plus Move Up and Move Down |
| Ivy data store and device sync | 3b | done | done | done | Own SQLCipher database; end-to-end encrypted sync messages to the user's own devices, per-field last edit wins |
| Ivy data export and import | 3b | done | done | done | Passphrase-encrypted file (PBKDF2, AES-GCM) |
| Remind me in… (messages and chats) | 3b | done | done | done | Presets, custom date with repeat, notification actions, list, markers; shown in the calendar |

## Productivity

| Feature | Phase | iPhone | iPad | macOS | Notes |
|---|---|---|---|---|---|
| Tasks | 4a | done | done | done | From a message or from scratch; notes, due date with reminder, lists, priority, subtasks; the link and quote go when the message is deleted or disappears |
| Calendar views | 4b | done | done | done | Agenda (90 days, overdue tasks first), day, week and month; events, tasks with a due date and open reminders together. The compact "today" overview is the Today section on Home |
| Events from messages and date detection | 4b | done | done | done | "Add to Calendar" in the message menu, prefilled with the first date found on the device (`NSDataDetector`); repeat and alert |
| ICS export, import and sending | 4b | done | done | done | Export one or all events, import with update by UID, send an event to a chat as an `.ics` file |
| Home tab | 4c | done | done | done | Quick actions (message, task, event, reminder), today's agenda, open tasks with check-off, important unread messages (mentions, replies, pinned and chosen chats, due reminders), unread chats by folder |
| Navigation and start tab setting | 4c | done | done | done | Home · Chats · Calendar · Calls. iPhone and a narrow iPad: tab bar, folders as chips above the chats. Mac and a wide iPad: the system sidebar with the sections and the folders (with unread counts and right-click menus), next to the list and the chat; View > Hide Sidebar (⌃⌘S). Opens with Chats unless set in Settings > Home and Navigation |

## Integrations

| Feature | Phase | iPhone | iPad | macOS | Notes |
|---|---|---|---|---|---|
| Apple Calendar and Reminders (one-way) | 5a | done | done | done | Events in a calendar named Ivy, tasks in a list named Ivy; set per device; changes made in Apple are replaced |
| Apple Calendar and Reminders (two-way) | 5a | done | done | done | Changes, new and deleted items in Ivy's calendar and list come back to Ivy; Ivy wins when both sides changed. Alerts, subtasks, lists and linked messages stay in Ivy |
| Widgets | 5b | done | done | in progress | Today, Tasks and Unread on the Home Screen, Lock Screen and Mac desktop. The Mac needs the signed app (Phase 7): the ad hoc beta has no app group |
| Menu bar extra / Control Center control | 5b | done | done | done | Agreed equivalents. iPhone and iPad (iOS 18): a New Task control. Mac: unread count, today's agenda, open tasks, new task or event |
| Shortcuts and Siri | 5c | done | done | done | Add Task (with due date and reminder), What's on Today, Open in Ivy (Home, Chats, Calendar, Calls, Tasks); Siri phrases in English and German; iOS 17 and later |
| Keyboard shortcuts | 5c | – | done | done | iPhone has no hardware keyboard support. ⌘1–⌘4 for Home, Chats, Calendar and Calls, ⌥⌘T new task, ⌥⌘E new event; on the Mac in the View and File menus |
| Text size | 5c | – | done | done | View > Make Text Bigger (⌘+), Make Text Smaller (⌘−), Actual Size (⌘0), kept per device; iPhone uses the system text size |
| Share extension | 5b | done | done | in progress | Upstream's share extension. The Mac needs the signed app (Phase 7) |

## Extras

| Feature | Phase | iPhone | iPad | macOS | Notes |
|---|---|---|---|---|---|
| Scheduled messages | 6a | done | done | done | Hold or right-click the send button: Send Later with the reminder presets or a chosen time. Synced; the writing device sends, another device takes over after 10 minutes. Text only. Listed on Home and in chat settings |
| Starred messages | 6a | done | done | done | Star or Remove Star in a message's menu; a star next to the time; list on Home; synced; removed when the message is deleted |
| Chat notes | 6a | done | done | done | Chat settings > Note; synced, only on the user's devices |
| Voice note speed and transcription | 6a | done | done | done | Speed is remembered per chat (as upstream); Transcribe in the message menu, on the device only |
| Hidden chats | 6a | done | done | done | Hide Chat in a chat's menu; hidden chats leave the chat list and search until shown with Face ID, Touch ID or the device passcode (profile menu > Show Hidden Chats), and hide again when Ivy leaves the screen. Their notifications show neither name nor content. Synced |
| Ivy passcode and app lock | 6a | done | done | done | Settings > Privacy > Ivy Passcode (with Screen Lock on): unlocking asks for the Ivy passcode instead of the device's; Face ID or Touch ID can stay as a shortcut. Wrong attempts make the next try wait, from 30 seconds up to an hour. Stored as a salted hash on the device only, never synced. The Mac locks Ivy when the screen locks or the Mac sleeps |
| Instant lock | 6a | done | done | done | Lock Ivy in the profile menu, File menu and ⌃⌘L; needs Screen Lock |
| Duress passcode and decoy mode | 6a | done | done | done | Settings > Privacy > Ivy Passcode > Duress Passcode. Entering it opens a decoy chat list with made-up chats that live only in memory and never send anything; the Notes chat has a button that deletes all Ivy data on the device. Leaving the app returns to the passcode screen |
| Metadata trimming | 6a | done | done | done | As upstream: Signal removes image metadata before sending; link previews can be turned off in Settings > Chats |
| Search with filters | 6b | done | done | done | Profile menu > Search Everything (⇧⌘F): messages, tasks, events and chat notes, with filters for chat, person, date and has link, photo or file. Uses the device's message index |
| Library of links, files and photos | 6b | done | done | done | Profile menu > Library (⇧⌘L): links, photos and files from all chats, newest first, with the chat, person and date filters. Shown as a list; tapping opens the link or the message |
| Waiting on you | 6b | done | done | done | Home > Waiting on You: the last message of recent chats when it asks the user something and the user hasn't replied, from the last 7 days. In groups only questions that mention or reply to the user. Detection runs on the device; Done puts a question aside on this device |
| Focus per folder | 6b | done | done | done | Folder > Notifications: only at certain days and hours, synced. An Apple Focus can have an Ivy filter that names folders; while it is on, only chats in those folders notify. Applies to message notifications |
| Quiet summary | 6b | done | done | done | Settings > Notifications > Muted Chats Summary: one notification a day at a chosen time with the unread messages in muted chats |
| Snooze a chat | 6b | done | done | done | Snooze in a chat's menu: later today, tonight, tomorrow, next week or a chosen time. The chat leaves the chat list and comes back marked unread. Profile menu > Snoozed Chats lists them. Synced |
| Drafts | 6c | done | done | done | Home > Drafts: unsent messages across chats, newest first. Tap to continue, swipe to discard |
| Snippets | 6c | done | done | done | Settings > Ivy Data > Snippets. Typing ;trigger and a space in any message inserts the text. Synced |
| Plan from the calendar | 6c | planned | planned | planned | Needs scheduled messages (6a) |
| Shared plans | 6c | planned | planned | planned | Other Signal apps get an `.ics` file |
| Task from a voice note | 6c | planned | planned | planned | On-device transcription |
| Weekly review | 6c | planned | planned | planned | |
| Multiple windows | 6d | – | planned | planned | |
| Quick reply from the menu bar | 6d | – | – | planned | Mac only |
| Global hotkey | 6d | – | – | planned | Mac only |
| Lock a chat | 6d | planned | planned | planned | |
| Disappearing messages per folder | 6d | planned | planned | planned | |
| Link previews per chat | 6d | planned | planned | planned | |

## Release

| Feature | Phase | iPhone | iPad | macOS | Notes |
|---|---|---|---|---|---|
| Accessibility review | 7 | planned | planned | planned | |
| Signed and notarized builds | 7 | planned | planned | planned | |
| Sparkle updates | 7 | – | – | planned | Platform-only distribution mechanism |
