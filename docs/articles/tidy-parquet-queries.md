# Tidy queries against a packed Parquet resource

This vignette assumes `NCHS_NAT_PARQUET` is set, on the machine running
it, to a sharded Parquet directory written by \[natality_pack()\] – see
`vignette("nchsNatality")` (or `inst/adrs/`) for how that directory
relates to `NCHS_NAT_PATH` and the raw fixed-width file it was packed
from.

``` r

library(nchsNatality)

parquet_dir <- nchs_nat_parquet_dir()
## the same structural check read_natality() itself uses to decide whether
## NCHS_NAT_PARQUET is usable -- see inst/adrs/0004-validation-and-fallback.md
have_parquet <- nzchar(parquet_dir) && nchsNatality:::.valid_parquet_dir(parquet_dir)
knitr::opts_chunk$set(eval = have_parquet)
```

`NCHS_NAT_PARQUET` is set to a valid directory on this machine
(`/Users/vincentcarey/HSPH_2026/BIRTH/NATAL/nchsNat2026.shparq`); the
rest of this vignette runs against it.

``` r

library(dplyr)
#> 
#> Attaching package: 'dplyr'
#> The following objects are masked from 'package:stats':
#> 
#>     filter, lag
#> The following objects are masked from 'package:base':
#> 
#>     intersect, setdiff, setequal, union
```

## 1. `read_natality()` resolves to Parquet automatically

With `NCHS_NAT_PARQUET` set,
[`read_natality()`](https://github.com/vjcitn/nchsNatality/reference/read_natality.md)
needs no `file` argument at all – it queries the shards via DuckDB
instead of scanning the fixed-width text, and the result is the same
`data.table` shape either way (see
[`?read_natality`](https://github.com/vjcitn/nchsNatality/reference/read_natality.md)).

``` r

dt <- read_natality(cols = c("DOB_MM", "MAGER", "SEX", "COMBGEST", "DBWT"))
#> duckdb is storing downloaded extensions and secrets under ~/.duckdb:
#> ℹ /Users/vincentcarey/.duckdb
#> This persists across sessions and is shared with the DuckDB CLI and other clients.
#> ℹ Run duckdb(shared_home = FALSE) to use a temporary directory instead.
#> ℹ See ?duckdb_storage for details and alternatives.
nrow(dt)
#> [1] 3619990
```

A `data.table` is also a `data.frame`, so ordinary dplyr verbs work on
it directly once it is in memory:

``` r

dt |>
  label_natality(cols = "SEX") |>
  filter(!is.na(DBWT), !is.na(COMBGEST)) |>
  group_by(SEX) |>
  summarise(n = n(), mean_dbwt = mean(DBWT), mean_gestation = mean(COMBGEST))
#> # A tibble: 2 × 4
#>   SEX          n mean_dbwt mean_gestation
#>   <fct>    <int>     <dbl>          <dbl>
#> 1 Male   1846980     3304.           38.5
#> 2 Female 1767632     3191.           38.6
```

## 2. Tidy queries that never materialize the full resource

[`read_natality()`](https://github.com/vjcitn/nchsNatality/reference/read_natality.md)
is convenient, but it still pulls the requested columns for every record
into memory. For an aggregate over the *whole* resource – all shards,
all records – it is more efficient to let dplyr push the
filter/group-by/summarise down to the Parquet files themselves, via
\[arrow::open_dataset()\], and only pull back the (small) aggregated
result with
[`collect()`](https://dplyr.tidyverse.org/reference/compute.html).

``` r

library(arrow)
#> 
#> Attaching package: 'arrow'
#> The following object is masked from 'package:utils':
#> 
#>     timestamp

## name the shards explicitly -- the directory also holds storage.csv,
## which open_dataset() would otherwise try to read as data
nat <- open_dataset(Sys.glob(file.path(parquet_dir, "*.parquet")))
nat
#> FileSystemDataset with 12 Parquet files
#> 236 columns
#> DOB_YY: int16 not null
#> DOB_MM: string not null
#> DOB_TT: int16 not null
#> DOB_WK: string not null
#> BFACIL: string not null
#> F_BFACIL: string not null
#> BFACIL3: string not null
#> MAGE_IMPFLG: string
#> MAGE_REPFLG: string
#> MAGER: int8 not null
#> MAGER14: string not null
#> MAGER9: string not null
#> MBSTATE_REC: string not null
#> RESTATUS: string not null
#> MRACE31: string not null
#> MRACE6: string not null
#> MRACE15: string not null
#> MRACEIMP: string
#> MHISPX: string not null
#> MHISP_R: string not null
#> ...
#> 216 more columns
#> Use `schema()` to see entire schema
```

``` r

by_month <- nat |>
  filter(DBWT != 9999) |>              # NCHS sentinel for "not stated"
  group_by(DOB_MM) |>
  summarise(n = n(), mean_dbwt = mean(DBWT)) |>
  arrange(DOB_MM) |>
  collect()

by_month
#> # A tibble: 12 × 3
#>    DOB_MM      n mean_dbwt
#>    <chr>   <int>     <dbl>
#>  1 01     304229     3234.
#>  2 02     275592     3239.
#>  3 03     298088     3243.
#>  4 04     289988     3248.
#>  5 05     304363     3246.
#>  6 06     298694     3252.
#>  7 07     322059     3255.
#>  8 08     319832     3256.
#>  9 09     310372     3262.
#> 10 10     306411     3252.
#> 11 11     281119     3246.
#> 12 12     305543     3244.
```

`by_month` is an ordinary tibble; everything up to
[`collect()`](https://dplyr.tidyverse.org/reference/compute.html) ran
against the Parquet shards, not against an in-memory copy of the whole
file.

## 3. Combining the two

A common pattern: scan the resource for a filtered, aggregated slice
with `arrow`/`dplyr`, then relabel the few columns that matter for a
figure or table with \[label_natality()\].

``` r

by_sex <- nat |>
  filter(DBWT != 9999) |>
  group_by(SEX, DPLURAL) |>
  summarise(n = n(), mean_dbwt = mean(DBWT), mean_age = mean(MAGER)) |>
  collect() |>
  label_natality(cols = c("SEX", "DPLURAL"))

by_sex
#>       SEX              DPLURAL       n mean_dbwt mean_age
#>    <fctr>               <fctr>   <int>     <num>    <num>
#> 1:   Male               Single 1792876  3331.444 29.76765
#> 2: Female               Single 1713795  3219.471 29.78585
#> 3: Female                 Twin   53488  2298.535 30.72886
#> 4:   Male                 Twin   53795  2405.413 30.71497
#> 5: Female              Triplet    1132  1630.149 31.44700
#> 6:   Male              Triplet    1100  1662.736 31.63636
#> 7: Female Quadruplet or higher      50  1544.060 31.20000
#> 8:   Male Quadruplet or higher      54  1467.389 31.81481
```
