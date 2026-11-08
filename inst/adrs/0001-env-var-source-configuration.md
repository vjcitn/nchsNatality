# 0001 — Environment variables for default data-source configuration

## Status
Proposed

## Context
Every function in the package today (`read_natality()`, `natality_sql()`,
`natality_pack()`, `diagnose_layout()`, `check_natality_file()`, ...) takes an
explicit `file` (or `out_dir`) argument. There is already a stub,
`nchs_nat_path()`, that reads `Sys.getenv("NCHS_NAT_PATH")`; it is used only in
`@examples` blocks and is not wired into any exported function's defaults.

The user wants two things to work from environment configuration alone,
without a path argument at every call site:

* (a) the raw fixed-width text file, when `NCHS_NAT_PATH` is set;
* (b) a sharded Parquet directory (as written by `natality_pack()`), when
  `NCHS_NAT_PARQUET` is set, used in preference to (a) for queries (see
  [0002](0002-parquet-before-text-resolution.md)).

## Decision
Introduce a second accessor, `nchs_nat_parquet_dir()`, symmetric with the
existing `nchs_nat_path()`:

```r
nchs_nat_path        <- function() Sys.getenv("NCHS_NAT_PATH")
nchs_nat_parquet_dir <- function() Sys.getenv("NCHS_NAT_PARQUET")
```

Functions that currently require `file` gain `file = NULL` (and, where
relevant, an analogous `parquet_dir = NULL`), resolved **at call time** via a
single internal resolver (see 0002), not cached at package load. This means:

* changing the env var mid-session (or per-`testthat::local_envvar()` test)
  takes effect on the next call, with no package reload;
* an explicit `file =` argument always overrides the environment, so every
  existing call site in the current test suite and any user scripts keeps
  working unchanged.

Package options (`options(nchsNatality.path = ...)`) were considered and
rejected: env vars already have precedent in this package
(`nchs_nat_path()`), and they are the natural fit for the batch/cluster
workflows this package targets (one file per job, set once in the job
environment) versus interactive `options()` calls that do not propagate to
child R processes.

## Consequences
* New public function `nchs_nat_parquet_dir()`.
* `read_natality()` (and friends) must distinguish "argument omitted" from
  "argument explicitly `NULL`"; using `NULL` as the sentinel for "resolve from
  environment" is consistent with existing optional-argument conventions in
  the package (e.g. `cols = NULL` already means "all fields").
