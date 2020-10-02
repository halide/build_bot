import os

from twisted.application import service

# Begin Workaround from https://github.com/buildbot/buildbot/issues/4592#issuecomment-577250309 :
# Remove when https://github.com/buildbot/buildbot/issues/4592 is fixed

from twisted.internet import defer
from buildbot.util.service import AsyncMultiService


class BuildRequestDistributor(AsyncMultiService):

    def __init__(self, botmaster):
        AsyncMultiService.__init__(self)
        self.botmaster = botmaster
        self.active = False
        self.timer = None
        self.cooldown_seconds = 4
        self.loop_deferred = None
        self.lock = defer.DeferredLock()

    @defer.inlineCallbacks
    def stopService(self):
        try:
            yield self.lock.acquire()
            yield AsyncMultiService.stopService(self)
            yield self.stop_loop()
        finally:
            self.lock.release()

    @defer.inlineCallbacks
    def maybeStartBuildsOn(self, new_builders):
        if not self.running:
            return
        try:
            yield self.lock.acquire()
            if not self.running:
                return
            yield self.stop_loop()
            self.timer = self.master.reactor.callLater(
                self.cooldown_seconds, self.start_loop)
        finally:
            self.lock.release()

    @defer.inlineCallbacks
    def stop_loop(self):
        if self.timer is not None:
            self.timer.cancel()
            self.timer = None
        if self.loop_deferred is not None:
            d = self.loop_deferred
            self.loop_deferred = None
            self.active = False
            yield d

    @defer.inlineCallbacks
    def start_loop(self):
        try:
            yield self.lock.acquire()
            self.timer = None
            yield self.stop_loop()
            if not self.running:
                return
            self.active = True
            self.loop_deferred = self.loop()
        finally:
            self.lock.release()

    @defer.inlineCallbacks
    def request_from_brdict(self, brdict):
        from buildbot.process.buildrequest import BuildRequest
        breq = yield BuildRequest.fromBrdict(self.master, brdict)
        breq.builder = self.botmaster.builders.get(breq.buildername)
        return breq

    @defer.inlineCallbacks
    def loop(self):
        from buildbot.data import resultspec

        brdicts = yield self.master.data.get(
            ['buildrequests'],
            [resultspec.Filter('claimed', 'eq', [False])])

        requests = yield defer.gatherResults(
            [self.request_from_brdict(b) for b in brdicts])

        try:
            self.master.config.prioritizeBuilders(requests)
        except Exception as e:
            print('BRD: ERROR %r while sorting build requests' % e)

        while self.active and self.running and requests:
            try:
                yield self.try_start_build(requests.pop(0))
            except Exception as e:
                print('BRD: ERROR %r while trying to start build' % e)

    @defer.inlineCallbacks
    def try_start_build(self, breq):
        from buildbot.util import epoch2datetime

        builder = breq.builder

        workerpool = builder.getAvailableWorkers()
        worker = None

        while workerpool and worker is None:
            worker = builder.config.nextWorker(builder, workerpool, breq)
            if worker is None:
                break
            workerpool.remove(worker)
            can_start = yield builder.canStartBuild(worker, breq)
            if not can_start:
                worker = None

        if worker is None:
            return

        yield self.master.data.updates.claimBuildRequests(
            [breq.id], claimed_at=epoch2datetime(self.master.reactor.seconds()))

        started = yield builder.maybeStartBuild(worker, [breq])
        if not started:
            yield self.master.data.updates.unclaimBuildRequests([breq])
        else:
            print('BRD: starting build %s on %s (%s)'
                  % (builder.name, worker.worker.name, ', '.join(builder.config.tags)))

from buildbot.process import buildrequestdistributor
buildrequestdistributor.BuildRequestDistributor = BuildRequestDistributor

# End Workaround

from buildbot.master import BuildMaster

basedir = '/home/abadams/build_bot_new/master'
rotateLength = 10000000
maxRotatedFiles = 10
configfile = 'master.cfg'

# Default umask for server
umask = None

# if this is a relocatable tac file, get the directory containing the TAC
if basedir == '.':
    import os
    basedir = os.path.abspath(os.path.dirname(__file__))

# note: this line is matched against to check that this is a buildmaster
# directory; do not edit it.
application = service.Application('buildmaster')

from twisted.python.logfile import LogFile
from twisted.python.log import ILogObserver, FileLogObserver

logfile = LogFile.fromFullPath(os.path.join(basedir, "twistd.log"),
                               rotateLength=rotateLength,
                               maxRotatedFiles=maxRotatedFiles)

application.setComponent(ILogObserver, FileLogObserver(logfile).emit)

m = BuildMaster(basedir, configfile, umask)
m.setServiceParent(application)
m.log_rotation.rotateLength = rotateLength
m.log_rotation.maxRotatedFiles = maxRotatedFiles
