Buildbot configuration for Halide build bots

To get started:

Install python3.x, python-pip, then run:

```
sudo pip install virtualenv
virtualenv python
source python/bin/activate
# for a master
pip install "buildbot[bundle]"
# or for a worker
pip install "buildbot-worker"
```

To create and launch the build master:

```
echo some_password > master/halide_bb_pass.txt
buildbot create-master master
buildbot start master
```

To launch a build worker:

```
echo the_same_password > worker/halide_bb_pass.txt
HALIDE_BB_WORKER_NAME=<worker_name> buildbot-worker start worker
```

If you're making your own master, you'll may need to edit
linux_slave/buildbot.tac to point to the ip address of your build
master. In the repo it's configured to point to the public Halide
build master.
