# slurm-jobs

An agent skill (Claude Code, Codex, or any agent that reads `SKILL.md`) for running Slurm work on
the VSC / KU Leuven Tier-2 clusters (wICE, mindwell) so it waits less and wastes fewer credits.

On wICE your job's rank is mostly your group's fair-share, which you do not control. What you do
control is whether the job **fits a backfill gap**: an honest `--time`, the CPUs, memory and GPUs
the job actually uses, and every partition it can run on. The skill sizes those requests from your
own `sacct` history and from small pilots, then plans, submits and follows up a whole campaign.

## Workflow

```
 1 Scope         work units × command, grouped into comparison groups (one GPU type each)
 2 Read cluster  cluster-now ─► fair-share, free / fitting / held GPUs per partition;  sam-balance
 3 Read history  suggest-time '<job name>' ─► --time and --mem from your past runs (or "no history")
 4 Plan          slurm/<campaign>.md: arrays of 30 min–6 h tasks, requests, credits ◄── you approve
 5 Pilot         smallest / median / largest unit, a few CPU shapes
                 suggest-time --jobs … ─► cheapest shape, --time for the slowest unit ◄── you approve
 6 Submit        templates/array.sbatch: resumable units, early stop near the limit, provenance
 7 Watch, learn  squeue --start, sprio; remaining ─► --array list to resubmit;
                 used vs asked goes into the plan, which becomes step 3's history next time
```

A single job skips the plan file: steps 2 and 3, then the request.

## What is in here

| Path | What |
|---|---|
| `SKILL.md` | The steps the agent follows |
| `reference/cluster.md` | Scheduler facts for wICE and mindwell (priority weights, backfill settings, limits, GPU partitions), each with the command that re-checks it |
| `scripts/cluster-now` | Fair-share per account; per GPU partition the GPUs free, the GPUs a job of your shape fits on now, held GPUs, pending jobs |
| `scripts/suggest-time` | `--time`/`--mem` from history; pilot report with CPU efficiency, peak memory, credits and the cheapest shape |
| `scripts/remaining` | Which array tasks still have units left, as an `--array=` list |
| `templates/array.sbatch` | Array job over `units.txt`: skips finished units, stops cleanly near the time limit (exit 75), logs provenance |
| `extras/queue-sampler` | Optional scrontab job that logs queue state every 30 min |
| `tests/run.sh` | Offline tests (fake `sinfo`/`sshare`, saved `sacct` output) |

Scripts need only bash, awk and Python 3 standard library, as on the login nodes.

## Install

```bash
git clone git@github.com:YongboYu/slurm-jobs.git ~/.agents/skills/slurm-jobs
ln -s ~/.agents/skills/slurm-jobs ~/.claude/skills/slurm-jobs     # Claude Code
# the scripts run on the login node:
rsync -a ~/.agents/skills/slurm-jobs/scripts/ hpc:"$(ssh hpc 'bash -lc "echo \$VSC_DATA"')"/slurm-jobs/
```

`hpc` is your SSH alias for a VSC login node. Then ask the agent, for example: "plan the
sweep over these 12 datasets × 5 seeds on wICE", or "why is job 6253456 still pending?".

The scripts work without an agent too: `$VSC_DATA/slurm-jobs/suggest-time -h`.

## Other sites

The method is general Slurm; the numbers in `reference/cluster.md`, the partition names, and
`sam-balance`/`sam-quote` are KU Leuven's. Elsewhere, re-derive the reference file with the
commands it lists and adjust the partition patterns in `cluster-now`.
