# 🪺 nestlab

> A homelab that started life as a humble TRaSH-guides *arr setup and, through the time-honoured process of "oh, I could also run *that* here," mutated into the Docker Compose menagerie you see before you.

This repo is the source of truth for a self-hosted stack running on **Unraid**: media automation, playback, home automation, an MQTT nervous system, and a time-series database quietly hoarding sensor data — all sitting behind a single Traefik reverse proxy with automatic TLS.

---

## 📖 The origin story

It began, as these things so often do, innocently.

**Chapter 1 — "I just want my media organised."** One evening I sat down with the [TRaSH guides](https://trash-guides.info/), a spare Unraid box, and every intention of *only* setting up Radarr, Sonarr and a download client. Quality profiles. Custom formats. A tidy little `/data` folder with hardlinks done properly. It was going to be simple.

**Chapter 2 — "While I'm in here…"** Of course it wasn't simple. Prowlarr joined to wrangle indexers. Bazarr turned up for subtitles. Then HD and UHD wanted their own Radarr/Sonarr instances, because *obviously*. Jellyfin arrived so the whole thing had somewhere to actually watch things. Seerr showed up so people could stop asking me to add stuff manually.

**Chapter 3 — "This is a homelab now."** Once the media side was humming, the scope crept sideways. Home Assistant moved in, dragging Zigbee2MQTT, AppDaemon and a Mosquitto broker along with it. A weather station started shouting readings over MQTT. TimescaleDB + Telegraf appeared to catch all that telemetry and keep it forever. Traefik took over the front door so everything got a proper hostname and a real certificate.

**Chapter 4 — "I should probably write this down."** Which is why you're reading this. What was once a single `docker-compose.yml` is now a fleet of tidy, single-purpose stacks with a consistent naming scheme and every knob pulled out into a `.env` file. Future me will be *so* grateful.

---

## 🧱 What's in the box

Each stack is a self-contained `docker-compose.yml` under [`stacks/`](stacks/), deployed independently.

| Stack | Services | What it does |
|-------|----------|--------------|
| **proxy** | Traefik, whoami | Reverse proxy + automatic Let's Encrypt TLS; the front door for everything |
| **arr** | Radarr (HD + UHD), Sonarr (HD + UHD), Bazarr, Prowlarr, Seerr | The *arr suite — finds, grabs, renames and subtitles all the things |
| **downloaders** | SABnzbd, qBittorrent | Usenet + torrent clients feeding the *arrs |
| **media** | Jellyfin | Playback, with hardware transcoding via `/dev/dri` |
| **ha** | Home Assistant, AppDaemon, ecowitt2mqtt, Zigbee2MQTT | Home automation brain + Zigbee bridge + weather station ingest |
| **mqtt** | Mosquitto | The MQTT broker every smart-home thing gossips through |
| **sql** | TimescaleDB, Telegraf | Time-series metrics — Telegraf sips MQTT, TimescaleDB stores it *(🚧 work in progress)* |

---

## 🕸️ Networking

Everything hangs off a consistent `nestlab-*` network naming scheme. Networks come in three flavours:

**External bridges** — created on the Docker host *before* deploying, then referenced by the stacks:

| Network | Subnet | Purpose |
|---------|--------|---------|
| `nestlab-proxy` | `172.67.0.0/24` | Traefik ↔ services ingress |
| `nestlab-download` | `172.65.0.0/24` | *arrs ↔ download clients |
| `nestlab-mqtt` | `172.19.0.0/16` | MQTT bus (broker, HA, Telegraf) |
| `nestlab-sys` | `172.63.0.0/24` | Infra / system |
| `nestlab-sql` | `172.22.0.0/16` | Database access |

**External macvlans** — real IPs on the LAN via tagged VLAN parents, for things that need to look like first-class citizens on the network:

| Network | Parent | Subnet |
|---------|--------|--------|
| `nestlab-lan` | `br0.10` | `192.168.10.0/24` |
| `nestlab-srv` | `br0.20` | `192.168.20.0/24` |
| `nestlab-iot` | `br0.30` | `192.168.30.0/24` |

**Local bridge** — created automatically by Compose, no host setup needed:

- `nestlab-ha` — an internal-only network for Home Assistant's private chatter.

Because the external networks live *outside* Compose, they have to exist before anything comes up — create them once on the host with `docker network create` (bridges for proxy/download/mqtt/sys/sql, macvlan for lan/srv/iot) using the subnets/parents from `.env`.

> ⚠️ macvlan parent gotcha: the parent is the interface that actually carries the VLAN. `sbh-home` (VLAN 10) is **untagged on `br0`**, so `nestlab-lan` uses `parent=br0` — *not* `br0.10`. The tagged VLANs (`services`=20, `iot`=30) use `br0.20` / `br0.30`.

---

## ⚙️ The `.env` philosophy

There is **one** place hardcoded values are allowed to live, and it is `.env`. Network names, subnets, gateways, macvlan parents, static IPs, MACs, container UIDs, paths, secrets — all of it. The compose files are pure structure; the `.env` is all the specifics.

[`stacks/.env.template`](stacks/.env.template) is the committed, secret-free blueprint. Copy it to `.env`, fill in the blanks, and you're off. The real `.env` is **git-ignored** and never leaves the host — so keep your own backup of it somewhere safe.

Broad strokes of what lives in there:

- **Host basics** — `PUID`, `PGID`, `TZ`, `UMASK`, `DATA_ROOT`, `APPDATA_ROOT`, `SCRATCH_ROOT`
- **Public face** — `ROOT_URL`, `EMAIL` (for Let's Encrypt)
- **Secrets** — `HA_TOKEN`, `MQTT_*`, `POSTGRES_*`
- **Network names** — `NET_PROXY`, `NET_DOWNLOAD`, `NET_MQTT`, …
- **Host network defs** — every subnet / gateway / macvlan parent (used by `docker network create`, not read by Compose)
- **Static addressing** — per-container IPs and MACs (`TRAEFIK_LAN_IP`, `HOMEASSISTANT_IOT_MAC`, …)
- **Hardware** — `ZIGBEE_DEVICE` (the Sonoff dongle's serial path)

---

## 🚀 Getting it running

```bash
# 1. Clone onto a PERSISTENT Unraid path — /root is RAM and vanishes on reboot!
cd /mnt/user/appdata
git clone <this-repo> nestlab
cd nestlab/stacks

# 2. Create your .env from the template and fill it in
cp .env.template .env
nano .env

# 3. Create the external networks (bridges + macvlans) on the host — once.
#    e.g. docker network create -d bridge  --subnet "$PROXY_SUBNET" --gateway "$PROXY_GATEWAY" nestlab-proxy
#         docker network create -d macvlan -o parent=br0 --subnet 192.168.10.0/24 --gateway 192.168.10.1 nestlab-lan
#    (repeat for the rest — see the "Networking" table for subnets/parents)

# 4. Bring the stacks up
for f in compose-*.yml; do docker compose -f "$f" up -d; done
```

Updating later is just `git pull` and re-running the `up -d` loop — Compose only recreates containers whose config actually changed.

> Deploying via **Portainer** instead of the CLI? Point it at each `compose-*.yml`, supply the same `.env`, and make sure the external networks already exist first — Portainer won't create them for you either.

---

## 🗂️ Repo layout

```
nestlab/
├── README.md
├── LICENSE
└── stacks/
    ├── .env.template           # blueprint (committed, no secrets)
    ├── .env                    # real values (git-ignored)
    ├── compose-proxy.yml       # Traefik + whoami
    ├── compose-arr.yml         # Radarr / Sonarr / Bazarr / Prowlarr / Seerr
    ├── compose-downloaders.yml # SABnzbd / qBittorrent
    ├── compose-media.yml       # Jellyfin
    ├── compose-ha.yml          # Home Assistant & friends
    ├── compose-mqtt.yml        # Mosquitto
    └── compose-sql.yml         # TimescaleDB + Telegraf
```

---

## 🧠 Hard-won lessons (a.k.a. gotchas)

- **External networks must exist first.** Compose references them but won't create them. Forget this and you get `network nestlab-x declared as external, but could not be found`.
- **Unraid runs from RAM.** Anything you want to survive a reboot must live on a real share (`/mnt/user/...` or `/boot`), not `/root` or `/tmp`.
- **macvlan has a catch.** Containers on a macvlan network can't talk to the Unraid host directly (and vice-versa) — that's macvlan being macvlan, not a bug. Plan host↔container comms over a bridge network.
- **Recreate, don't restart, after network changes.** If a network gets deleted and remade, a plain `docker restart` won't reattach the container — you need a full `up -d` recreate.
- **Two things never touch git:** `.env` and one shy little stack. Back them up yourself.

---

## 🚧 Status & roadmap

Most of the fleet is stable and doing its job. The **sql** stack is the exception — it's still a work in progress. TimescaleDB and Telegraf are up and capturing MQTT, but the plan is to grow it into a proper telemetry pipeline: ingesting and processing **weather** data (and whatever else the sensors throw at it), running continuous aggregates, and eventually surfacing it all somewhere nice. Consider it the "phase 5" that this project's origin story practically guarantees.

---

## 📜 Naming convention

Keep it boring and consistent so future-you doesn't have to think:

- **Networks:** `nestlab-<role>` (`nestlab-proxy`, `nestlab-mqtt`, …)
- **Stacks:** `compose-<domain>.yml` (`compose-arr.yml`, `compose-ha.yml`, …)
- **Env vars:** `UPPER_SNAKE_CASE`, grouped by purpose with comment headers

---

*Built one "wouldn't it be cool if…" at a time. 🪺*
