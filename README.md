# Configuration for Halide buildbots

To get started:

Install Python 3.6+, python3-pip, and python3-venv, then run:

```console
$ python3 -m venv venv
$ . venv/bin/activate
$ pip install -r requirements.txt
```

First, choose a buildbot password `$PASSWORD`. Then create and launch the build master:

```console
$ echo "$PASSWORD" > master/halide_bb_pass.txt
$ echo "<github-api-token>" > master/github_token.txt
$ buildbot upgrade-master master
$ buildbot start master
```

To launch a build worker:

```console
$ echo "$PASSWORD" > worker/halide_bb_pass.txt
$ export HALIDE_BB_WORKER_NAME=<worker_name>  # required
$ export HALIDE_BB_MASTER_ADDR=<master_ip>    # default = public Halide master
$ export HALIDE_BB_MASTER_PORT=<master_port>  # default = 9990
$ buildbot-worker start worker
```
