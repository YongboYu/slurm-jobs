#!/bin/bash
# Appends one snapshot of the queue to CSVs: one line per GPU node, one per CPU partition,
# your accounts' fair-share, and pending jobs per partition. Meant to run every 30 min from
# scrontab (see scrontab.txt); a few weeks of it show when each partition has room.
#   sample.sh [out-dir]      (default: $VSC_DATA/queue-sampler)
D=${1:-$VSC_DATA/queue-sampler}
mkdir -p "$D"
ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
[ -s "$D/gpu_nodes.csv" ] || echo "ts,cluster,partition,node,state,cpus_alloc,cpus_idle,cpus_other,cpus_total,gpus_total,gpus_used" > "$D/gpu_nodes.csv"
[ -s "$D/cpu_partitions.csv" ] || echo "ts,cluster,partition,cpus_alloc,cpus_idle,cpus_other,cpus_total" > "$D/cpu_partitions.csv"
[ -s "$D/fairshare.csv" ] || echo "ts,cluster,account,fairshare,levelfs" > "$D/fairshare.csv"
[ -s "$D/pending.csv" ] || echo "ts,state_ts,cluster,partition,pending" > "$D/pending.csv"

gpu() {
  sinfo -M "$1" -p "$2" -N -h -O "Partition:0|,NodeList:0|,StateCompact:0|,CPUsState:0|,Gres:0|,GresUsed:0" 2>/dev/null |
  awk -F"|" -v ts="$ts" -v c="$1" '
    function ngpu(s,   a, n) { if (!match(s, /gpu:[^:,(]+:[0-9]+/)) return 0
      n = split(substr(s, RSTART, RLENGTH), a, ":"); return a[n] }
    /^CLUSTER/ || NF < 6 {next}
    { split($4, cp, "/"); print ts "," c "," $1 "," $2 "," $3 "," cp[1] "," cp[2] "," cp[3] "," cp[4] "," ngpu($5) "," ngpu($6) }'
}
cpu() {
  sinfo -M "$1" -p "$2" -h -o "%P %C" 2>/dev/null |
  awk -v ts="$ts" -v c="$1" '/^CLUSTER/ {next} NF == 2 { split($2, cp, "/"); print ts "," c "," $1 "," cp[1] "," cp[2] "," cp[3] "," cp[4] }'
}
gpu wice gpu_h100,gpu_a100,gpu_p100,gpu_v100 >> "$D/gpu_nodes.csv"
gpu mindwell gpu_b200 >> "$D/gpu_nodes.csv"
cpu wice batch,batch_sapphirerapids,bigmem >> "$D/cpu_partitions.csv"
cpu mindwell batch_graniterapids,bigmem >> "$D/cpu_partitions.csv"

for c in wice mindwell; do
  sshare -M "$c" -U -n -P -o Account,FairShare,LevelFS 2>/dev/null |
    awk -F"|" -v ts="$ts" -v c="$c" 'NF >= 3 && $1 !~ /defaultslurmaccount$/ {print ts "," c "," $1 "," $2 "," $3}'
done >> "$D/fairshare.csv"

# Pending jobs per partition from the login message, when this node can read it.
Q=/etc/motd.d/vsc_queuestate
if [ -r "$Q" ]; then
  sed "s/\x1b\[[0-9;]*m//g" "$Q" | awk -v ts="$ts" '
    /^Queue state at/ {st = $4 "T" $5}
    /^[a-z]+:$/ {c = substr($1, 1, length($1) - 1)}
    /Pending jobs:/ {print ts "," st "," c "," $1 "," $NF}' >> "$D/pending.csv"
fi
