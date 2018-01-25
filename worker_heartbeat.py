# Usage: python worker_heartbeat.py

# If you plan to close the shell you run this in, detach it with something like:
# nohup python worker_heartbeat.py &

# Run this script on any machine with a reliable uptime and internet
# connection. Every 30 mins it connects to the buildbot REST endpoints
# and checks for liveness of the buildbots. It then connects to the
# gitter channel REST endpoint and tells us whether any are down.

# If you prefer, you can remove the while loop and sleep call and run this as a cron
# job.

# In the future we may want to consider also reporting build breakages
# on master to the gitter channel, post warnings when an individual
# builder has a very long queue, etc. Buildbot exposes a whole lot of
# stuff for us in convenient-to-consume json nuggets.

import json, urllib, urllib2, time

while True:    
    j = json.load(urllib2.urlopen("https://buildbot.halide-lang.org/master/api/v2/workers"))

    expected_workers = ["arm32-linux-worker-1", "arm32-linux-worker-2", "arm64-linux-worker-1", "arm64-linux-worker-2", "linux-worker-1", "linux-worker-2", "linux-worker-3", "mac-worker-1", "win-worker-1", "win-worker-2"]

    missing_workers = []

    for e in expected_workers:
        matches = [w for w in j['workers'] if w['name'] == e]
        if not matches or not matches[0]['connected_to']:
            missing_workers.append(e)

    if missing_workers:
        message = "The following workers are offline: " + ' '.join(missing_workers)
        level = "error"
    else:
        message = "All workers accounted for"
        level = "info"
    
    data = urllib.urlencode({'message': message, 'level': level})
    response = urllib2.urlopen(urllib2.Request('https://webhooks.gitter.im/e/542ccf5d8e37a44a2c48', data))
        
    print response.read()

    # Notify every 30 mins
    time.sleep(30 * 60 * 60)
