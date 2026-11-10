# OpenLegacy Hub on Docker

One command installs OpenLegacy Hub, and the OpenLegacy apps you choose, on a single computer with Docker.
You answer four questions; the installer does the rest, in the right order, and tells you where to sign in.

| Always installed | |
|---|---|
| PostgreSQL 17 | one database for everything (one schema per app) |
| Keycloak 26 | sign-in, realm `ol-hub` |
| OpenLegacy Hub 4.0.0 | the Hub and its built-in gateway to the apps |
| HTTPS proxy (Caddy) | gives every component its own `https://` address |

Optional apps: OL Integration, TermIQ, DataIQ (with DataIQ batch), AppIQ, OL Next, OL Spec, OL Code,
OL Terminal, CoreIQ, AtomIQ.

Contents: [Before you start](#before-you-start) · [Install](#install) · [Sign in](#sign-in) ·
[Where each app starts](#where-each-app-starts) · [Everyday use](#everyday-use) ·
[Addresses](#choosing-the-address) · [Certificates](#certificates) · [Settings](#settings-installconf) ·
[How it works](#how-it-works) · [Data and backups](#data-secrets-and-backups) · [Upgrading](#upgrading) ·
[Troubleshooting](#troubleshooting) · [Files](#files)

---

## Before you start

You need:

1. **The master licence from OpenLegacy** — a file ending in `.jwt` (for example `master-license.jwt`).
   **The installation does not start without it.**
2. **Docker**
   - Windows or macOS: install [Docker Desktop](https://www.docker.com/products/docker-desktop/) and start it.
     In Docker Desktop, open *Settings → Resources* and give it at least **8 GB of memory** (16 GB if you install
     several apps).
   - Linux: install [Docker Engine](https://docs.docker.com/engine/install/) with the *docker-compose-plugin*.
   - Docker Compose **2.20 or newer** (any current Docker has it). The installer checks this for you.
3. **Windows only: [Git for Windows](https://git-scm.com/download/win)** (default options). The installer is a
   bash script; Git for Windows brings bash. Linux and macOS already have everything.
4. **Free ports 443 and 80** on this computer. If another program uses them, the installer tells you, and you
   can pick other ports (see [Settings](#settings-installconf)).

Nothing else needs to be installed: everything else runs inside Docker. (`curl`, used to activate the licence,
is part of Windows, macOS and almost every Linux.)

**Computer size.** Before it downloads anything, the installer adds up the memory your chosen apps need and
tells you if Docker has less.

| What you install | Memory for Docker (at least) | Disk |
|---|---|---|
| Hub only | 4 GB | 20 GB |
| Hub + 3 apps | 6 GB | 25 GB |
| Hub + all apps | 12 GB | 40 GB |

The first installation downloads 5–15 GB of images, depending on the apps. No internet on the target computer?
See [Upgrading → Without internet](#upgrading).

## Install

**1. Get the installer** — either way gives you a folder named `ol-hub-docker-installer`:

- with git:

  ```bash
  git clone https://github.com/openlegacy/ol-hub-docker-installer.git
  ```

- or without git: on [github.com/openlegacy/ol-hub-docker-installer](https://github.com/openlegacy/ol-hub-docker-installer)
  click **Code → Download ZIP** and unpack it (the folder is then named `ol-hub-docker-installer-main`).

**2. Copy your licence file into that folder** (the folder that contains `ol-hub-docker.sh`). The installer
then finds it by itself.

**3. Start it:**

- **Windows:** double-click **`ol-hub-docker.cmd`**. A *Git Bash* window opens with the menu.
- **macOS / Linux:** open a terminal in this folder and run:

  ```bash
  ./ol-hub-docker.sh
  ```

  If you see "Permission denied", run `bash ol-hub-docker.sh` instead.

**4. Choose `1) Install OpenLegacy Hub`** — type `1` and press Enter. The menu lists everything you can do; it
changes once the Hub is installed (status, passwords, add apps, stop/start, ...).

```
      ____
     /\   \      OpenLegacy Hub
    /  \___\     Docker installer
    \  /   /     Not installed on this computer yet.
     \/___/

   1) Install OpenLegacy Hub
   2) Load images from a file (computer without internet)
   3) Save the images to a file (for a computer without internet)
   4) Help: every command
   0) Exit

What do you want to do? Type a number:
```

(Every menu choice is also a command you can type, e.g. `./ol-hub-docker.sh install` or
`./ol-hub-docker.sh status` — see `./ol-hub-docker.sh help`. On Windows the same commands work with
`ol-hub-docker.cmd status`, or in Git Bash with `./ol-hub-docker.sh status`.)

The installer asks four questions. Press **Enter** to accept the suggestion in [brackets]:

| Question | What to answer |
|---|---|
| **1. Domain** | `localhost` if only this computer will open the Hub (simplest). The computer's IP address (for example `192.168.1.20`) if other computers should open it too. Or your company domain — see [Choosing the address](#choosing-the-address). |
| **2. Licence file** | Press Enter if the licence file is in this folder; otherwise type its path (or drag the file into the window). The installer checks the file and asks again if it is not a valid master licence. |
| **3. Apps** | A list of every app, one per row; `[x]` means *will be installed*. All apps start marked. Move with the **↑ ↓** arrow keys, press **Space** to mark or unmark the app at the `>`, **A** to mark all, **N** to mark none, and **Enter** when the list is right — exactly the marked apps are installed (see below). You can add or remove apps later. |
| **4. Organization** | Your company name. |

The app list looks like this (here OL Integration, DataIQ, DataIQ batch and CoreIQ are marked):

```
     [x] = will be installed
     ↑ ↓ move    Space mark / unmark    A all    N none    Enter done

       [x] OL Integration
       [ ] TermIQ           needs OL Integration
     > [x] DataIQ           needs OL Integration, DataIQ batch
       [x] DataIQ batch
       [ ] AppIQ            needs OL Integration
       [ ] OL Next
       ...
       [x] CoreIQ
       [ ] AtomIQ
     4 apps will be installed
```

Some apps need others: marking DataIQ also marks OL Integration and DataIQ batch, and unmarking OL Integration
also unmarks the apps that need it. The last line always says how many apps will be installed.

Nothing is saved until all four questions are answered: if you stop half-way (Ctrl+C or closing the window),
the next run asks everything again.

It then shows a plan with two checks: is there enough memory for the chosen apps, and can this computer
reach the image registries. It asks *Start the installation?*. Type `y` and press Enter.

The first installation takes **10–20 minutes**, mostly downloading. You see each step, and a spinner with the
seconds while the installer waits for something:

```
== 1/6 Preparing settings and secrets ==
== 2/6 Images ==
== 3/6 HTTPS proxy and database ==
== 4/6 Keycloak ==
== 5/6 OpenLegacy Hub ==        the Hub starts and activates your licence
== 6/6 Apps ==
== Done ==
```

The licence is activated as soon as the Hub runs, **before** the apps start: if the Hub refuses it, you know
within a few minutes, not at the end.

At the end the installer does three more things:

- **Saves every password in an encrypted file**, `ol-hub-credentials.enc` in this folder. You choose the
  file's password (at least 8 characters, typed twice; nothing shows while you type). Keep that password safe:
  without it the file cannot be opened. Press Enter instead to skip; you can save it later from the menu.
- *Trust the certificate on this computer now?* — so the browser does not warn (Windows then asks you to
  confirm with **Yes**; macOS asks for your password).
- *Open the Hub in your browser now?*

Your answers are saved in `install.conf`, and the licence is kept in this folder as `master-license.jwt`. To
change something later, edit `install.conf` and run `./ol-hub-docker.sh` again.

## Sign in

At the end the installer prints the address, the user and the password:

```
  Open https://ol-hub.localhost and sign in:
      user      ol-hub
      password  ••••••••••••••••••••
```

- Open the address in **Chrome, Edge or Firefox**.
- If you did not let the installer trust the certificate, the browser warns that the connection is not
  private (the certificate was made on this computer). To fix that for good, run once:

  ```bash
  ./ol-hub-docker.sh trust-certificate
  ```

  and restart the browser. This matters most for **OL Terminal** and **OL Code**: the Hub loads them from
  their own addresses, and browsers block that silently while the certificate is not trusted. Without it,
  open `https://ol-terminal.<domain>` and `https://ol-code.<domain>` once and accept the warning there too.
  **Firefox** keeps its own list: import `certs/openlegacy-root-ca.crt` there ([Certificates](#certificates)).
- Forgot a password? Menu → *Passwords and addresses* (or `./ol-hub-docker.sh credentials`):

  ```
  Which credentials do you want to see?
     1) OpenLegacy Hub - sign in here (all apps use this sign-in)
     2) Keycloak admin console (administrators)
     3) CoreIQ admin panel passkey
     4) AtomIQ admin passkey
     5) App API admin accounts (technical)
     6) PostgreSQL database
     7) All of the above
     8) Update the encrypted file (ol-hub-credentials.enc)
     9) Open the encrypted file (ol-hub-credentials.enc)
     0) Back
  ```

**Which password is for what**

| Credential | Used for |
|---|---|
| **Hub user `ol-hub`** | The only browser sign-in you need. Every app in the Hub (TermIQ, DataIQ, OL Code, CoreIQ, ...) uses it. |
| Keycloak admin | Keycloak's admin console: managing users and sign-in settings. |
| CoreIQ admin panel passkey | CoreIQ's admin panel (`https://ol-hub.<domain>/ol-coreiq/admin`): sign in to the Hub first, then enter the passkey. |
| AtomIQ admin passkey | AtomIQ's admin functions. |
| App API admin accounts (OL Code, OL Terminal, CoreIQ) | Technical: each app's own admin API (`/api/v1/admin/...`), not a browser login. Each app has its own account, so each has its own password. |
| PostgreSQL | The database inside Docker (for backups, see [Data and backups](#data-secrets-and-backups)). |

**Open the encrypted passwords file** (`ol-hub-credentials.enc`) — any of these:

- Menu → *Passwords and addresses* → *Open the encrypted file*, then type the file's password.
- `./ol-hub-docker.sh credentials` (Windows: `ol-hub-docker.cmd credentials`) → *Open the encrypted file*.
- Without this folder, on any computer with OpenSSL (Git Bash has it):

  ```bash
  openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -a -in ol-hub-credentials.enc
  ```

  It asks for the file's password and prints the passwords.

## Where each app starts

**Start order.** Everything starts one after the other; each part waits until the one before it answers.
`./ol-hub-docker.sh install` and `start` keep this order. After a restart of the computer, Docker starts the
containers by itself; a part that comes up before the one it needs retries until it answers.

| Order | Starts | Waits for |
|---|---|---|
| 1 | HTTPS proxy, PostgreSQL | – |
| 2 | Keycloak | PostgreSQL |
| 3 | Hub database migration (`ol-hub-migrate`), then the Hub (and the licence is activated) | Keycloak |
| 4 | OL Integration (several apps call it) | the Hub |
| 5 | TermIQ | OL Integration |
| 6 | DataIQ and DataIQ batch, together | TermIQ |
| 7 | AppIQ, then OL Next, OL Spec, OL Code, OL Terminal, CoreIQ, AtomIQ — one after the other | the app before it |
| 8 | The Hub switches every app on | all apps answer |

Only the apps you chose start; the others are skipped.

**Where to open each app.** Sign in to the Hub first; every app uses the same sign-in. Inside the Hub each app
is a page of its own, `https://ol-hub.<domain>/<app>`. Each app also has a short address that leads there.

| App | Inside the Hub | Short address | Notes |
|---|---|---|---|
| OpenLegacy Hub | `https://ol-hub.<domain>` | – | sign in here |
| OL Integration | `https://ol-hub.<domain>/ol-integration` | `https://ol-integration.<domain>` | |
| TermIQ | `https://ol-hub.<domain>/ol-termiq` | `https://ol-termiq.<domain>` | needs OL Integration |
| DataIQ | `https://ol-hub.<domain>/ol-dataiq` | `https://ol-dataiq.<domain>` | needs OL Integration, DataIQ batch |
| DataIQ batch | – | `https://ol-dataiq-batch.<domain>` | DataIQ's "View job" links open it |
| AppIQ | `https://ol-hub.<domain>/ol-appiq` | `https://ol-appiq.<domain>` | needs OL Integration |
| OL Next | `https://ol-hub.<domain>/ol-next` | `https://ol-next.<domain>` | |
| OL Spec | `https://ol-hub.<domain>/ol-spec` | `https://ol-spec.<domain>` | |
| OL Code | `https://ol-hub.<domain>/ol-code` | `https://ol-code.<domain>` | the short address is OL Code's own page |
| OL Terminal | `https://ol-hub.<domain>/ol-terminal` | `https://ol-terminal.<domain>` | the Hub loads it from its own address |
| CoreIQ | `https://ol-hub.<domain>/ol-coreiq` | `https://ol-coreiq.<domain>` | admin panel: `https://ol-hub.<domain>/ol-coreiq/admin` (CoreIQ passkey) |
| AtomIQ | `https://ol-hub.<domain>/ol-atomiq` | `https://ol-atomiq.<domain>` | |
| Keycloak (administrators) | – | `https://keycloak.<domain>/auth/admin` | |

With `APPS_DOMAIN=localhost`, `<domain>` is `localhost`: the Hub is `https://ol-hub.localhost`, TermIQ is
`https://ol-hub.localhost/ol-termiq`. The installer adds the apps an app needs by itself. An app appears in the
Hub only once it is running and answering.

## Everyday use

The menu (`./ol-hub-docker.sh`, or double-click `ol-hub-docker.cmd` on Windows) has all of these. As commands
(`./ol-hub-docker.sh help` lists every command):

| To... | Run |
|---|---|
| See if everything is running | `./ol-hub-docker.sh status` |
| See the addresses and passwords, or save them in an encrypted file | `./ol-hub-docker.sh credentials` |
| Stop everything (for example before shutting down) | `./ol-hub-docker.sh stop` |
| Start everything again | `./ol-hub-docker.sh start` |
| Restart one part | `./ol-hub-docker.sh restart ol-hub` |
| Watch the logs (Ctrl+C to stop watching) | `./ol-hub-docker.sh logs` or `./ol-hub-docker.sh logs ol-hub` |
| Add apps (the menu shows the apps not installed yet as a list to mark) | `./ol-hub-docker.sh add ol-spec ol-coreiq` |
| Remove an app, its data is kept (the menu shows the installed apps as a list to mark) | `./ol-hub-docker.sh remove ol-coreiq` |
| Remove an app and delete its data | `./ol-hub-docker.sh remove ol-coreiq --purge` |
| Replace the licence | `./ol-hub-docker.sh activate-license /path/to/new-license.jwt` |
| Apply changed settings, upgrade, or repair | `./ol-hub-docker.sh` |
| Trust the certificate on this computer | `./ol-hub-docker.sh trust-certificate` |
| Prepare an install without internet | `./ol-hub-docker.sh save-images` (with internet), then `load-images <file>` (see [Upgrading](#upgrading)) |
| Remove the containers (data is kept) | `./ol-hub-docker.sh uninstall` |
| Delete everything and start over from the beginning (all data, passwords and your answers in `install.conf`; your licence file stays) | menu → *Uninstall and DELETE all data*, or `./ol-hub-docker.sh uninstall --purge` |

Options: `-y` answers yes to every question (for scripts; needs an `install.conf` and the licence file),
`-c <file>` uses another settings file.

Everything starts again by itself after a restart of the computer (or of Docker Desktop). Give it a minute or
two until every app answers (`./ol-hub-docker.sh status`).

## Choosing the address

Every component gets its own address under one domain:

| Component | Address |
|---|---|
| Hub (sign in here) | `https://ol-hub.<domain>` |
| Keycloak | `https://keycloak.<domain>` |
| OL Code | `https://ol-code.<domain>` |
| OL Terminal | `https://ol-terminal.<domain>` |
| DataIQ batch ("View job" links) | `https://ol-dataiq-batch.<domain>` |
| Every other app | `https://<app>.<domain>`, e.g. `https://ol-termiq.<domain>` — leads to its page inside the Hub, `https://ol-hub.<domain>/ol-termiq` |

Choose the domain (`APPS_DOMAIN` in `install.conf`):

| Domain | Who can open it | What you need to do |
|---|---|---|
| `localhost` | this computer only | nothing (use Chrome, Edge or Firefox; Safari does not open `*.localhost`) |
| an IP address, e.g. `192.168.1.20` | every computer that reaches this IP | nothing. The installer turns it into `192.168.1.20.nip.io`, a free public DNS service. The other computers need normal internet DNS; some company networks block it. Then use your own domain. |
| your own domain, e.g. `ol.example.com` | everyone you allow | ask IT for a DNS entry `*.ol.example.com` → this computer's IP. Without DNS, add a line to the *hosts* file of each computer that opens it; the installer prints the exact line (`192.168.1.20 ol-hub.ol.example.com keycloak.ol.example.com ...`) |

To change the domain later: change `APPS_DOMAIN` in `install.conf` and run `./ol-hub-docker.sh` again. The
sign-in settings are updated automatically.

If ports 443/80 are taken, set for example `HTTPS_PORT=8443` and `HTTP_PORT=8080`. The addresses then
include the port: `https://ol-hub.localhost:8443`.

## Certificates

`TLS_MODE` in `install.conf`:

| Value | Certificate | Browser warning |
|---|---|---|
| `selfsigned` (default) | made by the proxy on this computer | until you run `./ol-hub-docker.sh trust-certificate` (or import `certs/openlegacy-root-ca.crt` on each computer that opens the Hub) |
| `custom` | your company's certificate: put the full chain in `certs/tls.crt` and the key in `certs/tls.key`. It must be valid for all five addresses (a wildcard `*.<domain>` is easiest). | none |
| `letsencrypt` | free public certificate from Let's Encrypt. Needs a real domain with public DNS, `ACME_EMAIL`, and ports 80 and 443 of this computer reachable from the internet. | none |

To trust the self-signed certificate on another computer, copy `certs/openlegacy-root-ca.crt` to it and:

- **Windows:** double-click the file → *Install Certificate* → *Current User* → *Place all certificates in the
  following store* → *Trusted Root Certification Authorities* → Finish. Restart the browser.
- **macOS:** double-click the file (opens Keychain Access), then double-click the certificate → *Trust* →
  *Always Trust*.
- **Firefox (any system):** *Settings → Privacy & Security → Certificates → View Certificates → Authorities →
  Import*, tick *Trust this CA to identify websites*.

The certificate authority lives in the `caddy-data` volume and stays the same across restarts and upgrades.

## Settings (`install.conf`)

The installer creates `install.conf` on the first run (template: `install.conf.example`). After a change, run
`./ol-hub-docker.sh`.

| Setting | Default | Meaning |
|---|---|---|
| `APPS_DOMAIN` | `localhost` | the domain of all addresses ([Choosing the address](#choosing-the-address)) |
| `APPS` | asked | the apps, by their script names, space separated. Apps already installed stay installed (use `remove`). |
| `MASTER_LICENSE_FILE` | asked | the master licence (required). The installer keeps a copy in this folder as `master-license.jwt`. |
| `TENANT_ORGANIZATION` | `OpenLegacy` | your organization (tenant name; also in the admin's sign-in token) |
| `TENANT_CONTACT` | `ol-hub` | contact person stored on the tenant |
| `HUB_ADMIN_EMAIL` | `admin@openlegacy.com` | e-mail of the admin user `ol-hub` (set when the user is created) |
| `TENANT_ID` | `4a6bfc5d-3bae-45a3-99b9-d1e255875adb` | keep the default: the built-in tenant whose admin the Hub creates |
| `HTTPS_PORT`, `HTTP_PORT` | `443`, `80` | ports on this computer |
| `TLS_MODE`, `ACME_EMAIL` | `selfsigned` | [Certificates](#certificates) |
| `HUB_HOST`, `KEYCLOAK_HOST`, `OL_CODE_HOST`, `OL_TERMINAL_HOST`, `OL_DATAIQ_BATCH_HOST` | `<name>.<APPS_DOMAIN>` | a different host name for one address |
| `EXTRA_REDIRECT_URIS` | none | more addresses allowed to sign in (Keycloak client `hub-spa`), space separated |
| `DB_HOST` … `DB_PASSWORD` | bundled PostgreSQL | an external PostgreSQL 17: set `DB_HOST` and `DB_PASSWORD` (the user must be able to create schemas; the host must be reachable from Docker) |
| `PULL_IMAGES` | `true` | `false`: use images already on the computer (offline installs, see [Upgrading](#upgrading)) |
| `WAIT_TIMEOUT` | `900` | seconds to wait for each component; raise it on slow computers |
| `IMAGE_*` | `images.conf` | override one image, e.g. to pin a digest |

## How it works

`./ol-hub-docker.sh` runs these steps; each one waits until the previous component answers:

| Step | What happens |
|---|---|
| Checks | Docker running, Compose version, curl; the licence file is a master licence; enough memory for the chosen apps; the image registries are reachable |
| 1. Settings | `secrets.env` is generated once (passwords and encryption keys). `.env` and `generated/hub-apps.env` are written from `install.conf`, `images.conf` and `secrets.env`. |
| 2. Images | `docker compose pull` |
| 3. Proxy, PostgreSQL | the HTTPS proxy starts; PostgreSQL starts and gets the schema `keycloak` |
| 4. Keycloak | imports realm `ol-hub` on its first start (`config/keycloak/realm-ol-hub.json`) |
| 5. Hub | `ol-hub-migrate` runs the Hub's database migration, then the Hub starts. The installer writes the ACTIVE tenant row and, in Keycloak, the admin user `ol-hub` (fixed id `9a780e8b-…`, the admin the Hub and OL Integration create) with its tenant and role. It also adds every address to the `hub-spa` redirect URIs. Then it activates the master licence through the Hub (`PUT /backoffice/api/v1/tenants/<id>/license`, as the Hub's licence screen does). A refused licence stops here, before the apps. |
| 6. Apps | One after the other: OL Integration first, then TermIQ, DataIQ with DataIQ batch, AppIQ and the rest; each one answers before the next starts. Each app is switched on in the Hub (`generated/hub-apps.env`, from `config/hub/apps/<app>.env`) **only once it answers**: a switch without a running app stops the Hub page from loading. |
| End | offers to trust the certificate on this computer and to open the Hub in the browser |

Re-running is always safe: secrets are never overwritten, existing data is kept, and installed apps stay
installed. After the install, plain `docker compose` commands work in this folder too (`docker compose ps`,
`docker compose logs ol-hub`), and `docker compose up -d` starts everything in the same order.

**Inside Docker**

| Service | Container port | Health check | In the Hub gateway | Data volumes |
|---|---|---|---|---|
| `proxy` | 443 (`HTTPS_PORT`), 80 | – | – | `caddy-data`, `caddy-config` |
| `postgres` | 5432 | `pg_isready` | – | `postgres-data` |
| `keycloak` | 8080 (http), 8443 (https) | realm `ol-hub` answers | – | – (in PostgreSQL) |
| `ol-hub` | 8080 (+ 9095–9097) | `/health` | – | – |
| `ol-integration` | 8080, 9095 | `/health` | `/backend`, designer | – |
| `ol-termiq` | 8094 | `/health` | `/remotes/termiq` | – |
| `ol-dataiq` | 9092 | `/health` | `/remotes/dataiq` | `ol-dataiq-data` (encryption key, JDBC drivers) |
| `ol-dataiq-batch` | 8089 | `/actuator/health` | – | – |
| `ol-appiq` | 8095 | `/health` | `/remotes/appiq` | – |
| `ol-next` | 8080 | `/api` | `/remotes/ol-next` | `ol-next-data`, `ol-next-cache` |
| `ol-spec` | 3008 | `/health` | `/remotes/olspec` | `ol-spec-data` (master.key), `ol-spec-cache` |
| `ol-code` | 9091 | `/health` | `/remotes/olcode` | `ol-code-data` (home folder) |
| `ol-terminal` | 9093 | `/health` | – (own address) | `ol-terminal-traffic`, `ol-terminal-data` |
| `ol-coreiq` | 8090 | `/health` | `/remotes/ol-coreiq` | – |
| `ol-atomiq` | 8091 | `/health` | `/remotes/ol-atomiq` | – |

- Containers call each other on these ports (`http://ol-hub:8080`, `https://hub-enterprise-keycloak:8443/auth`).
  They also answer to the names the images expect by default (`hub-enterprise-postgres`,
  `hub-enterprise-keycloak`, `dataiq-service`, `dataiq-batch`, `appiq`, `olspec`, `coreiq`, `atomiq`).
- The public addresses point at the proxy inside Docker too (network aliases), so the apps reach Keycloak and
  the Hub on their public URLs, exactly as the browser does. With `APPS_DOMAIN=localhost` the apps' HTTP client
  treats `*.localhost` as the container itself, so `docker-compose.localhost.yml` (switched on automatically
  through `COMPOSE_FILE` in `.env`) adds hosts-file entries that point those names at this computer, where the
  proxy listens.
- An app's data volumes start empty. A one-shot `<app>-volumes` step makes them writable for the app's user.
- Optional apps are compose profiles (`COMPOSE_PROFILES` in `.env`).
- The installer needs only Docker, bash (3.2 or later, so the bash that ships with macOS works) and curl. It
  generates the secrets and talks to the database and Keycloak inside the containers.

## Data, secrets and backups

- **Data** lives in Docker volumes named `ol-hub_*`: the database (`ol-hub_postgres-data`), the apps' files and
  the proxy's certificates. Stopping, restarting, upgrading and `./ol-hub-docker.sh uninstall` keep them. Only
  `uninstall --purge` (menu: *Uninstall and DELETE all data*) deletes them, together with the passwords and
  `install.conf`, so the next install starts from the beginning. Your licence file is kept.
- **Secrets** (passwords and encryption keys) are in `secrets.env`, generated once and never changed by the
  installer. **Never delete or change the encryption keys:** the data stored with them becomes unreadable.
- **Back up the database, `secrets.env` and `master-license.jwt` together.** The data cannot be read without the
  keys. For example, while everything runs:

  ```bash
  docker compose exec -T postgres pg_dump -U postgres -Fc postgres > backup-$(date +%F).dump
  cp secrets.env install.conf master-license.jwt backup-folder/
  ```

  For a full copy including the app files, stop everything (`./ol-hub-docker.sh stop`) and back up the
  `ol-hub_*` volumes with your usual Docker volume backup tool.
- To change the admin password: change it in the Hub/Keycloak as usual. The installer never resets an existing
  user's password, so `secrets.env` then shows only the first password.

## Upgrading

1. Change the image tags in `images.conf` (or get the new version of this folder).
2. Run `./ol-hub-docker.sh`. It downloads the new images, runs the Hub's migration, and recreates only the
   containers whose image or settings changed.

**Without internet** (or when a company network blocks the image registries):

1. On a computer **with** internet and Docker, in this folder (with the same `install.conf`, or none for all
   apps): `./ol-hub-docker.sh save-images` — writes `ol-hub-images.tar` (several GB).
2. Copy this folder and that file to the computer **without** internet.
3. There: `./ol-hub-docker.sh load-images ol-hub-images.tar` — loads the images and sets `PULL_IMAGES=false`.
4. Run `./ol-hub-docker.sh` as usual.

## Troubleshooting

First run `./ol-hub-docker.sh status`, then `./ol-hub-docker.sh logs <component>` for the part that fails.
Re-running `./ol-hub-docker.sh` is always safe and repairs most problems.

| What you see | What to do |
|---|---|
| `A master licence is required` / the installer keeps asking for the licence | Copy the `.jwt` file from OpenLegacy into this folder and run again. The message under the question says what is wrong with the file you gave. |
| `... is not a master licence` | You have a different kind of licence: ask OpenLegacy for the **master** licence. |
| `Docker is installed but not running` | Start Docker Desktop (Linux: `sudo systemctl start docker`) and run again. |
| `Docker refuses this user` (Linux) | `sudo usermod -aG docker $USER`, log out and in, run again. |
| `Port 443 or 80 is already used` | Stop the other program (a web server, IIS...), or set `HTTPS_PORT=8443` and `HTTP_PORT=8080` in `install.conf`. |
| `Docker has N GB of memory; the Hub with these apps needs about M GB` | Give Docker more memory (Docker Desktop: *Settings → Resources → Memory*), or choose fewer apps (`APPS` in `install.conf`). You can also continue: the apps then start slowly or stop. |
| `This computer cannot reach: public.ecr.aws ...` | No internet, or a company proxy/firewall. Set the proxy in Docker Desktop (*Settings → Resources → Proxies*), or use `save-images` / `load-images` ([Upgrading](#upgrading)). |
| `The installer needs Git for Windows` (double-clicking `ol-hub-docker.cmd`) | Install [Git for Windows](https://git-scm.com/download/win) with the default options, then double-click again. |
| `the Hub refused the licence: HTTP 400 - license signature invalid` | The file is not a valid OpenLegacy master licence (changed, or for another product). Ask OpenLegacy for the master licence; replace `master-license.jwt` and run again. |
| `<component> was not ready after 900s` | Slow computer or download: set `WAIT_TIMEOUT=1800` in `install.conf` and run again. The log lines printed above the error show the real cause. |
| `Could not download the images` | Check the internet connection or proxy. Images come from `public.ecr.aws` and Docker Hub (`openlegacy/openlegacy-keycloak`). |
| `Docker has an expired login for public.ecr.aws` | An old `docker login public.ecr.aws` expired; Docker then refuses even public images. The installer downloads them without that login and carries on. To fix it for good: `docker logout public.ecr.aws`. |
| The browser says "Your connection is not private" | Expected with the self-signed certificate: `./ol-hub-docker.sh trust-certificate`, or continue past the warning ([Certificates](#certificates)). |
| The address does not open at all | `localhost`: use Chrome, Edge or Firefox. Another computer: its DNS (or hosts file) must point the names at this computer, and the firewall must allow port 443. |
| Sign-in error "Invalid parameter: redirect_uri" | The page's address is not allowed: run `./ol-hub-docker.sh sync-keycloak` (after changing addresses), or add it to `EXTRA_REDIRECT_URIS`. |
| OL Terminal / OL Code area stays empty in the Hub | The browser does not trust their address yet: `./ol-hub-docker.sh trust-certificate`, or open that app's address once and accept the warning. |
| An app answers 401 although you are signed in | Wrong addresses after a change: run `./ol-hub-docker.sh` again (it re-applies everything), then sign out and in. |
| An app says "The Hub licence ... could not be read", or "Tenant not found or inactive" | The licence is not active: `./ol-hub-docker.sh activate-license master-license.jwt`. Sign in as `ol-hub`, the built-in admin. |
| `licence ... is already used by tenant ...` | That licence belongs to another tenant: use the `TENANT_ID` shown, or ask OpenLegacy for a new licence. |
| `Licence activation failed: HTTP 4xx` | The Hub refused the licence (expired, not a master licence): the message says why. |
| `/remotes/<app>` 404 in `status` | The app is not switched on in the Hub (it was not answering during the install): run `./ol-hub-docker.sh` again once it is up. |
| `/remotes/<app>` FAIL / 502 | The app is down: `./ol-hub-docker.sh logs <app>`. |
| The Hub keeps restarting | `./ol-hub-docker.sh logs ol-hub` shows why; then run `./ol-hub-docker.sh` again. |
| `$'\r': command not found` | The scripts got Windows line endings: in Git Bash run `git config core.autocrlf input`, then check this folder out again (the folder's `.gitattributes` prevents this for new checkouts). |
| *the keyboard is typing another language* | The keyboard is set to another language (for example Hebrew): switch it to English (Alt+Shift) and answer again. The Y and N keys are understood in Hebrew too. |
| The arrow keys do nothing in the app list | The terminal does not send them: use **J** (down) and **K** (up) instead, or run `OLHUB_NUMBERED_LIST=1 ./ol-hub-docker.sh` to choose the apps by typing their numbers. |
| A question rejects a clear `y`, or the app list looks wrong | Run it with `OLHUB_DEBUG=1 ./ol-hub-docker.sh` and answer as usual: every raw answer is written to `generated/answers.log`. Send that file to OpenLegacy support with a description of what happened. |

## Files

```
ol-hub-docker.sh              the installer and day-to-day tool (run this)
ol-hub-docker.cmd             Windows: double-click for the menu (opens Git Bash with the OL icon); also takes commands
install.conf.example          settings template; install.conf = your settings (created on the first run)
images.conf                   image per component
docker-compose.yml            every component, with all its settings
docker-compose.localhost.yml  added only with APPS_DOMAIN=localhost (*.localhost names inside the containers)
config/caddy/Caddyfile        HTTPS proxy: one address per component
config/keycloak/              realm ol-hub (imported on Keycloak's first start)
config/postgres/initdb/       creates the schema keycloak on the database's first start
config/hub/                   the Hub's settings per app (switched on by the installer)
certs/                        your certificate (TLS_MODE=custom), the exported local CA
lib/                          installer functions (menu.sh: the menu, picklist.sh: the app list you mark,
                              credentials.sh: passwords and the encrypted file)
assets/                       ol-hub.ico (window icon of the Windows launcher) and its source ol-hub.svg
--- created by the installer (git-ignored, never commit them) ---
install.conf  master-license.jwt  secrets.env  ol-hub-credentials.enc  .env  generated/  certs/openlegacy-root-ca.crt
ol-hub-images.tar (save-images)
```
