# Python environment

To get started setting up _either_ a worker or a master, install Python 3.6+, python3-pip, and python3-venv, then create
a virtual environment and install our Python dependencies:

```console
$ python3 -m venv venv
$ . venv/bin/activate
$ pip install -r requirements.txt
```

# Master configuration

## Web server settings

Using your production-quality web server of choice (Apache, Nginx, etc.), choose a URL at which to host the master. Call
this `BUILDBOT_WWW`. Then, set up a reverse proxy for the buildbot webserver (on port 8012). For Apache, your
configuration might look like:

```
ProxyPass /ws ws://localhost:8012/ws
ProxyPassReverse /ws ws://localhost:8012/ws
ProxyPass / http://localhost:8012/
ProxyPassReverse / http://localhost:8012/

SetEnvIf X-Url-Scheme https HTTPS=1
ProxyPreserveHost On
```

Note that you will need to enable `proxy_wstunnel` for this to work (via `a2enmod`). It is essential that HTTPS only is
used (to protect)

**Close port 8012 to the internet.** If you can't have port 9990 open, redirect another port to it. Whichever port this
is, call it `MASTER_PORT`.

Make a note of your master's IP address. Call this `MASTER_ADDR`.

## Secrets

Four secrets control authentication with external users and servers. These will need to be determined before starting up
a new master.

1. Obtain a [GitHub personal access token](https://github.com/settings/tokens) with at least the `repo` scope enabled (
   other scopes that are not currently used but might be later are `write:packages` and `delete:packages`). Call
   this `GITHUB_TOKEN`.
2. Generate a secret for the workers to authenticate with the master. Call this `WORKER_SECRET`.
3. Generate a secret to authenticate GitHub's webhook updates with the master. Call this `WEBHOOK_SECRET`.
4. Choose a password for the `halidenightly` user to authenticate with the web interface. Call this `WWW_PASSWORD`.

A convenient command for generating a secure secret is `openssl rand -hex 20`.

## GitHub Configuration

Make your way to the Webhooks section of your repository settings. The url
is `https://github.com/{owner}/{repo}/settings/hooks`. The following settings are the correct ones:

1. **Payload URL:** `$BUILDBOT_WWW/change_hook/github`
2. **Content type:** `application/json`
3. **Secret:** `$WEBHOOK_SECRET`
4. **SSL verification:** Select _Enable SSL verification_
5. **Which events would you like to trigger this webhook?**
   a. **Let me select individual events.**. Check _"Pull requests"_ and _"Pushes"_.

## Starting the master

First, write all the secrets to the corresponding files:

```console
$ echo "$GITHUB_TOKEN" > master/github_token.txt
$ echo "$WORKER_SECRET" > master/halide_bb_pass.txt
$ echo "$WEBHOOK_SECRET" > master/webhook_token.txt
$ echo "$WWW_PASSWORD" > master/buildbot_www_pass.txt
```

Then, create a database for the master to save its work. This only needs to be done once.

```console
$ buildbot upgrade-master master
```

Choose a directory to hold artifacts for package runs:

```console
$ export HALIDE_BB_MASTER_ARTIFACTS_DIR=/srv/www/buildbot/public_html/artifacts
```

Finally, start the master!

```console
$ buildbot start master
```

# Worker configuration

## Worker dependencies

(TODO: flesh this out)

The macOS and Linux buildbots expect to have ccache installed. It is available through homebrew or APT. After
installing, one should run the following commands:

```console
$ ccache --set-config=sloppiness=pch_defines,time_macros
$ ccache -M 100G  # or smaller, depending on disk size
```

The first command allows CCache to work in the presence of precompiled headers. The second sets the cache size to
something very large (100GB in this case).

## Starting a worker

The master recognizes workers by their reported names, eg. `linux-worker-4` or `win-worker-1`. To launch the buildbot
daemon on the worker named `$WORKER_NAME`, run the following commands after setting up the Python environment as
detailed above:

```console
$ echo "$WORKER_SECRET" > worker/halide_bb_pass.txt
$ export HALIDE_BB_WORKER_NAME=$WORKER_NAME  # required
$ export HALIDE_BB_MASTER_ADDR=$MASTER_ADDR  # default = public Halide master
$ export HALIDE_BB_MASTER_PORT=$MASTER_PORT  # default = 9990
$ buildbot-worker start worker
```
