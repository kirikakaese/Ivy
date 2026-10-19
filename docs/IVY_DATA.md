# Ivy Data

Data that only Ivy knows about: folder emoji and color, per-folder pins, reminders, tasks with their lists, and calendar events.

## Storage

- Database: `ivy-db/ivy.sqlite` in the app group container, next to the upstream `grdb` folder. The folder name must not start with `grdb`, because upstream deletes such folders.
- Encryption: SQLCipher with a 48-byte raw key spec (256-bit key and 128-bit salt), like the upstream database. The key is in the keychain (`IvyDataKeyChainService` / `IvyDataCipherKeySpec`, accessible after first unlock, this device only).
- Reset: "Delete all data" removes the database and its key (`IvyData.deleteAll()`).

## Model

Every entity is a set of fields in the table `IvyDataField`:

| Column | Meaning |
|---|---|
| `kind` | `folder`, `reminder`, `task`, `taskList` or `event` |
| `entityId` | Folder id (hex), or the UUID of a reminder, task, task list or event |
| `field` | Field name, e.g. `color`, `pins`, `dueAt`, `done`; `deleted` marks a deleted entity |
| `value` | JSON value, or NULL when cleared |
| `millis`, `deviceId` | When and on which device the field was last edited |

Edits merge per field: the higher `(millis, deviceId)` wins. Each device's clock never goes backwards and moves past every timestamp it receives, so a later edit wins even when device clocks differ.

Chats and messages are named in a way that is the same on all devices: `a:<ACI>`, `e:<phone number>` or `g:<base64 group id>` for chats, and chat, timestamp and author ACI for messages.

## Sync

- Local edits are collected for two seconds and sent as a sync message to the user's own devices. The payload (`IvySyncPayload`, JSON) is in field 7301 of `SyncMessage`, which official clients do not know and skip ("unsupported sync message").
- Sync messages are end-to-end encrypted like all Signal messages and accepted only from the user's own account.
- A device asks for all data once (`requestSnapshot`); every Ivy device answers with `snapshot`. Settings > Folders, Tasks, Calendar and Sync > Get Data from Other Devices asks again.
- Large snapshots are split into payloads of about 64 KB.

## Export and import

The file starts with `IVYDATA1`, a 16-byte salt and the PBKDF2 iteration count (4 bytes, big endian), followed by an AES-256-GCM box with the JSON list of all fields. The key is derived from the passphrase with PBKDF2-HMAC-SHA256. An import merges like a sync from another device and sends what changed to the other devices.

## Reminders

Each device schedules a local notification for every open reminder that is still in the future. When a reminder comes due, the chat is marked unread once on each device and shown at the top of the chat list until the reminder is done. Snoozing or finishing a reminder on one device changes `dueAt` or `done`, which syncs, and the other devices update their notifications.

## Tasks

A task's fields are `title`, `notes`, `dueAt` (milliseconds), `allDay`, `reminds`, `list`, `priority`, `subtasks` (one JSON list), `source`, `done`, `completedAt` and `createdAt`. A task list has a `name`. Only the fields that changed are written, so renaming a task on one device and finishing it on another keeps both edits. Subtasks are one field, so two devices editing subtasks at the same time keep the later list.

- A task made from a message keeps the message's reference and up to 500 characters of its text (`source`). When the message is deleted on this device, disappears, or is deleted for everyone, `source` is cleared; the task stays. The deletion syncs like any other edit.
- A task that reminds gets a local notification on each device at its due time, or at 9:00 on its day when it is all-day. "Mark as Done" and "Tomorrow" work from the notification.
- Deleting a list keeps its tasks, without a list.

## Calendar events

An event's fields are `title`, `notes`, `location`, `startAt` and `endAt` (milliseconds; for an all-day event `endAt` is the start of its last day), `allDay`, `recurrence` (frequency, interval, last day), `alert` (minutes before the start), `source` (like a task's), `uid` (of an imported calendar entry) and `createdAt`.

- The calendar shows events together with tasks that have a due date and open reminders. Repeating events are expanded on the device; a monthly event on the 31st skips months without that day.
- "Add to Calendar" on a message looks for the first date in its text on the device (`NSDataDetector`). Nothing leaves the device for this.
- Each device schedules alerts only for the next occurrence of each event and only for the 24 soonest events, because the system limits pending notifications.
- `.ics` export writes times in UTC and all-day events as dates. Import reads `VEVENT` entries with `DTSTART`/`DTEND` or `DURATION` (UTC, `TZID` or floating), `SUMMARY`, `DESCRIPTION`, `LOCATION`, `RRULE` (`FREQ`, `INTERVAL`, `UNTIL`, `COUNT`), `UID` and the earliest `VALARM` trigger. Importing an entry with a known `UID` updates the event instead of adding a copy.
- "Send to Chat" sends an event as an `.ics` file through the normal attachment screen. People on other Signal apps receive a normal file.
- Deleting or losing the source message removes the event's `source`, like a task's.

