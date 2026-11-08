# Pack a natality file into compact, lossless, sharded Parquet

Profiles every record, writes one Parquet file per value of `shard_by`,
and then checks that the original records can be rebuilt exactly from
the shards (see
[`natality_verify()`](https://github.com/vjcitn/nchsNatality/reference/natality_verify.md)).

## Usage

``` r
natality_pack(
  file,
  out_dir,
  shard_by = "DOB_MM",
  level = 22L,
  row_group_size = 1e+06,
  sort_by = NULL,
  int_codes = FALSE,
  parquet_version = c("V1", "V2"),
  max_mb = 95,
  verify = TRUE,
  record_length = NULL,
  memory_limit = "8GB",
  year = 2025
)
```

## Arguments

- file:

  Path to the fixed-width natality file.

- out_dir:

  Directory for the shards and `storage.csv`. Its base name is used as
  the stem of the shard file names.

- shard_by:

  Field to shard on. The default, birth month, gives 12 files (plus one
  for blank months, if any). `NULL` writes a single file.

- level:

  zstd compression level, 1-22. High levels are slow to write but not
  slower to read.

- row_group_size:

  Rows per Parquet row group.

- sort_by:

  Columns to sort rows by within each shard. `NULL` uses
  [`natality_default_sort()`](https://github.com/vjcitn/nchsNatality/reference/natality_default_sort.md);
  `character(0)` means no sorting.

- int_codes:

  Also store digit-only categorical codes (e.g. MEDUC, MRACE15) as
  integers. `FALSE` keeps them as the character codes that
  [`label_natality()`](https://github.com/vjcitn/nchsNatality/reference/label_natality.md)
  expects.

- parquet_version:

  `"V1"` (most widely readable) or `"V2"`.

- max_mb:

  Warn if any shard is larger than this many MiB.

- verify:

  Run
  [`natality_verify()`](https://github.com/vjcitn/nchsNatality/reference/natality_verify.md)
  after writing.

- record_length:

  Record length of the file, excluding line endings. `NULL` detects it
  from the first 10,000 records; every record must then have that
  length.

- memory_limit:

  DuckDB memory limit, e.g. `"8GB"`.

- year:

  Data year; see
  [`natality_years()`](https://github.com/vjcitn/nchsNatality/reference/natality_years.md).

## Value

Invisibly, a list with `storage` (the storage table), `report` (from
[`natality_report()`](https://github.com/vjcitn/nchsNatality/reference/natality_report.md))
and `verified` (`TRUE`, `FALSE`, or `NA` if not run).

## How fields are stored

The storage of each field is decided from the data, not assumed from the
guide:

- `int`: digits only, zero-padded to full width. Stored as the smallest
  integer type that fits; rebuilt by padding with `0`. Used for numeric
  fields, and for digit-only codes too if `int_codes = TRUE`.

- `left`: no leading blanks. Stored as trimmed text; rebuilt by padding
  on the right.

- `right`: no trailing blanks. Stored as trimmed text; rebuilt by
  padding on the left.

- `raw`: anything else. Stored untrimmed.

- `blank`: a FILLER that is blank in every record. Not stored.

A blank field is stored as `NULL`. The rules are written to
`<out_dir>/storage.csv`, which
[`natality_verify()`](https://github.com/vjcitn/nchsNatality/reference/natality_verify.md)
and
[`natality_unpack()`](https://github.com/vjcitn/nchsNatality/reference/natality_unpack.md)
need, so keep it with the shards. Numeric fields keep their sentinel
codes (DBWT 9999, CIG_0 99, ...); turn them into `NA` when analysing.

Bytes beyond the record length the guide documents (1330 for 2025) are
kept as a trailing column, `FILLER_1331`, unless they are blank in every
record.

## What is not kept

Record order (rows are sorted so that they compress better) and line
endings. The check compares the source and the rebuilt records as
multisets.

## File size

GitHub blocks files over 100 MiB and warns at 50 MiB, so `max_mb`
defaults to 95.

## Examples

``` r
if (FALSE) { # \dontrun{
res <- natality_pack("Nat2025PublicUS.c20260624.r20260922.txt", "nat2025")
res$report
arrow::open_dataset("nat2025")
} # }
```
