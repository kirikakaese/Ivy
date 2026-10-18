# Mac Beta

Until Ivy has an Apple developer certificate (needed for a signed and notarized app, Phase 7), there is a beta for the Mac. Every change merged into `main` builds a new one and publishes it as a pre-release named "Ivy Mac beta" on the [releases page](https://github.com/kirikakaese/Ivy/releases).

The beta is signed ad hoc. It runs in the App Sandbox, so everything it stores is in its own container, `~/Library/Containers/io.github.kirikakaese.ivy`. macOS gives apps signed ad hoc neither an app group container nor the keychain, so the beta differs from the real app:

- Its data is in `Library/Application Support/Ivy Beta` inside the container instead of the app group container.
- Its database keys are in `Library/Application Support/Ivy Beta/Keys` inside the container, readable only by your user account, instead of the keychain. FileVault encrypts them with the rest of your disk.
- It has no share extension and no widgets. The menu bar extra works.
- It is a separate install: the signed app will not take over the beta's data, so you link it again then.

Everything else is the normal Ivy for the Mac. It needs a Mac with Apple Silicon.

## Install

1. Download `Ivy-Mac-Beta.zip` from the newest "Ivy Mac beta" pre-release and open it.
2. Move "Ivy Beta" to your Applications folder.
3. Open it. macOS says it can't check the app for malicious software. Click Done, then open System Settings > Privacy & Security and click "Open Anyway" next to Ivy Beta. Confirm with your password.
4. Ivy shows a QR code. On your phone, open Signal (or Ivy) > Settings > Linked Devices > Link New Device and scan it.

Signal does not support third-party clients. An account used with Ivy can be rate-limited or blocked; a separate test number is the safe choice while Ivy is in development.

## Update

Quit Ivy Beta, replace the app in Applications with the new one, and open it. Your data stays. Each beta has a new signature, so macOS may ask once more to "Open Anyway".

## Messages and notifications

Like the regular Mac app, the beta receives messages while it runs. Settings > Notifications > Open at Login starts it when you log in. macOS may not allow a login item for an app without a certificate; then add Ivy Beta yourself in System Settings > General > Login Items.

## Remove

Unlink the Mac on your phone (Settings > Linked Devices), delete Ivy Beta from Applications, and delete `~/Library/Containers/io.github.kirikakaese.ivy`, which holds all of its data and keys.

The first two betas ran outside the App Sandbox. If you tried them, also delete `~/Library/Application Support/Ivy Beta`, the Ivy log files in `~/Library/Caches/Logs`, and `~/Documents/ProfileAvatars` if it exists.

## Building it yourself

```
make dependencies
Scripts/ivy/mac-beta.sh build/mac-beta
```

The script builds the App Store Release configuration with the compilation condition `IVY_MAC_BETA`, removes the extensions, signs the app ad hoc with the App Sandbox (`Scripts/ivy/IvyMacBeta.entitlements`) and zips it. The code paths that differ are marked `IVY_MAC_BETA` (`SignalServiceKit/Ivy/IvyMacBeta.swift`, `MainAppContext`, `KeychainStorageImpl`, `GRDBSchemaMigrator`).