## Apple Calendar and Reminders

Settings > Folders, Tasks, Calendar and Sync > Apple Calendar and Reminders turns sync on for this device: "Copy from Ivy" or "Sync Both Ways", separately for events and tasks. Before the first sync, Ivy says that items in Apple's apps leave Signal's end-to-end encryption and asks the system for full access.

- Events go to a calendar named Ivy and tasks to a reminders list named Ivy, in the account of the default calendar or list. If the calendar or list is deleted in Apple, the next sync creates it again and copies everything.
- Synced: an event's title, notes, location, start, end, all-day and repeat rule (daily, weekly, monthly or yearly with an interval and an end date); a task's title, notes, due date, all-day, priority and done. Alerts, subtasks, lists and linked messages stay in Ivy, so nothing rings twice.
- Each device stores, per item, the Apple identifier and what both sides looked like at the last sync. That tells which side changed: "Copy from Ivy" puts back what changed in Apple; "Sync Both Ways" takes changes, new and deleted items from Apple, and Ivy's version wins when both sides changed.
- Changes Ivy takes from Apple are written to the Ivy data store and sync to the other devices like any edit.
- Turning sync off forgets the links and leaves the calendar and list in Apple.

## Widgets and the menu bar

Widgets and the Mac menu bar extra don't open the database. The app writes a small summary, `IvyGlance.json`, to its app group container whenever tasks, events, reminders or the unread count change: today's events, due tasks and reminders, up to 8 open tasks, the number of open tasks and the unread count. It contains titles (of events, tasks and, for reminders, chats) and times, no message text. The file is readable after the device was unlocked once since starting, so Lock Screen widgets work. Widgets and menu items open Ivy with `sgnl://ivy/...` links (`home`, `chats`, `calendar`, `calls`, `tasks`, `tasks/new`, `calendar/new`, `task?id=`, `event?id=`).

## Starred messages and chat notes

A star (kind `star`) holds the message reference, up to 500 characters of the message's text and when it was starred. Its id comes from the message, so starring the same message on two devices keeps one star. When the message is deleted on this device, disappears, or is deleted for everyone, the star is removed.

A chat note (kind `chatNote`) holds one text per chat, up to 10,000 characters; its id is the chat. Clearing the text removes the note.

Voice message transcripts are never stored or synced. Ivy transcribes on the device with Apple's speech recognition (`requiresOnDeviceRecognition`) and keeps the text only while the app runs.

## Scheduled messages

A scheduled message (kind `scheduled`) holds the chat, the message body with its mentions and styles (`MessageBody`, archived, base64), its text for lists, the send time, the device that wrote it, `createdAt`, `state` (`pending` or `sent`), `sentAt`, and `claimedBy`/`claimedAt` when another device took over.

- The device that wrote the message, or last changed its time, sends it at the send time.
- If that device hasn't sent it 10 minutes after the send time, another Ivy device takes over: it records itself in `claimedBy`, waits 30 seconds for a takeover by another device to arrive, and sends if it still holds the claim. A claim that hasn't led to a sent message after 5 minutes can be taken over again.
- The sending device marks the message `sent` before handing it to Signal's send queue, which retries until it goes out. Sent entries are removed after 7 days.
- An iPhone only sends while Ivy runs; a message may go out late when no Ivy device is running at the time.
- Only text is scheduled; attachments are not.

## Hidden chats

A hidden chat (kind `hiddenChat`) is the chat's reference and when it was hidden; its id is the chat. Hidden chats sync to all Ivy devices. Whether they are shown right now is not stored or synced: each device shows them only after Face ID, Touch ID or the device passcode, until Ivy leaves the screen or locks.

The Ivy passcode is not Ivy data: it stays on each device as a salted PBKDF2 hash in the local key-value store (collection `IvyPasscode`) and never syncs. The duress passcode is stored the same way, with its own salt. The decoy mode's chats are never stored.

## Snoozed chats

A snoozed chat (kind `snooze`) is the chat's reference with the time it comes back (`until`, milliseconds since 1970); its id is the chat. Snoozes sync to all Ivy devices. When the time comes, whichever device is running marks the chat unread and deletes the snooze.

Questions put aside on Home's Waiting on You are not Ivy data: they stay on the device in the local key-value store (collection `IvyWaitingDismissed`).

## Folder notification hours

A folder entity (kind `folder`) can have `hours`: the weekdays (1 is Sunday) and the start and end in minutes after midnight when the folder's chats may notify. It syncs with the folder's emoji and color. A chat notifies when it is in no folder with hours, or when one of its folders allows it now.

Which folders the current Apple Focus lets notify, and the time of the muted chats summary, are not Ivy data: they stay on the device.

## Snippets

A snippet (kind `snippet`) has a `trigger` (lowercase letters and digits, typed after a semicolon) and a `text` of up to 2000 characters. Snippets sync to all Ivy devices.

Drafts are not Ivy data: Home lists the drafts the chats keep themselves.
