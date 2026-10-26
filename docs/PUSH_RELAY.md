# Ivy Push

Signal's servers send push notifications only to the official Signal app. Without them, iOS wakes Ivy only now and then (Background App Refresh), so notifications can be late, and never come while Ivy is swiped away.

Ivy Push fixes that with a small relay on your own server:

1. Ivy adds a linked device called **Ivy Push** to your account. Its keys are made for it and thrown away, so it can't read your messages.
2. [MollySocket](https://github.com/mollyim/mollysocket) on your server stays connected to Signal as that device. When an urgent message arrives (not read receipts or typing), it calls the Ivy gateway next to it.
3. The gateway sends Ivy a push through Apple, with no content.
4. Ivy's notification service wakes up, fetches the messages and shows them as usual.

The relay learns when you get messages, never what they say or who sent them. It keeps the password of the Ivy Push device, which can receive encrypted messages but not decrypt or send them. Removing the device (in Ivy or under Linked Devices) cuts the relay off.

If the relay is down, Ivy falls back to Background App Refresh.

## What you need

- A small server that is always on, with Docker. The smallest VPS plan of most providers is plenty (1 CPU, 1 GB of memory, a few euros a month).
- A domain or subdomain pointing at it, for example `relay.example.com` (an A record with the server's IP address). The relay gets an HTTPS certificate from Let's Encrypt by itself.
- An Apple push key (below).

## 1. Apple push key

1. On [developer.apple.com](https://developer.apple.com/account) > Certificates, Identifiers & Profiles > **Keys**, click **+**.
2. Name it `Ivy Push` and tick **Apple Push Notifications service (APNs)**. If Apple asks for an environment, choose **Sandbox & Production**. Then **Continue** and **Register**.
3. **Download** the `.p8` file (only possible once) and note the **Key ID**.

The TestFlight workflow turns on Push Notifications for the App ID `io.github.kirikakaese.ivy` by itself. Builds from before Ivy Push can't receive pushes; install a new TestFlight build first.

## 2. The server

Log in to the server (`ssh root@<server IP>`) and install Docker if needed:

```sh
curl -fsSL https://get.docker.com | sh
```

Get the relay files and prepare the settings:

```sh
mkdir ivy-relay && cd ivy-relay
for f in docker-compose.yml Caddyfile env.example; do
  curl -fsSLO "https://raw.githubusercontent.com/kirikakaese/Ivy/main/relay/$f"
done
cp env.example .env
```

Copy the push key from your computer to the server (run this on your computer, with your file name):

```sh
scp ~/Downloads/AuthKey_ABCDE12345.p8 root@<server IP>:ivy-relay/apns.p8
```

Edit `.env` on the server (`nano .env`):

| Setting | Value |
|---|---|
| `IVY_RELAY_DOMAIN` | your domain, for example `relay.example.com` |
| `IVY_ACCOUNT_ID` | in Ivy: Settings > Notifications > Push Relay > Account ID (tap to copy) |
| `APNS_TEAM_ID` | developer.apple.com > Membership details > Team ID |
| `APNS_KEY_ID` | the Key ID from step 1 |

Start it:

```sh
docker compose up -d --build
docker compose logs -f
```

The first start builds the gateway and fetches a certificate, which takes a minute or two. Opening `https://relay.example.com/discover` in a browser should show a short text starting with `{"mollysocket"`.

Ports 80 and 443 must be reachable; with a firewall (for example `ufw`), allow them: `ufw allow 80,443/tcp`.

## 3. Ivy

On the iPhone your account was registered on:

1. Settings > Notifications > **Push Relay** > **Connect Relay**.
2. Enter your domain and tap **Continue**. Allow notifications if asked.

"Connected" means the relay accepted Ivy. Under Settings > Linked Devices you now see **Ivy Push**. Send yourself a message from another device while Ivy is closed to check.

## Updates and maintenance

```sh
cd ivy-relay
docker compose pull && docker compose up -d --build
```

- Signal removes linked devices that don't connect for 45 days, so keep the relay running. If the device was removed, Ivy shows "Device removed" under Push Relay; tap **Connect Again**.
- To stop using Ivy Push, tap **Disconnect** in Ivy, then `docker compose down -v` on the server.

## Troubleshooting

| Ivy says | Check |
|---|---|
| No relay answered | The domain points at the server, ports 80 and 443 are open, `docker compose ps` shows all three services running |
| Doesn't accept this account | `IVY_ACCOUNT_ID` in `.env` matches the ID in Ivy; after changing `.env`, run `docker compose up -d` |
| Most linked devices allowed | Signal allows 5 linked devices; remove one under Linked Devices |
| Connected, but no notifications | `docker compose logs ivy-gateway`: "InvalidProviderToken" means `APNS_TEAM_ID`, `APNS_KEY_ID` or `apns.p8` don't match; "BadDeviceToken" usually means a build without push, install the latest TestFlight build and connect again |
