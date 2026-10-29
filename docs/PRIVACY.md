# Ivy Privacy Policy

Last updated: 29 October 2026

Ivy is an open-source messenger for iPhone, iPad and Mac that works with the Signal network. Its source code is public at https://github.com/kirikakaese/Ivy. Ivy is not made by Signal and not affiliated with Signal Messenger LLC.

This policy explains which data Ivy handles, where it goes and how long it is kept.

## Who is responsible

Ivy is maintained by kiri. For questions about privacy, open an issue at https://github.com/kirikakaese/Ivy/issues or use the feedback address shown in TestFlight.

## Messages and calls: the Signal service

Ivy connects to Signal's servers in the same way as the official Signal app. Your messages and calls are end-to-end encrypted: only you and the people you talk to can read or hear them. Your account, phone number, profile and contacts are handled by the Signal service under Signal's own privacy policy: https://signal.org/legal/

Ivy itself has no servers that receive your messages, contacts or profile.

## On your devices

- Your messages, contacts and settings are stored on your devices, encrypted.
- Ivy's own data, such as tasks, calendar entries, reminders and folder colors, is stored encrypted on your devices and synced only between your own devices, end-to-end encrypted.
- Voice messages are transcribed on the device.
- If you turn on sync with Apple Calendar or Apple Reminders on a device, the synced events and tasks are also stored by Apple, under Apple's privacy policy.
- Ivy contains no analytics, no advertising and no crash reporting. Debug logs stay on your device unless you export and share them yourself.

## Instant notifications: the Ivy Push relay

Signal's servers only send push notifications to the official Signal app. So that Ivy can notify you right away, Ivy uses a push relay run by the maintainer (push.useivy.app). It is on by default and can be turned off at any time in Ivy: Settings > Notifications > Push Relay > Instant Notifications.

How it works: Ivy adds a linked device called "Ivy Push" to your Signal account. This device has no keys and cannot decrypt anything. The relay stays connected to the Signal service as this device and, when encrypted data arrives for you, asks Apple to wake Ivy on your iPhone or iPad. Ivy then fetches and decrypts your messages on the device.

The relay stores:

- your account ID (a random identifier of your Signal account, not your phone number), the Ivy Push device's number and its password, so it can stay connected;
- your device's Apple push token, so it can wake Ivy;
- for operating the service: when wake-ups were sent and whether Apple accepted them, with devices shown only as a short code derived from the push token. Hourly counts are kept for 7 days, the last 100 wake-ups and the daily service history for up to 90 days;
- technical server logs (for example connection events with your account ID), which are rotated and only kept for a short time.

The relay never sees what your messages say, who sent them or who you talk to. It learns when encrypted data arrives for your account. It doesn't receive your phone number, contacts or profile.

When you turn instant notifications off, Ivy removes the Ivy Push device from your account; the relay can no longer connect, and its stored entry for you is no longer used. The relay runs on a server at Hetzner Online GmbH in Finland (EU). Wake-ups are delivered by Apple Push Notification service under Apple's privacy policy.

The public status page (status.useivy.app) shows whether the service works. It contains no information about users.

## Apple

Ivy is distributed through Apple (TestFlight and the App Store). Apple may collect data about app installs and, if you agree, crash reports for developers, under Apple's privacy policy: https://www.apple.com/legal/privacy/

## Your rights

You can turn off instant notifications at any time, which ends the relay's processing for you. You can ask for information about, correction of or deletion of data the relay stores about you through the contact above. Depending on where you live, you may also have the right to complain to a data protection authority.

## Changes

Changes to this policy are published at this address, with a new date at the top. The history of all changes is public in the repository.
