# Ivy – Design Direction

One direction for the native Mac and iOS apps. Every screen follows it; a screen that needs to break it changes this file first.

## Direction

- **Product.** A private messenger on the Signal network for people who also keep their tasks, dates and reminders next to their chats.
- **Character.** Unhurried, exact, a little grown-in.
- **World.** A gardener's notebook: paper labels, pencil, and one living green. The world shows in the accent and in the moments, never in the window chrome.
- **Moments.** Content carries the richness: photos and media in a chat, your own message bubbles in ivy green, and on the link screen the QR code on its paper card. Each screen has at most one.
- **Signature.** The tendril: a 2 pt ivy-green rule on the leading edge of the thing that is currently yours — the selected chat, the first unread message, a quoted reply. It is used nowhere else.

## Rules for native screens

| Layer | Rule |
|---|---|
| Spacing | 4 pt grid. Steps: 4, 8, 12, 16, 24, 32, 48. Inside a group 8, between groups 24. Window content padding 32 on Mac, 16 on iPhone. Sidebar rows 36 tall on Mac |
| Color | Surfaces, borders and text are the system's semantic colors, so dark mode and Increase Contrast work. One accent, ivy green: `#2E7D4F` light, `#3A9A62` dark, `#1D5C38` / `#5CC08A` with Increase Contrast (the asset `Accent`). Accent marks the primary action, the selection and own bubbles. Red and orange only for errors and warnings. No gradients, glows or colored shadows |
| Icons | SF Symbols only, regular weight, in the color of the text next to them. No emoji as icons |
| Copy | Sentence case. No exclamation marks, no greeting headlines, no trailing period on titles, labels and buttons. Strings come from the translation tables; the app is "Ivy", the network is "Signal" |
| Type | The system font through text styles (`.title2`, `.body`, `.callout`, `.footnote`), never fixed sizes, so text follows the user's size setting. Weights regular and medium; semibold only for a window's one title. Figures and codes use monospaced digits |
| Layout | Mac: sidebar 260–320, content fluid, text columns at most 420 wide. Text aligns to the leading edge; only one- or two-line empty states are centered |
| Details | Radii: controls 8, cards 12, sheets 16. Hairline separators from the system. Counts are quiet monospaced text, not pills |
| Motion | System transitions only, 0.2 s ease-out for our own state changes, none when Reduce Motion is on. Nothing loops except a progress indicator while work is running |
| Accessibility | Every control has a label, every image a description or is hidden. Full keyboard access on Mac: default button on Return, Escape cancels, all actions in the menus. Layouts mirror in right-to-left languages |

The tokens live in `apps/mac/Sources/Design.swift` and are shared with the iOS app.

## Screens

| Screen | Moment | Notes |
|---|---|---|
| Link this Mac | The QR code on a white paper card | Steps on the leading side, code on the trailing side. The card stays white in dark mode so phones can scan it |
| Chat list | None: the list stays quiet, content comes with the chat | Sidebar 260–320. Two lines per chat: name and time, last message and unread count in ivy green as a plain number. The tendril marks the selected chat |
