Buildbot configuration for Halide build bots

To get started:

Install python2.7, python2.7-pip
pip install buildbot

To create and launch the build master:

export HALIDE_BB_PASS=some_password
buildbot creater-master master
buildbot start mater

To launch a build slave:

export HALIDE_BB_PASS=the_same_password
buildslave start ubuntu_slave

If you're making your own master, you'll may need to edit
ubuntu_slave/buildbot.tac to point to the ip address of your build
master. In the repo it's configured to point to the public Halide
build master.
