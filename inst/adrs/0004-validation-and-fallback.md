# 0004 — Validation, staleness and fallback behavior

## Status
Proposed

## Context
A directory named by `NCHS_NAT_PARQUET` can be: absent, empty, mid-write from
a concurrent `natality_pack()` run, missing `storage.csv`, or simply stale
relative to whatever `NCHS_NAT_PATH` now points to (re-packed from a different
file, a different year's layout, or not re-packed after the source file
changed). Because this package's entire purpose is losslessness, silently
serving wrong-but-plausible data from a stale Parquet directory is worse than
refusing to run.

## Decision
**Structural validity check** (cheap, run on every resolution per
[0002](0002-parquet-before-text-resolution.md)):
a directory counts as a usable Parquet source only if `storage.csv` exists and
parses, **and** at least one `*.parquet` file exists alongside it. Either
condition failing is a hard error naming the missing piece — not a silent
fallback to `NCHS_NAT_PATH` — because a half-written or misconfigured Parquet
directory is far more likely to be a mistake worth surfacing than a deliberate
choice to fall back.

**No implicit content cross-check against the text file.** The resolver does
*not* compare the Parquet directory's content or modification time against
`NCHS_NAT_PATH` by default: doing so would mean scanning the (large) text file
on every query just to validate it, which defeats the performance reason for
having Parquet shards at all. This tradeoff is documented prominently on the
resolver's (and `read_natality()`'s) help page: *the package trusts that a
configured Parquet directory matches the intended source; re-run
`natality_pack()` after the source file changes.*

**Verification remains explicit and opt-in.** `natality_verify()` already
exists and already runs by default inside `natality_pack()`
(`verify = TRUE`). Nothing here implicitly calls it on the query path; a user
who wants a one-time confirmation that a given Parquet directory matches a
given text file runs `natality_verify(file, parquet_dir)` themselves.

**No automatic fallback flag in this iteration.** An opt-in
`fallback = TRUE` on the resolver (silently drop to text if Parquet fails
structural validation) was considered and deferred: it's easy to add later
without breaking the default (fail-loud) behavior, and adding it now without
a concrete use case would be speculative.

## Consequences
* Query functions fail fast and specifically ("no storage.csv in <dir>", "no
  *.parquet files in <dir>") rather than falling through to a possibly
  wrong-year text file.
* Staleness is a documented caller responsibility, not a runtime guarantee;
  this is a conscious performance/correctness tradeoff, not an oversight.
* Tests should cover: missing dir, dir with `storage.csv` but no shards, dir
  with shards but no `storage.csv`, and the happy path — each resolved the
  way this ADR specifies.
