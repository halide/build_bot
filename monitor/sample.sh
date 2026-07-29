#!/bin/sh
# Host-level network sampler for diagnosing the intermittent wheel-download
# connect timeouts (uv reports "client error (Connect): operation timed out").
#
# Runs as a docker-compose sidecar with network_mode: host, so the /proc/net
# counters below reflect the *host* TCP stack -- where inbound :443 SYNs are
# accepted and NATed to the caddy container -- rather than the sidecar's own
# namespace. It only reads /proc, so no extra tooling is needed.
#
# Emits one TSV row per interval. The failure is a connect timeout, which
# never reaches Caddy and so leaves no trace in Caddy's access log; these
# host counters are how we tell *where* the connection is being lost:
#
#   * listen_overflows / listen_drops / reqq_full_drop climbing, or syn_recv
#     spiking, or conntrack near conntrack_max, or load1 high  -> the loss is
#     on THIS host (accept-queue overflow / table exhaustion / CPU stall), and
#     we tune the host or Caddy accordingly.
#   * all of the above flat and low while CI reports failures -> the SYNs are
#     being dropped UPSTREAM (OpenStack floating-IP NAT / network path) and
#     never reached us; the fix is an infra/network escalation, not the server.
#
# Counters from /proc/net/{snmp,netstat} are cumulative since boot -- diff
# adjacent rows (by epoch) during analysis to get per-interval rates.
#
# Caveat: with Docker's userland-proxy enabled (the default), host:443 has a
# docker-proxy listener whose accept-queue drops show up here as
# listen_drops/overflows; with it disabled (pure iptables DNAT) accept-queue
# pressure instead lands in the caddy container's namespace, so cross-check
# against Caddy's caddy_http_requests_in_flight metric when interpreting.

set -u

INTERVAL="${SAMPLE_INTERVAL:-15}"
OUT="${SAMPLE_OUT:-/var/log/netmon/net-samples.tsv}"
MAX_BYTES="${SAMPLE_MAX_BYTES:-104857600}"  # rotate at 100 MiB, keep one prior

mkdir -p "$(dirname "$OUT")"

# Pull one named field out of /proc/net/snmp or /proc/net/netstat. These files
# store, per protocol label, a header row of field names followed by a values
# row; map names->columns from the header, then print the matching value.
field() {
  # $1=file  $2=label (e.g. Tcp, TcpExt)  $3=field name
  awk -v L="$2:" -v F="$3" '
    $1==L {
      if (!(L in seen)) { for (i=2;i<=NF;i++) col[$i]=i; seen[L]=1; next }
      print $(col[F])
    }' "$1"
}

if [ ! -f "$OUT" ]; then
  printf 'epoch\tiso\tload1\tconntrack\tconntrack_max\tcurr_estab\tsyn_recv\tactive_opens\tpassive_opens\tattempt_fails\tretrans_segs\tout_rsts\tlisten_overflows\tlisten_drops\treqq_full_drop\tsyncookies_sent\ttcp_timeouts\tsyn_retrans\n' > "$OUT"
fi

while :; do
  epoch=$(date +%s)
  iso=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  load1=$(cut -d' ' -f1 /proc/loadavg)
  ct=$(cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null || echo -1)
  ctmax=$(cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null || echo -1)

  curr_estab=$(field /proc/net/snmp Tcp CurrEstab)
  active_opens=$(field /proc/net/snmp Tcp ActiveOpens)
  passive_opens=$(field /proc/net/snmp Tcp PassiveOpens)
  attempt_fails=$(field /proc/net/snmp Tcp AttemptFails)
  retrans_segs=$(field /proc/net/snmp Tcp RetransSegs)
  out_rsts=$(field /proc/net/snmp Tcp OutRsts)

  listen_overflows=$(field /proc/net/netstat TcpExt ListenOverflows)
  listen_drops=$(field /proc/net/netstat TcpExt ListenDrops)
  reqq_full_drop=$(field /proc/net/netstat TcpExt TCPReqQFullDrop)
  syncookies_sent=$(field /proc/net/netstat TcpExt SyncookiesSent)
  tcp_timeouts=$(field /proc/net/netstat TcpExt TCPTimeouts)
  syn_retrans=$(field /proc/net/netstat TcpExt TCPSynRetrans)

  # SYN_RECV (TCP state 0x03) across IPv4+IPv6: half-open / accept-queue depth.
  syn_recv=$(cat /proc/net/tcp /proc/net/tcp6 2>/dev/null | awk '$4=="03"' | wc -l | tr -d ' ')

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$epoch" "$iso" "$load1" "$ct" "$ctmax" "$curr_estab" "$syn_recv" \
    "$active_opens" "$passive_opens" "$attempt_fails" "$retrans_segs" "$out_rsts" \
    "$listen_overflows" "$listen_drops" "$reqq_full_drop" "$syncookies_sent" \
    "$tcp_timeouts" "$syn_retrans" >> "$OUT"

  sz=$(wc -c < "$OUT" 2>/dev/null || echo 0)
  if [ "$sz" -gt "$MAX_BYTES" ]; then
    mv "$OUT" "$OUT.1"
  fi

  sleep "$INTERVAL"
done
