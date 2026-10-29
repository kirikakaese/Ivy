# Ivy Push

Signal's servers send push notifications only to the official Signal app. Without them, iOS wakes Ivy only now and then (Background App Refresh), so notifications can be late, and never come while Ivy is swiped away.

Ivy Push fixes that with a small relay on a server. One relay serves every Ivy user: TestFlight builds connect to the relay built into them by themselves, and anyone can turn that off (Settings > Notifications > Push Relay > Instant Notifications) or enter a relay of their own.

1. Ivy adds a linked device called **Ivy Push** to your account. Its keys are made for it and thrown away, so it can't read your messages.
2. [MollySocket](https://github.com/mollyim/mollysocket) on your server stays connected to Signal as that device. When an urgent message arrives (not read receipts or typing), it calls the Ivy gateway next to it. Ivy's small patch (`relay/mollysocket`) skips what the account's own devices send each other, for example when you read a chat or send a message on the Mac, so the phone isn't woken for something it already knows.
3. The gateway sends Ivy a push through Apple, with no content.
4. Ivy's notification service wakes up, fetches the messages and shows them as usual.

The relay learns when you get messages, never what they say or who sent them. It keeps the password of the Ivy Push device, which can receive encrypted messages but not decrypt or send them. Removing the device (in Ivy or under Linked Devices) cuts the relay off.

If the relay is down, Ivy falls back to Background App Refresh.

Whoever runs the relay learns when its users get messages. Tell the people who use your builds that it's on by default and where to turn it off.

## What you need

- A small server that is always on, with Docker. The smallest VPS plan of most providers is plenty (1 CPU, 1 GB of memory, a few euros a month).
- Two names pointing at it, for example `relay.example.com` for the relay and `status.example.com` for the Ivy Status page (an A record each with the server's IPv4 address, and an AAAA record each if it has IPv6). The relay gets HTTPS certificates from Let's Encrypt by itself.
- An Apple push key (below).

## 1. Apple push key

1. On [developer.apple.com](https://developer.apple.com/account) > Certificates, Identifiers & Profiles > **Keys**, click **+**.
2. Name it `Ivy Push` and tick **Apple Push Notifications service (APNs)**. If Apple asks for an environment, choose **Sandbox & Production**. Then **Continue** and **Register**.
3. **Download** the `.p8` file (only possible once) and note the **Key ID**.

The TestFlight workflow turns on Push Notifications for the App ID `io.github.kirikakaese.ivy` by itself. Builds from before Ivy Push can't receive pushes; install a new TestFlight build first.

## 2. The server

Most providers let you add an SSH key when you create the server; do that. Otherwise copy it over once from your computer: `ssh-copy-id root@<server IP>`.

Log in to the server (`ssh root@<server IP>`), harden it and install Docker:

```sh
curl -fsSLO https://raw.githubusercontent.com/kirikakaese/Ivy/main/relay/harden.sh
less harden.sh   # read what it does first
bash harden.sh
curl -fsSL https://get.docker.com | sh
```

`harden.sh` (Debian or Ubuntu) turns on automatic security updates (with a restart at 04:00 when one needs it), a firewall that only lets in SSH, HTTP and HTTPS, key-only SSH logins, fail2ban against password guessing, and safer kernel network settings. It leaves password logins on while no SSH key is set up, so you can't lock yourself out; run it again after adding a key.

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
| `IVY_RELAY_DOMAIN` | the relay's name, for example `relay.example.com` |
| `IVY_STATUS_DOMAIN` | the status page's name, for example `status.example.com` |
| `APNS_TEAM_ID` | developer.apple.com > Membership details > Team ID |
| `APNS_KEY_ID` | the Key ID from step 1 |
| `IVY_ADMIN_PASSWORD` | a password for the status page, for example from `openssl rand -base64 24`. Leave it empty to turn the page off. |
| `IVY_ALLOWED_ACCOUNTS` | optional: only these accounts may use the relay, for example `["account ID"]`. Ivy shows the ID under Settings > Notifications > Push Relay. Leave it out to serve every Ivy account. |

Start it:

```sh
docker compose up -d --build
docker compose logs -f
```

The first start builds the gateway and fetches a certificate, which takes a minute or two. Opening `https://relay.example.com/discover` in a browser should show a short text starting with `{"mollysocket"`.

Ports 80 and 443 must be reachable; `harden.sh` opens them. If your provider has its own firewall in its web console, allow them there too.

The containers run with no extra privileges, memory limits and rotated logs; the gateway's file system is read-only. From outside, only MollySocket's registration, the status pages and HTTPS are reachable.

## 3. Build it into Ivy

1. In GitHub > the Ivy repository > Settings > Secrets and variables > Actions > **Variables**, add a repository variable `IVY_PUSH_RELAY_HOST` with your domain, for example `relay.example.com` (no `https://`).
2. Run the TestFlight workflow.

On the new build, Ivy connects by itself the next time it opens, on the phone each account was registered on. Settings > Notifications > **Push Relay** then shows "Connected", and Settings > Linked Devices shows **Ivy Push**. Send yourself a message from another device while Ivy is closed to check.

Without the variable, builds have no built-in relay; users can still tap **Connect Relay** there and enter a relay's address.

## Turning it off

In Ivy: Settings > Notifications > Push Relay > **Instant Notifications** off. Ivy removes the Ivy Push device and doesn't connect by itself again. **Use Another Relay** connects to a different relay instead.

## Ivy Status page

`https://status.example.com` is Ivy's public status page; the relay's own address and its old `/status` path forward there. Anyone can open it; Ivy links to it under Settings > Notifications > Push Relay > Service Status. It shows:

- **Overall status**: All good, Maintenance, Some trouble or Something isn't working.
- **Services**, each with its own state:
  - *Ivy Push relay*: MollySocket answers and stays connected to Signal (many reconnections in ten minutes count as trouble).
  - *Apple push delivery*: Apple accepts wake-ups (a rejection within the last hour counts as trouble, mostly rejections as down).
  - *Signal service*: the relay checks once a minute whether Signal's chat server answers and how fast. A server error or an answer slower than 3 seconds counts as trouble, three missed checks in a row as down. Signal's server uses a certificate only Signal's apps trust; the check accepts that, since it only looks whether the server answers and sends nothing.
- **Measurements**: uptime over 30 and 90 days (per minute), wake-up time (median time for Apple to accept a wake-up, last 24 hours, from 10 wake-ups), share accepted by Apple (last 24 hours, from 50 wake-ups).
- **Incidents, maintenance and notices** posted on the admin page, with their updates; resolved ones stay listed for 14 days.
- A bar for each of the last 90 days.

It tells nothing about who uses the relay, how many or when. The relay checks itself once a minute; visitors never cause checks.

### In Ivy

While Ivy is open on a device that uses the relay, it reads the status data from the relay (`https://<relay>/status/status.json`) when it comes to the front and every 5 minutes. When something is wrong, a banner at the top of the chat list says what, and the profile picture on every tab gets a yellow badge:

- an open incident, with its title and latest update, then a problem the relay found by itself, then maintenance; a notice shows in the chat list only, without the badge;
- *Can't reach Ivy Push* when the relay didn't answer twice in a row while the device was online.

The banner opens the status page; its arrow collapses it to the title until the next, different problem.

Signal's own status page (status.signal.org) offers no data to read, so the relay checks `https://chat.signal.org/` itself. To check a different address, set `SIGNAL_CHECK_URL` for the `ivy-gateway` service; `off` leaves Signal out.

## Admin page

`https://status.example.com/admin` (user `admin`, password `IVY_ADMIN_PASSWORD`) shows whether the relay works and runs the status page:

- **Status**: Operational, Maintenance, Degraded or Down, with what needs attention.
- **Status page**: for each service what the checks found and what the public page shows.
- **New post**:
  - *Incident*: a title, the affected services and minor (some trouble) or major (down) impact. Add updates as it goes: investigating, identified, monitoring, resolved.
  - *Maintenance*: a start and an end; the affected services show "Maintenance" in between. Upcoming maintenance is listed on the public page.
  - *Notice*: a message without effect on the services, for example about a new build.
- **Posts**: add updates, close or delete them. Changes show on the public page right away.
- **Overview**: connected accounts, devices woken in the last day and week, wake-ups and failures in the last 24 hours.
- **Wake-ups per hour** for the last 24 hours.
- **Apple push**: last delivery, last rejection with Apple's reason, totals.
- **Relay**: MollySocket's version and counters, removed devices, how long the gateway has been running.
- **Recent wake-ups**: each with time, result and a short device code.

After 10 wrong passwords from one address, the page refuses that address for 15 minutes. Changes are only accepted from the admin page itself, not from other sites.

The page shows no account IDs, phone numbers or push tokens; devices appear only as a code derived from their token. It refreshes every 30 seconds. Counts and posts are kept in the `gateway-data` volume, so they survive restarts.

## Updates and maintenance

The server folder holds downloaded copies of the relay files, not a clone of the repository, and Docker keeps the gateway's source from GitHub until it's told to fetch it again. To update:

```sh
cd ivy-relay
for f in docker-compose.yml Caddyfile; do
  curl -fsSLO "https://raw.githubusercontent.com/kirikakaese/Ivy/main/relay/$f"
done
docker compose build --no-cache ivy-gateway
docker compose pull && docker compose up -d
docker compose restart caddy
```

- `restart caddy` loads a changed Caddyfile; `up -d` alone keeps the old one.
- After a change to `relay/mollysocket`, also run `docker compose build --no-cache mollysocket` before `up -d` (about 10 minutes).

- MollySocket is built on the server from the upstream version pinned in `relay/mollysocket/Dockerfile`, plus Ivy's patch. The first build takes about 10 minutes. To move to a newer MollySocket, change `MOLLYSOCKET_COMMIT` there and check that the patch still applies (CI builds it).
- Signal removes linked devices that don't connect for 45 days, so keep the relay running. If the device was removed, Ivy shows "Device removed" under Push Relay; tap **Connect Again**.
- To shut the relay down: remove the `IVY_PUSH_RELAY_HOST` variable, run the TestFlight workflow, then `docker compose down -v` on the server. Ivy falls back to Background App Refresh; the Ivy Push devices stay linked until users turn the switch off or Signal removes them after 45 days.

## Troubleshooting

| Ivy says | Check |
|---|---|
| No relay answered | The domain points at the server, ports 80 and 443 are open, `docker compose ps` shows all three services running |
| Doesn't accept this account | `IVY_ALLOWED_ACCOUNTS` in `.env` contains the ID shown in Ivy, or remove it; after changing `.env`, run `docker compose up -d` |
| Most linked devices allowed | Signal allows 5 linked devices; remove one under Linked Devices |
| Connected, but no notifications | `docker compose logs ivy-gateway`: "InvalidProviderToken" means `APNS_TEAM_ID`, `APNS_KEY_ID` or `apns.p8` don't match; "BadDeviceToken" usually means a build without push, install the latest TestFlight build and connect again |
