Buildbot configuration for Halide build bots

To get started:

Install python2.7, python2.7-pip, then run:

```
pip install buildbot
```

To create and launch the build master:

```
echo some_password > master/halide_bb_pass.txt
buildbot create-master master
buildbot start master
```

To launch a build slave:

```
echo the_same_password > master/halide_bb_pass.txt
buildslave start linux_slave
```

If you're making your own master, you'll may need to edit
linux_slave/buildbot.tac to point to the ip address of your build
master. In the repo it's configured to point to the public Halide
build master.
