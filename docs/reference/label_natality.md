# Turn categorical codes into labelled factors

Turn categorical codes into labelled factors

## Usage

``` r
label_natality(dt, cols = NULL, territory = FALSE, year = 2025)
```

## Arguments

- dt:

  A `data.table` from
  [`read_natality()`](https://github.com/vjcitn/nchsNatality/reference/read_natality.md).

- cols:

  Fields to label; the default is every categorical field in `dt`.

- territory:

  If `TRUE`, use the Puerto Rico / territory coding (block 2 of
  [`natality_values()`](https://github.com/vjcitn/nchsNatality/reference/natality_values.md))
  where the guide gives one (RESTATUS, DMAR). If `FALSE`, use the US
  coding.

- year:

  Data year; see
  [`natality_years()`](https://github.com/vjcitn/nchsNatality/reference/natality_years.md).

## Value

A copy of `dt` with those columns as factors. A field whose codes
include `"Blank"` maps `NA` to that label (e.g. MAGE_IMPFLG "Age not
imputed"). Codes in the data that the guide does not list become levels
of their own, unchanged.

## Examples

``` r
dt <- data.table::data.table(SEX = c("M", "F"), MAGE_IMPFLG = c(NA, "1"))
label_natality(dt)
#>       SEX     MAGE_IMPFLG
#>    <fctr>          <fctr>
#> 1:   Male Age not imputed
#> 2: Female     Age imputed
```
