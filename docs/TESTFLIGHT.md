# TestFlight

The **TestFlight** workflow builds the iOS app (iPhone and iPad), signs it with the Ivy team's certificates and uploads it to App Store Connect. Run it by hand: Actions > TestFlight > Run workflow, on `main`.

The workflow creates the App IDs of the extensions, a distribution certificate and the provisioning profiles itself, through the App Store Connect API (`Scripts/ivy/asc-signing.rb`). Nothing has to be signed on a Mac.

## One-time setup

1. **Team ID.** On [developer.apple.com](https://developer.apple.com/account) > Membership details, copy the Team ID (10 characters).
2. **API key.** In [App Store Connect](https://appstoreconnect.apple.com) > Users and Access > Integrations > App Store Connect API > Team Keys, generate a key with the **Admin** role (it creates certificates, App IDs and profiles). Download the `.p8` file; it can only be downloaded once. Note the Key ID and the Issuer ID shown above the list.
3. **App ID.** On developer.apple.com > Certificates, Identifiers & Profiles > Identifiers, add an App ID (App, explicit) with the bundle ID `io.github.kirikakaese.ivy`.
4. **App record.** In App Store Connect > Apps > + > New App: platform iOS, a name (it must be unique on the App Store, for example "Ivy Messenger"), primary language, the bundle ID from step 3, and any SKU (for example `ivy`).
5. **Repository secrets.** In GitHub > Settings > Secrets and variables > Actions, add:
   - `APPLE_TEAM_ID`: the Team ID
   - `ASC_KEY_ID`: the Key ID
   - `ASC_ISSUER_ID`: the Issuer ID
   - `ASC_KEY`: the whole text of the `.p8` file, including the BEGIN and END lines
6. **App Group.** The app and its extensions share their data through the App Group `group.io.github.kirikakaese.ivy.group`. Apple's API can't assign App Groups, so this is done on the website once:
   - Identifiers > + > App Groups: description `Ivy`, identifier `group.io.github.kirikakaese.ivy.group`.
   - The first workflow run creates the extensions' App IDs (`.SignalNSE`, `.shareextension`, `.widgets`) and stops with a list of the App IDs that still lack the group. For each of them (and the app's own App ID): open it under Identifiers, tick **App Groups** if it isn't, click **Configure**, tick the group, **Continue**, **Save**.
   - Run the workflow again.

Each run creates its own distribution certificate and App Store profiles and removes them at the end, so they never pile up. Builds already uploaded stay valid.

## Each build

1. Run the workflow. A build takes about an hour.
2. Apple processes the upload, usually within 30 minutes; App Store Connect sends an email when it's done.
3. In App Store Connect > TestFlight, add yourself under Internal Testing once. New builds then reach the TestFlight app on your devices without review.

## Version numbers

The app's version stays the upstream Signal release (8.32), because Ivy reports it to Signal's servers. The build number is the upstream build number followed by the workflow's run number (`1910.57`), so every upload has a new one. Signal's servers only see `1910`. See `Config/Ivy.xcconfig`.

## What differs from the Mac beta

- The iOS build uses `*-AppStore.entitlements`: data protection, the App Group and the keychain group. Ivy doesn't use Apple push, so the push, VoIP and notification filtering entitlements that Apple grants to Signal are left out. On iPhone, messages arrive while Ivy is open and through Background App Refresh.
- The encryption question is answered in `Info.plist` (`ITSAppUsesNonExemptEncryption`), as upstream does.
