# from https://hub.docker.com/r/buildbot/buildbot-worker

FROM buildbot/buildbot-worker:master


USER root

# Do this to prevent Docker from stopping at prompting us for our time zone
ENV \
    DEBIAN_FRONTEND="noninteractive" \
    TZ="America/Los_Angeles"

# TODO: cuda

# gcc 9.3 is the default gcc on Ubuntu 20,
# so we'll leave it at that. We need multilib
# for our 32-bit x86 builds, so install the gcc9 versions of those too.
RUN \
    apt-get update && \
    apt-get -y upgrade && \
    apt-get -y install -q \
        doxygen \
        g++-9-multilib \
        gcc-9-multilib \
        libatlas-base-dev \
        libeigen3-dev \
        libgl-dev \
        libjpeg-dev \
        libopenblas-dev \
        libpng-dev \
        ninja-build \
        python3-dev \
        zlib1g-dev &&\
    pip3 install \
        buildbot-worker~=2.10.0 \
        buildbot[bundle]~=2.10.0 \
        imageio==2.4.1 \
        numpy \
        pillow \
        pybind11==2.5.0 \
        scipy \
        Twisted~=20.3.0 \
        txrequests==0.9.6

USER buildbot
WORKDIR /buildbot

CMD ["pwd"]
CMD ["ls", "-l"]
CMD ["ls", "-l", "worker"]
# CMD ["buildbot-worker", "start", "worker"]
