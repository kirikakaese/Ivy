# Ivy Core

`core/` is a Rust workspace that will own everything that is not screen or OS glue. The apps in `apps/` are UI shells over it through UniFFI bindings. The Swift code in `Signal/`, `SignalServiceKit/` and `SignalUI/` stays the reference and the shipping app until the new apps replace it.

## Layout

| Path | What |
|---|---|
| `core/ivy-core` | The core. Uses the `libsignal-protocol` and `libsignal-net` crates directly, at the tag the Podfile pins |
| `core/uniffi-bindgen` | Generates the Swift bindings |
| `apps/mac` | Native Mac app (SwiftUI). `project.yml` is an XcodeGen project; `Scripts/build-core.sh` builds the core and the bindings |
| `docs/DESIGN.md` | The design direction every screen follows |

The protos (`SignalServiceKit/Protos/Specifications`) and the reported client version (`Config/Ivy.xcconfig`) are read by `core/ivy-core/build.rs`, so they have one source.

## Rust or Swift

Rust unless Apple only offers the API to Swift: views, Keychain, app group paths, and later CallKit, notifications, extension entry points, menus. Swift holds no business logic, persistence or networking. What is Swift today:

| File | Why Swift |
|---|---|
| `Keychain.swift` | The Keychain is an Apple API. It stores and returns bytes; the key itself is made in Rust (`new_key_spec`) |
| `AppModel.swift` | Finds the app group folder, hands the core's state to SwiftUI and picks the translated text for each core error |
| `LinkView.swift`, `IvyApp.swift`, `Design.swift` | Views and design tokens. The QR code's modules are computed in Rust and only drawn here |

## Data

- The core has its own SQLCipher database, `ivy-core/core.sqlite` in the app group folder, with the same parameters as the Swift app's (48-byte raw key spec from the Keychain, 32-byte plaintext header, WAL). Its key is the Keychain item `IvyCoreKeyChainService` / `IvyCoreCipherKeySpec`.
- The Swift app's database (`grdb/signal.sqlite`) is only ever opened read-only (`db::open_legacy`). Existing data will be copied into the core database once, slice by slice; the old file is never changed, so nothing can be lost and the current app keeps working.
- Until that copy exists, the new Mac app does not link when it finds an existing account: it shows what it found and stops, so it cannot end up as a second device beside the data it should take over.
- A read-only connection to a database in WAL mode may create the `-shm` file next to it. It never changes the database or its `-wal` file.

### Checking a real database

Reading the Swift app's key-value store means decoding `NSKeyedArchiver` data. The tests use archives built by hand, so the reader must be confirmed against a real database before any migration relies on it:

```bash
cargo run -p ivy-core --example legacy_check -- /path/to/copy/of/signal.sqlite <key spec as 96 hex digits>
```

It prints whether an account with a valid identity key was found, the device id, and the number of chats and messages. It prints no keys. The new Mac app runs the same check on start.

## Building and testing

```bash
cd core && cargo test
```

Needs `protoc`, `cmake` and a C compiler. On Linux it also needs `libsqlcipher-dev`: Apple builds bundle SQLCipher on CommonCrypto, but elsewhere a bundled SQLCipher would need OpenSSL, whose symbols clash with libsignal's BoringSSL in one binary. Linux is for development and CI only.

`cargo test -- --ignored live` opens a provisioning socket on Signal's production server and expects a link address. It needs a network path that does not intercept TLS, because libsignal pins Signal's certificates.

Mac app, on a Mac with Xcode, XcodeGen and the Rust target `aarch64-apple-darwin`:

```bash
cd apps/mac && xcodegen generate && open IvyMac.xcodeproj
```

## Not as strong as the Swift app yet

| Area | Swift app | Core today |
|---|---|---|
| fsync | `F_BARRIERFSYNC` through Signal's SQLCipher fork | `fullfsync` and `checkpoint_fullfsync` on stock SQLCipher |
| Routes | Direct, censorship circumvention, user proxy | Direct only |
| History on linking | Link and sync | Not offered (the QR code announces no capability) |

## Slices

1. Link as a secondary device — core done, Mac app written but not built or run yet
2. Conversation list
3. Open a chat and read
4. Send text
5. Attachments
6. Groups
7. Calls
8. Settings
9. Backups
10. The rest of `docs/PARITY.md`
11. iOS: iPhone, iPad, notification extension, share extension, widgets
