# Check that Parquet shards rebuild the source records exactly

Rebuilds every record from the shards and compares the result with the
source file using order-independent hashes of all records (a count, a
sum and an xor of 64-bit hashes, and a sum of hashes of MD5 digests).

## Usage

``` r
natality_verify(file, out_dir, con = NULL)
```

## Arguments

- file:

  Path to the source fixed-width file.

- out_dir:

  Directory written by
  [`natality_pack()`](https://github.com/vjcitn/nchsNatality/reference/natality_pack.md).

- con:

  Optional open DuckDB connection.

## Value

`TRUE` if the two sets of records are identical, else `FALSE`.
