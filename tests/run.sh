#!/bin/bash
# Offline tests for the scripts and the array template: fake sinfo/sshare on PATH, saved sacct
# output, and the template run as a plain bash script. Run from anywhere: tests/run.sh
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(dirname "$HERE")
export FIXTURES=$HERE/fixtures
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
pass=0 fail=0

check() {  # check <name> <expected substring> <actual output>
  if printf '%s' "$3" | grep -qF -- "$2"; then pass=$((pass + 1))
  else fail=$((fail + 1)); printf 'FAIL %s\n  expected: %s\n  got:\n%s\n' "$1" "$2" "$3"; fi
}

# --- suggest-time ---------------------------------------------------------------------------
st() { python3 "$ROOT/scripts/suggest-time" --sacct-file "$FIXTURES/sacct.txt" "$@" 2>&1; }
out=$(st train)
check "history: killed run blocks --time" "no safe --time: a run was killed at 04:00:00" "$out"
check "history: memory" "suggest  --mem=25G" "$out"
out=$(st --jobs 300,301,302 --units 1 --scale 400)
check "pilot: sized by slowest unit" "suggest  --time=03:00:00 --mem=10G" "$out"
check "pilot: warns on 4x spread" "over 4x" "$out"
check "pilot: credits per job" "180000" "$out"
check "pilot: task count" "400 tasks (--array=0-399%K)" "$out"
out=$(st --jobs 400,401,402)
check "shape sweep: cheapest within 1.25x" "sweet spot: 8 CPUs, 1 GPUs" "$out"
out=$(st nosuchjob)
check "history: unknown name" "no jobs named 'nosuchjob'" "$out"

# --- cluster-now ----------------------------------------------------------------------------
cn() { VSC_QUEUESTATE=/nonexistent PATH="$HERE/bin:$PATH" bash "$ROOT/scripts/cluster-now" -M wice "$@" 2>&1; }
out=$(cn)
check "cluster-now: accounts, default account hidden" "fair-share: lp_group=1.000 lp_other=0.020" "$out"
check "cluster-now: free/fit/held/total" "gpu_h100           9     7     3     20" "$out"
out=$(cn -c 24 -m 180 -A lp_other)
check "cluster-now: shape limits fit" "gpu_h100           9     4     3     20" "$out"
check "cluster-now: -A filters" "fair-share: lp_other=0.020" "$out"
case $out in *debug*|*batch*) check "cluster-now: skips debug and CPU partitions" "no debug" "$out" ;; *) pass=$((pass + 1)) ;; esac

# --- array.sbatch + remaining ---------------------------------------------------------------
cd "$TMP"
sed -e 's/<units per task>/2/' -e 's|<command>|./w|' "$ROOT/templates/array.sbatch" > job.sh
printf 'a 1\nb/x 1\nc 1\nd 1\n' > units.txt
printf '#!/bin/sh\nsleep 2\n' > w; chmod +x w
export SLURM_ARRAY_JOB_ID=9 SLURM_JOB_PARTITION=gpu_h100
SLURM_ARRAY_TASK_ID=0 bash job.sh > o0 2>&1 & P=$!
sleep 1; kill -USR1 $P; wait $P; rc=$?
check "template: early stop exits 75" "75" "$rc"
check "template: early stop message" "stopped with 1 units left" "$(cat o0)"
out=$(python3 "$ROOT/scripts/remaining" units.txt 2 --limit 4)
check "remaining: lists both unfinished tasks" "resubmit:  sbatch --array=0-1%4 <script>" "$out"
SLURM_ARRAY_TASK_ID=0 bash job.sh > /dev/null 2>&1; rc=$?
check "template: rerun resumes and exits 0" "0" "$rc"
check "template: '/' in unit name" "b_x_1.done" "$(ls results)"
out=$(python3 "$ROOT/scripts/remaining" units.txt 2)
check "remaining: task 1 left" "  task 1: 2 left" "$out"
printf '#!/bin/sh\nexit 3\n' > w
SLURM_ARRAY_TASK_ID=1 bash job.sh > o1 2>&1; rc=$?
check "template: failing unit exits with its code" "3" "$rc"
check "template: provenance recorded" '"partition":"gpu_h100"' "$(head -1 provenance.jsonl)"

echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
