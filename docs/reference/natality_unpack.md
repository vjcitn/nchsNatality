# Rebuild the fixed-width file from Parquet shards

Rebuild the fixed-width file from Parquet shards

## Usage

``` r
natality_unpack(out_dir, outfile)
```

## Arguments

- out_dir:

  Directory written by
  [`natality_pack()`](https://github.com/vjcitn/nchsNatality/reference/natality_pack.md).

- outfile:

  Path of the fixed-width file to write (LF line endings). Records come
  out in shard order, not the original order.

## Value

`outfile`, invisibly.
