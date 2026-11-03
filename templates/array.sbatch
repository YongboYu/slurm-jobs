#!/bin/bash
# Array job over a list of work units: task i runs units [i*PER_TASK, (i+1)*PER_TASK) of units.txt.
# Each finished unit leaves a .done marker and is skipped on a rerun, so a killed or resubmitted
# task resumes where it stopped. Every task appends one provenance record.
#
# Exit codes: 0 = every unit of the task done; 75 = stopped near the time limit with units left
# (resubmit that task, it resumes); other = a unit failed (fix it first). So `sacct` shows a task
# with units left as FAILED, never COMPLETED.
#
# units.txt: one unit per line, no duplicate lines (duplicates share one .done marker).
#
# Fill in the <...> fields. logs/ must exist before sbatch (Slurm opens the log before the script
# runs; a missing folder fails the job without a log). For 400 units at 10 per task, 8 running:
#   mkdir -p logs && sbatch --array=0-39%8 array.sbatch
# Worst-case credit quote first: sam-quote sbatch --array=0-39%8 array.sbatch
#SBATCH --job-name=<kind>-<dataset>
#SBATCH --account=<account>
#SBATCH --clusters=<wice|mindwell>
#SBATCH --partition=<one GPU type per comparison group, e.g. gpu_h100>
#SBATCH --nodes=1
#SBATCH --gpus-per-node=<n>
#SBATCH --cpus-per-gpu=<from pilot>
#SBATCH --mem=<from suggest-time>
#SBATCH --time=<from suggest-time>
#SBATCH --signal=B:USR1@300
#SBATCH --output=logs/%x-%A_%a.out
set -euo pipefail

PER_TASK=<units per task>
UNITS=units.txt                      # one unit per line, e.g. "dataset window seed"
OUT=results                          # unit output: $OUT/<unit with spaces as _>.done
mkdir -p "$OUT"

# Environment (edit): modules or a venv, and inputs staged to fast storage when they are read a lot.
# module load cluster/<wice|mindwell>/<partition-group> <Module/version>
# source "$VSC_DATA/<project>/.venv/bin/activate"
# rsync -a "$VSC_DATA/<inputs>/" "$VSC_SCRATCH/<inputs>/"   # then point <command> at $VSC_SCRATCH

stop=0
trap 'stop=1; echo "USR1: time limit near, stopping after the current unit"' USR1

gpu=$(nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>/dev/null | head -1 || echo none)
cpu=$(lscpu 2>/dev/null | awk -F: '/Model name/ {gsub(/^ +/, "", $2); print $2; exit}' || echo none)
commit=$(git rev-parse --short HEAD 2>/dev/null || echo none)
printf '{"job":"%s","task":"%s","host":"%s","partition":"%s","gpu":"%s","cpu":"%s","commit":"%s","start":"%s"}\n' \
  "$SLURM_ARRAY_JOB_ID" "$SLURM_ARRAY_TASK_ID" "$(hostname)" "$SLURM_JOB_PARTITION" "$gpu" "$cpu" "$commit" \
  "$(date -u +%FT%TZ)" >> provenance.jsonl

first=$(( SLURM_ARRAY_TASK_ID * PER_TASK + 1 ))
while read -r unit; do
  [ "$stop" = 1 ] && break
  name=${unit//\//_}
  done_file="$OUT/${name// /_}.done"
  [ -e "$done_file" ] && continue
  start=$(date +%s)
  <command> $unit &                  # in the background, so the USR1 trap runs mid-unit
  pid=$!
  until wait "$pid"; rc=$?; ! kill -0 "$pid" 2>/dev/null; do :; done
  [ "$rc" = 0 ] || { echo "unit failed (exit $rc): $unit"; exit "$rc"; }
  echo "$unit $(( $(date +%s) - start ))s" > "$done_file"
done < <(sed -n "${first},$(( first + PER_TASK - 1 ))p" "$UNITS")

left=0
while read -r unit; do
  name=${unit//\//_}
  [ -e "$OUT/${name// /_}.done" ] || left=$(( left + 1 ))
done < <(sed -n "${first},$(( first + PER_TASK - 1 ))p" "$UNITS")
if [ "$left" -gt 0 ]; then
  echo "stopped with $left units left: resubmit with --array=$SLURM_ARRAY_TASK_ID"
  exit 75
fi
