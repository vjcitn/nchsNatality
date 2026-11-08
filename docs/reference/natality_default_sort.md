# Default row order for natality_pack()

Reporting flags first: they are constant within a reporting area, so
sorting on them groups records in state-like blocks. Then a few
low-cardinality fields. Sorting changes only how well the data compress,
never the content.

## Usage

``` r
natality_default_sort(storage)
```

## Arguments

- storage:

  A storage table, as written to `storage.csv` by
  [`natality_pack()`](https://github.com/vjcitn/nchsNatality/reference/natality_pack.md).

## Value

Character vector of column names.
