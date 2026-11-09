# 0003 — Dual backend pipelines behind one output contract

## Status
Proposed

## Context
The package already has two independent, separately tested pipelines:

* `read.R`: `vroom_fwf()` over byte positions from `natality_layout()`, with
  R-side numeric typing and sentinel-to-`NA` conversion
  (`read_natality()`/`label_natality()`).
* `parquet.R`: a DuckDB pipeline whose column set, types and trim rules are
  decided *from the data* at pack time and recorded in `storage.csv` (the
  `rule`/`type`/`col` columns) — not derived from `natality_layout()` alone,
  because packing adapts to whatever record length and content a given file
  actually has (e.g. the `FILLER_1331` trailing-bytes column).

Satisfying the resolution order in [0002](0002-parquet-before-text-resolution.md)
for query-shaped functions (principally `read_natality()`) means a caller
asking for `cols = c("MAGER", "DBWT")` must get the same shaped answer
(data.table, same column names/types, same sentinel-NA semantics) whether the
request was served from text or from Parquet shards.

## Decision
Do **not** unify the two pipelines onto a single engine in this iteration.
Instead:

* `read_natality()` gains `file = NULL`; when resolution (0002) says
  `kind == "text"`, it calls the existing, unchanged vroom pipeline.
* When resolution says `kind == "parquet"`, a new internal
  `.read_natality_parquet(parquet_dir, cols, n_max, raw, na_unknown, year)`
  queries the shards directly with DuckDB (`SELECT <cols> FROM
  read_parquet('<dir>/*.parquet')`), using `storage.csv`'s `col` to find each
  requested field (erroring the same way as `read_natality()` does today for
  an unknown field name) and reusing a **shared** helper for the
  numeric-typing / `na_unknown` sentinel logic that `read_natality()` already
  has, factored out so both pipelines call the same code rather than keeping
  two independent copies of that logic in sync by hand.
* `natality_sql()` keeps its existing, tested, text-only contract (it
  documents and tests `substr(line, ...)` SQL over a raw file). It is not
  overloaded to also mean "query Parquet"; a Parquet-querying counterpart is
  additive, not a change to `natality_sql()`'s behavior or tests.

Rejected alternative: route the text case through DuckDB too (so one query
engine serves both backends uniformly). This would require re-deriving and
re-validating `read_natality()`'s existing sentinel/typing behavior, which is
exactly the logic this package's test suite is built to protect, for no
benefit beyond code-path uniformity. Revisit only if the two pipelines'
behavior drifts in practice.

Rejected alternative: make the backend an explicit user-facing argument
(`read_natality(..., backend = "parquet")`) instead of resolving silently from
the environment. Rejected because it does not satisfy the request ("if a
Parquet serialization is found... it is used") and reintroduces a per-call
parameter that the whole point of 0001's env-var design is to avoid. Can be
added later as an escape hatch without conflicting with this ADR.

## Consequences
* Two code paths to maintain, but each stays close to its current,
  already-tested shape.
* A shared "apply numeric typing + sentinel NA" helper must be extracted from
  `read_natality()`'s current body so both pipelines call one implementation.
* Tests must cover the same `read_natality()` behaviors (typed numerics, BMI
  as double, `na_unknown`, unknown-field error) against *both* a text fixture
  and a Parquet fixture built from it with `natality_pack()`, to guarantee the
  contract actually matches, not just "looks similar by inspection."
