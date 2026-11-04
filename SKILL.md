---
name: slurm-jobs
description: Plan, size, submit and manage Slurm jobs on the VSC/KU Leuven clusters (wICE, mindwell) so they wait less. Use when writing or submitting an sbatch script or job array, splitting a run into jobs, choosing --time/--mem/partition, piloting resource use, or diagnosing pending, timed-out or out-of-memory jobs.
---

# slurm-jobs

Larger work is a **campaign**: a set of work units (dataset × window × seed, model × fold, …) run
as Slurm tasks. Waiting comes from two places (details and sources: [`reference/cluster.md`](reference/cluster.md)):

- **Rank**: priority is mostly the group's fair-share, which the user does not control.
- **Fill**: backfill starts a lower job early when it fits a gap. The request decides whether it
  fits: honest `--time`, the CPUs, memory and GPUs it uses, and every partition and cluster that fits.

So the lever is the request, and requests are predictable from history and pilots.

## Start where the request is

Enter the steps at the row that matches the request and stop where the row says; run the earlier
steps only when the entry step needs their output.

| Request | Start at | Stop after |
|---|---|---|
| Run a sweep, campaign or many jobs | 1 Scope | 7 Watch and learn |
| Write or submit one job | *One job, not a campaign* | its submission |
| Size a job: `--time`, `--mem`, CPUs per GPU | 3 Read history (5 Pilot when there is none) | the suggested request, not submitted |
| Where would it start soonest; why is it pending | 2 Read the cluster, then 7 *While pending* | the advice |
| Timed out, out of memory, units left, resubmit | 7 *After the run* | the resubmission, approved |

## Defaults

Before the first cluster command, read the user's defaults: `slurm/defaults` in the project, then
`~/.config/slurm-jobs/defaults`; a project value wins over the personal one. Keys and format:
[`defaults.example`](defaults.example). `SSH_HOST` is the login node alias, `ACCOUNT` goes into
`--account` and `cluster-now -A`, `CLUSTER` is tried first, and `CPUS_PER_GPU`/`GB_PER_GPU` are
the usual shape. `cluster-now` and `suggest-time` read the same files on the login node.

When neither file exists, ask the user once for the SSH alias, account and usual job shape, write
`~/.config/slurm-jobs/defaults`, and copy it to the login node (command in the example). A project
that differs (another account, one fixed GPU type) gets its own `slurm/defaults`.

**Access.** `hpc` below stands for `SSH_HOST` from the defaults. Run cluster commands as
`ssh hpc 'bash -lc "<cmd>"'`: a plain `ssh hpc '<cmd>'` has no `$VSC_DATA` or modules. The
scripts in `scripts/` run on the login node: sync this skill's `scripts/` folder with
`rsync -a <this skill>/scripts/ hpc:"$(ssh hpc 'bash -lc "echo \$VSC_DATA"')"/slurm-jobs/`
and call `$VSC_DATA/slurm-jobs/<script>` (each takes `-h`). SSH to the cluster drops out at
times: when it fails, say so and continue with whatever is local.

**Credits and the shared queue.** Pilots and campaigns spend the group's credits and occupy shared
GPUs. A job costs its Slurm billing weight × minutes run (`sam-balance` shows what is left,
`sam-quote sbatch <args> <script>` quotes a submission at its full `--time`). Show the plan with
its credit estimate and get the user's go-ahead before the pilot, and again before the full
submission.

## One job, not a campaign

For a single job or a handful (an interactive session, one training run, a quick test): run
`cluster-now` with the job's shape and `suggest-time` on its job name (steps 2 and 3), then write
the request directly, from [`templates/array.sbatch`](templates/array.sbatch) with
`--array=0-0` when the job should resume after a kill. Skip the plan file; still show the request
and its `sam-quote` and get the go-ahead before submitting. Once the work grows to many units or
several stages, switch to the steps below.

## Steps

### 1. Scope

List the work units, the command per unit, its inputs, and the **comparison groups**: the sets of
runs whose results or run times will be compared with each other (one table, one figure).
Done when every unit belongs to exactly one comparison group.

### 2. Read the cluster

Run `cluster-now`, with `-c <CPUs per GPU> -m <GB per GPU>` when the job's shape differs from the
defaults: fair-share per account
and cluster, and per GPU partition the GPUs free, the GPUs a job of that shape fits on now, the
GPUs held for a higher job, and the pending jobs. Run `sam-balance` for the credits left.
Check the facts in `reference/cluster.md` against `scontrol show config` when its date is more
than a month old. Done when you know, per candidate cluster and partition, the fair-share, the
current load and the walltime cap, and you know the credit balance.

