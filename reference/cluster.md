# KU Leuven Tier-2 scheduler facts (wICE, mindwell)

Verified 2026-11-03 from the live config. This file is a **cache**: re-check with the command
beside each fact when it is older than a month or when a result surprises you.

## Ranking: priority points (`scontrol -M <c> show config | grep ^Priority`)

Same settings on wICE and mindwell (Slurm multifactor, Fair Tree since `PriorityFlags` is empty).

| Factor | Max points | Note |
|---|---|---|
| Fair-share | 10,000 | The group's place among all users, not your own usage |
| Age | 1,000 | Full after 7 days (`PriorityMaxAge`). Jobs held by a dependency gain no age (no `ACCRUE_ALWAYS`) |
| Job size | 1,000 | Nodes/CPUs requested; `--time` does not enter it (`PriorityFavorSmall=no`) |
| TRES | CPU 1,000, GPU 1,000 | Share of the partition's CPUs and GPUs requested |
| QOS, partition | 0 | Every QOS priority is 0; partition weight 0 |

Submission time of day is not a factor.

## Fair-share (`sshare -M <c> -U`)

- Fair Tree: walks the account tree, ordering sibling accounts by LevelFS (share / recent usage);
  your FairShare is your rank among all users divided by their number. Everyone under a
  lower-ranked branch ranks below everyone under a higher-ranked one, whatever their own usage.
- `PriorityDecayHalfLife = 7 min`: only roughly the last half hour of usage counts, so the
  score swings with who in your branch is running now.
- It is per cluster and per account. One group on 2026-11-03: wICE 0.007 to 0.02 within the
  day, mindwell 1.0. A user with several accounts can have very different scores on each.
- `PrivateData` hides other users and the tree: the branch above a group is not visible.
  Docs: https://slurm.schedmd.com/fair_tree.html, https://slurm.schedmd.com/priority_multifactor.html

## Filling: backfill (`scontrol show config | grep SchedulerParameters`)

`sched/backfill` with `bf_interval=60`, `bf_resolution=600`, `bf_window=11000`, `bf_continue`,
`bf_max_job_start=100`. Every minute Slurm plans 7.6 days ahead in 10-minute steps; a lower
job starts now if it ends before the reserved start of every higher job it would delay.
So `--time` precision below 10 min buys nothing, and a padded `--time` loses gaps.
Preemption is off.

## Limits (`sacctmgr show qos`, `sinfo -M <c> -o "%P %l"`)

- QOS `normal`: at most 500 jobs submitted per user, pending plus running, array tasks
  counted one by one. `long` (on `*_long` partitions): 20 submitted, 10 nodes. `debug`
  (`*_debug`): 1 submitted. `interactive`: 4 submitted, 8 CPUs, 1 GPU.
- Max walltime: 3 days on `batch*`, `bigmem`, `gpu_*`; 7 days on `*_long`; 1 h on `*_debug`;
  16 h on `interactive`.
- CPU and memory per GPU (above this sbatch warns), from
  https://docs.vscentrum.be/leuven/slurm_specifics.html:
  P100 9 cores / 45,000 MiB; V100 4 / 84,000; A100 18 / 126,000; H100 16 / 187,200;
  B200 (mindwell) 24 / 194,400; interactive 8 / 60,000.
- GPU partitions need `--gpus-per-node` (sbatch rejects plain `--gpus`).
- Memory buys cores (`SelectTypeParameters=CR_CORE_MEMORY`): a request above the partition's
  memory per core gets the cores that come with that memory, and is billed for them. Example:
  `--cpus-per-task=8 --mem=1900G` on wICE bigmem was allocated 70 cores, billing 35 → 307.
  Ask for the peak memory (MaxRSS) plus margin.

## GPU partitions

| Cluster | Partition | GPUs | Debug / long |
|---|---|---|---|
| wICE | `gpu_h100` | 5 nodes × 4 H100 80 GB | |
| wICE | `gpu_a100` (= `gpu`) | 4 × 4 A100 80 GB | `gpu_a100_debug` (1 node) |
| wICE | `gpu_p100` | 9 × 4 P100 | `gpu_p100_debug`, `gpu_p100_long` |
| wICE | `gpu_v100` | 2 × 8 V100 | `gpu_v100_long` |
| mindwell | `gpu_b200` | 3 × 8 B200 | |

wICE `batch` is Ice Lake only; `batch_sapphirerapids` is a separate CPU type.

## Live state

- `/etc/motd.d/vsc_queuestate` on the login node, refreshed every 10 min: free, busy and
  reserved nodes/GPUs and pending jobs per partition (counts everyone's jobs).
- `squeue --start -j <id>`: the backfill planner's current start estimate.
- `sprio -j <id>`: the points of your pending job, factor by factor.
- Node state suffix `-` (`mix-`, `idle-`): Slurm holds the node for a pending higher job; a job
  starts there only if it ends before that job's reserved start. `cluster-now` reports these as *held*.
- History: when the user runs the sampler (`extras/queue-sampler`, every 30 min from scrontab),
  `$VSC_DATA/queue-sampler/*.csv` has GPU use per node, fair-share and pending jobs over time.
