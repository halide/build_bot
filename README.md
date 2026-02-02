# Python environment

To get started hacking, install Python 3.10+ and [uv]. Then run:

```console
$ uv sync --all-packages
```

# Master configuration

The master is deployed via [Docker Compose][dc], which manages three services:
a PostgreSQL database, the Buildbot master, and a [Caddy] reverse proxy with
automatic HTTPS.

## Secrets

Five secrets control authentication with external users and servers. These will
need to be determined before starting up a new master.

1. Obtain a [GitHub personal access token](https://github.com/settings/tokens)
   with at least the `repo` scope enabled (other scopes that are not currently
   used but might be later are `write:packages` and `delete:packages`). Call
   this `GITHUB_TOKEN`.
2. Generate a secret for the workers to authenticate with the master. Call this
   `WORKER_SECRET`.
3. Generate a secret to authenticate GitHub's webhook updates with the master.
   Call this `WEBHOOK_SECRET`.
4. Choose a password for the `halidenightly` user to authenticate with the web
   interface. Call this `WWW_PASSWORD`.
5. Generate a password for the PostgreSQL database. Call this `DB_PASSWORD`.
   This is only needed when using PostgreSQL (i.e., when
   `HALIDE_BB_MASTER_DB_URL` contains `{DB_PASSWORD}`). The default SQLite
   backend does not require it.

A convenient command for generating a secure secret is `openssl rand -hex 20`.

Write all the secrets to the corresponding files:

```console
$ echo "$GITHUB_TOKEN" > secrets/github_token.txt
$ echo "$WORKER_SECRET" > secrets/halide_bb_pass.txt
$ echo "$WEBHOOK_SECRET" > secrets/webhook_token.txt
$ echo "$WWW_PASSWORD" > secrets/buildbot_www_pass.txt
$ echo "$DB_PASSWORD" > secrets/db_password.txt
```

## GitHub configuration

Make your way to the Webhooks section of your repository settings. The url is
`https://github.com/{owner}/{repo}/settings/hooks`. The following settings are
the correct ones:

1. **Payload URL:** `https://buildbot.halide-lang.org/master/change_hook/github`
2. **Content type:** `application/json`
3. **Secret:** `$WEBHOOK_SECRET`
4. **SSL verification:** Select _Enable SSL verification_
5. **Which events would you like to trigger this webhook?**
   a. **Let me select individual events.** Check _"Pull requests"_
   and _"Pushes"_.

## Starting the master

Choose a directory to hold artifacts from package builds (the default is
`./data/artifacts`):

```console
$ export HALIDE_BB_MASTER_ARTIFACTS_DIR=/srv/www/buildbot/public_html/artifacts
```

Then start all services:

```console
$ docker compose up -d --build
```

The database is automatically initialized on first start. Caddy handles TLS
certificates, so there is no manual web server configuration needed. The
Buildbot web interface is available at `https://buildbot.halide-lang.org/master/`
and artifacts are served at the site root.

Port 9990 must be reachable by workers. Port 8012 is internal only; Caddy
proxies it on ports 80/443.

### Running without Docker

By default, the master uses a SQLite database (`sqlite:///state.sqlite`), so
no external database is required. To use PostgreSQL instead, set
`HALIDE_BB_MASTER_DB_URL`:

```console
$ export HALIDE_BB_MASTER_DB_URL="postgresql://buildbot:{DB_PASSWORD}@db/buildbot"
```

Then start the master:

```console
$ ./master.sh start
```

The script automatically runs `upgrade-master` before starting. If the master
is already running, invoking `./master.sh` with no arguments will reconfig it
instead.

# Worker configuration

The master recognizes workers by their reported names, e.g. `linux-worker-4`
or `win-worker-1`.

## Linux / macOS

Write the worker secret and set the worker name, then use the wrapper script:

```console
$ echo "$WORKER_SECRET" > worker/halide_bb_pass.txt
$ export HALIDE_BB_WORKER_NAME=$WORKER_NAME
$ ./worker.sh
```

## Windows

```powershell
> Set-Content worker/halide_bb_pass.txt "$WORKER_SECRET"
> $env:HALIDE_BB_WORKER_NAME = "$WORKER_NAME"
> .\worker.ps1
```

## Optional environment variables

| Variable                | Default                    | Description     |
|-------------------------|----------------------------|-----------------|
| `HALIDE_BB_MASTER_ADDR` | `buildbot.halide-lang.dev` | Master hostname |
| `HALIDE_BB_MASTER_PORT` | `9990`                     | Master PB port  |

## Platform-specific installation

Automated installation scripts that set up system dependencies and configure
the worker to start automatically are provided under `worker/`:

- **macOS:** `worker/macos/install.sh` — installs Homebrew dependencies,
  configures ccache, and installs a launchd agent so the worker starts on login.
  Requires `HALIDE_BB_WORKER_NAME`, `HL_WEBGPU_NODE_BINDINGS`,
  `HL_WEBGPU_NATIVE_LIB`, and `EMSDK` to be set before running.

- **Windows:** `worker/windows/install.ps1` — installs dependencies via winget,
  sets up Visual Studio 2022, installs uv, and bootstraps vcpkg with the
  required libraries.

[Caddy]: https://caddyserver.com
[dc]: https://docs.docker.com/compose/
[uv]: https://docs.astral.sh/uv