### 3. Read history

For each kind of job, run `suggest-time '<job-name regex>' -M <cluster> --days 365`, and read the
project's own logs (`logs/`, `provenance.jsonl`, earlier campaign notes). A kind has **history**
when it has three or more completed runs over 2 minutes on comparable inputs. Done when every
kind is marked *history* (with its suggested `--time`/`--mem`) or *no history*.

### 4. Plan

Write the plan in the project as `slurm/<campaign>.md`: units, tasks, arrays, stages, requests,
the estimated GPU-hours or core-hours, and the credits: expected (from history or pilot) and
worst case (`sam-quote` per array), against the balance. Rules:

- **Task size**: pack units so one task runs about 30 min to 6 h. Shorter tasks pay scheduling
  overhead; longer ones fit fewer gaps. Stay under the walltime cap with margin; anything that
  needs longer gets checkpointing or a finer split.
- **Arrays**: one array per kind and comparison group, `--array=0-N%K`. All tasks count toward
  the 500-job limit, pending included; `%K` keeps the group's share of a partition polite.
- **Stages**: chain with `--dependency=afterok:<id>` only where a stage truly needs the earlier
  output. A dependent job gains no age while it waits, so submit late stages once they are close.
- **Placement**: see *Reproducibility* below; within that, pick the cluster with the higher
  fair-share and list every partition the job fits.
- **Restart**: units are idempotent (skip when output exists) so a killed task resumes;
  start from [`templates/array.sbatch`](templates/array.sbatch).

Done when the plan names every array with its request and the user has approved it.

### 5. Pilot (kinds with no history, or inputs much larger than before)

Submit a small slice before the campaign: the smallest, a median and the largest unit of each
kind, and, when the CPU or GPU count is open, the same unit at two or three shapes (e.g. 4, 8, 16
CPUs per GPU). Use `*_debug` partitions when the pilot fits in 1 h. Then
`suggest-time -M <cluster> --jobs <ids> --units <units per pilot> --scale <total units>` gives
time per unit, CPU efficiency, peak memory, credits, the cheapest shape within 1.25× of the
fastest, and the task split. `-M` is needed for jobs on a cluster other than the login node's
(mindwell from a wICE login). The suggested `--time` covers the slowest pilot; when it warns that
pilot times differ more than 4×, give the large units their own array.
Done when every kind has a completed pilot at each size class, or the failure is diagnosed;
then update the plan's requests and get the go-ahead for the full run.

### 6. Submit

Submit the arrays from the plan (`mkdir -p logs` first: Slurm needs the log folder before the
script starts), and record each job ID, its request and the time in the plan.
Done when `squeue -u $USER` shows every array and the plan lists every ID.

### 7. Watch and learn

- While pending: `squeue --start -j <id>` and `sprio -j <id>`. Re-placing a pending job
  (`scontrol update jobid=<id> partition=…` within a cluster; cancel and resubmit across clusters)
  is worth it when a partition that keeps the comparison group intact has free GPUs.
- After the run: `suggest-time -M <cluster> --jobs <ids>` per array, then in the campaign folder
  `remaining units.txt <PER_TASK>`: the tasks with units left and the `--array=` list to resubmit.
  Read `sacct -M <cluster> -j <id> -X -n -o JobID,State,ExitCode` for those tasks first. Exit
  code 75: stopped near its limit, resubmit as is, it resumes. Another exit code: a unit failed,
  read its log and fix it. TIMEOUT or OUT_OF_MEMORY: a finer split or a larger request.
- Write used vs asked per array into the plan: it is the next campaign's history.

Done when every task is completed or has a recorded decision, and the plan carries the numbers.

## Reproducibility

Different GPU types (H100, A100, V100, P100, B200) and CPU types differ in numerics (TF32,
bf16 support, kernel choices), memory and speed. Results, and run times above all, are comparable
only within one hardware type.

- Pin each comparison group to one partition (one GPU type). Spread across partitions only
  between comparison groups, never inside one.
- When a group must span types for throughput, balance it: give every type the same mix of
  methods, datasets and seeds (stratified, not first-come), and report the type per run.
- Every task records host, partition, GPU model, driver, CPU model and commit
  (`provenance.jsonl` in the template). Fix seeds per unit, not per task.
- Run-time comparisons (speed as a result) use one node type and an exclusive or same-shape
  request, or they measure the neighbours.
