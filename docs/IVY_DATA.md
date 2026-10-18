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
