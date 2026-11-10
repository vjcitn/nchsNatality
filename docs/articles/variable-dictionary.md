# Variable dictionary

This vignette lists every field in the natality public-use file record
layout – its description, byte width and type – together with the value
labels for every coded field. Both tables come from
\[natality_layout()\] and \[natality_values()\] and need no external
resource (`NCHS_NAT_PATH` / `NCHS_NAT_PARQUET`) to build.

``` r

library(nchsNatality)
library(data.table)
#> 
#> Attaching package: 'data.table'
#> The following object is masked from 'package:base':
#> 
#>     %notin%
```

## Fields

One row per field that is actually readable (the `FILLER` blocks that
pad out unused bytes are omitted). `kind` is `"numeric"` for fields read
as numbers and `"code"` for fields whose values are a fixed set of
labelled codes – see the [Value labels](#value-labels) table below for
those.

``` r

fields <- natality_layout()[kind != "filler",
                             .(name, description, kind, width)]

if (have_dt) {
  DT::datatable(fields, rownames = FALSE, filter = "top",
                 options = list(pageLength = 15))
} else {
  knitr::kable(fields)
}
```

## Value labels

Every documented code and its label, for every coded field (`block` 1 is
the coding used for US records; `block` 2, where present, is the
separate coding for Puerto Rico and the other territories – see
[`?natality_values`](https://github.com/vjcitn/nchsNatality/reference/natality_values.md)).
Numeric fields have no entry here; their sentinel/“unknown” codes, where
documented, are also listed in this table (e.g. `DBWT` 9999).

``` r

values <- natality_values()

if (have_dt) {
  DT::datatable(values, rownames = FALSE, filter = "top",
                 options = list(pageLength = 15))
} else {
  knitr::kable(values)
}
```
