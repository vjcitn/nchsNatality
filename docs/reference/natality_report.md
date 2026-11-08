# Sizes of the Parquet shards

Sizes of the Parquet shards

## Usage

``` r
natality_report(out_dir, file = NULL)
```

## Arguments

- out_dir:

  Directory written by
  [`natality_pack()`](https://github.com/vjcitn/nchsNatality/reference/natality_pack.md).

- file:

  Optional source file, to report the compression ratio.

## Value

A `data.table` with `file` and `mb` (MiB). A summary is shown as a
message.
