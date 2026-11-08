# 0002 — Resolution precedence: parquet before text

## Status
Proposed

## Context
A natality text file is ~1.3–1.4 KB/record, no delimiters; reading it means
either `vroom_fwf()` over every requested byte range, or DuckDB's
`read_csv(..., delim = chr(1))` trick in `natality_sql()`/`parquet.R`. A
sharded, zstd-compressed, columnar Parquet directory written by
`natality_pack()` is both smaller on disk and far cheaper to query (column
pruning, row-group stats, no per-record string slicing). When both a source
text file and a packed Parquet directory are available, the Parquet directory
should be used for queries whenever present — that is the entire point of
having packed it.

## Decision
Define one internal resolver, `.natality_source(file = NULL, parquet_dir = NULL,
require = NULL)`, used by every function that needs "the" default natality
source. Its precedence, evaluated fresh on each call:

1. If `parquet_dir` (explicit arg or `NCHS_NAT_PARQUET`) is set **and** it
   passes the validity check in [0004](0004-validation-and-fallback.md) →
   resolve to `list(kind = "parquet", path = parquet_dir)`.
2. Else if `file` (explicit arg or `NCHS_NAT_PATH`) is set **and**
   `file.exists(file)` → resolve to `list(kind = "text", path = file)`.
3. Else `stop()`, naming both `NCHS_NAT_PATH` and `NCHS_NAT_PARQUET` in the
   message so the user knows both options.

An explicit `file =` argument passed by the caller is never silently
overridden by a Parquet directory found via the environment: resolution only
consults `NCHS_NAT_PARQUET` when the caller did not pin a source explicitly.
Put differently, per-call arguments outrank environment variables, and among
environment variables, Parquet outranks text.

`require` lets a caller that only makes sense for one backend
(`natality_pack()`, which produces Parquet, has no use resolving to an
existing Parquet dir as its *input*) force `kind = "text"` and get the
ordinary "no text source configured" error if only a Parquet dir is set.

## Consequences
* Users who set only `NCHS_NAT_PATH` see no behavior change.
* Users who set `NCHS_NAT_PARQUET` (with or without `NCHS_NAT_PATH` also set)
  get Parquet-backed queries automatically, with no per-call flag.
* Functions whose contract is inherently about the text file
  (`check_natality_file()`, `diagnose_layout()`, which inspect raw bytes/line
  endings) are explicitly out of scope for this resolver and keep requiring
  `file` — see [0003](0003-dual-backend-common-contract.md) for which
  functions are in scope.
