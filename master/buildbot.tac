import sys
from pathlib import Path

from buildbot.master import BuildMaster
from twisted.application import service
from twisted.logger import ILogObserver, textFileLogObserver

# note: this line is matched against to check that this is a buildmaster
# directory; do not edit it.
application = service.Application('buildmaster')  # fmt: skip
application.setComponent(ILogObserver, textFileLogObserver(sys.stdout))

m = BuildMaster(str(Path(__file__).parent), "master.cfg", umask=None)
m.setServiceParent(application)
