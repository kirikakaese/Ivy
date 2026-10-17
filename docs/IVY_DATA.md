# Ivy Data

Data that only Ivy knows about: folder emoji and color, per-folder pins and reminders. Tasks and calendar events (Phase 4) will use the same store.

## Storage

- Database: `ivy-db/ivy.sqlite` in the app group container, next to the upstream `grdb` folder. The folder name must not start with `grdb`, because upstream deletes such folders.
- Encryption: SQLCipher with a 48-byte raw key spec (256-bit key and 128-bit salt), like the upstream database. The key is in the keychain (`IvyDataKeyChainService` / `IvyDataCipherKeySpec`, accessible after first unlock, this device only).
- Reset: "Delete all data" removes the database and its key (`IvyData.deleteAll()`).

## Model

Every entity is a set of fields in the table `IvyDataField`:

| Column | Meaning |
|---|---|
| `kind` | `folder` or `reminder` |
| `entityId` | Folder id (hex) or reminder id (UUID) |
| `field` | Field name, e.g. `color`, `pins`, `dueAt`, `done`; `deleted` marks a deleted entity |
| `value` | JSON value, or NULL when cleared |
| `millis`, `deviceId` | When and on which device the field was last edited |

Edits merge per field: the higher `(millis, deviceId)` wins. Each device's clock never goes backwards and moves past every timestamp it receives, so a later edit wins even when device clocks differ.

Chats and messages are named in a way that is the same on all devices: `a:<ACI>`, `e:<phone number>` or `g:<base64 group id>` for chats, and chat, timestamp and author ACI for messages.

## Sync

- Local edits are collected for two seconds and sent as a sync message to the user's own devices. The payload (`IvySyncPayload`, JSON) is in field 7301 of `SyncMessage`, which official clients do not know and skip ("unsupported sync message").
- Sync messages are end-to-end encrypted like all Signal messages and accepted only from the user's own account.
- A device asks for all data once (`requestSnapshot`); every Ivy device answers with `snapshot`. Settings > Folders, Reminders and Sync > Get Data from Other Devices asks again.
- Large snapshots are split into payloads of about 64 KB.

## Export and import

The file starts with `IVYDATA1`, a 16-byte salt and the PBKDF2 iteration count (4 bytes, big endian), followed by an AES-256-GCM box with the JSON list of all fields. The key is derived from the passphrase with PBKDF2-HMAC-SHA256. An import merges like a sync from another device and sends what changed to the other devices.

## Reminders

Each device schedules a local notification for every open reminder that is still in the future. When a reminder comes due, the chat is marked unread once on each device and shown at the top of the chat list until the reminder is done. Snoozing or finishing a reminder on one device changes `dueAt` or `done`, which syncs, and the other devices update their notifications.
