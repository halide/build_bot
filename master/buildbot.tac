import os
from pathlib import Path

from buildbot.master import BuildMaster
from twisted.application import service
from twisted.python.log import ILogObserver, FileLogObserver
from twisted.python.logfile import LogFile

basedir = str(Path(__file__).parent.resolve())
rotateLength = 10000000
maxRotatedFiles = 10
configfile = 'master.cfg'

# Default umask for server
umask = None

logfile = LogFile.fromFullPath(os.path.join(basedir, "twistd.log"),
                               rotateLength=rotateLength,
                               maxRotatedFiles=maxRotatedFiles)

# note: this line is matched against to check that this is a buildmaster
# directory; do not edit it.
application = service.Application('buildmaster')
application.setComponent(ILogObserver, FileLogObserver(logfile).emit)

m = BuildMaster(basedir, configfile, umask)
m.setServiceParent(application)
m.log_rotation.rotateLength = rotateLength
m.log_rotation.maxRotatedFiles = maxRotatedFiles
