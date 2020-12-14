import os
import sys

from pathlib import Path
from buildbot_worker.bot import Worker
from twisted.application import service
from twisted.python.logfile import LogFile
from twisted.python.log import ILogObserver, FileLogObserver

basedir = os.path.abspath(os.path.dirname(__file__))
rotateLength = 10000000
maxRotatedFiles = 10

# note: this line is matched against to check that this is a worker
# directory; do not edit it.
application = service.Application('buildbot-worker')

logfile = LogFile.fromFullPath(
    os.path.join(basedir, "twistd.log"), rotateLength=rotateLength,
    maxRotatedFiles=maxRotatedFiles)
application.setComponent(ILogObserver, FileLogObserver(logfile).emit)

buildmaster_host = os.environ.get('HALIDE_BB_MASTER_ADDR', '104.154.46.123')
port = os.environ.get('HALIDE_BB_MASTER_PORT', 9990)
workername = os.environ.get('HALIDE_BB_WORKER_NAME') or sys.exit('env var HALIDE_BB_WORKER_NAME must be non-empty')
passwd = Path('halide_bb_pass.txt').read_text().strip()
keepalive = 600
umask = None
maxdelay = 300
numcpus = None
allow_shutdown = None
maxretries = None
use_tls = None
delete_leftover_dirs = False

s = Worker(buildmaster_host, port, workername, passwd, basedir,
           keepalive, umask=umask, maxdelay=maxdelay,
           numcpus=numcpus, allow_shutdown=allow_shutdown,
           maxRetries=maxretries, useTls=use_tls,
           delete_leftover_dirs=delete_leftover_dirs)
s.setServiceParent(application)
