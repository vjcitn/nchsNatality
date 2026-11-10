# Value labels of the natality public-use file

Value labels of the natality public-use file

## Usage

``` r
natality_values(year = 2025)
```

## Source

The underlying public-use file is downloaded from NCHS at
<https://www.cdc.gov/nchs/data_access/vitalstatsonline.htm#Downloadable>;
these value labels describe its codes and are not themselves downloaded
from there.

## Arguments

- year:

  Data year; see
  [`natality_years()`](https://github.com/vjcitn/nchsNatality/reference/natality_years.md).

## Value

A `data.table` with columns `name`, `code`, `label` and `block`. `block`
1 is the coding for US records. `block` 2 is the separate coding for
Puerto Rico and the territories, where the guide gives one (RESTATUS,
DMAR). Codes such as `"0227-8165"` are documented ranges of a numeric
field.

## Examples

``` r
v <- natality_values()
v[name == "SEX"]
#>      name   code  label block
#>    <char> <char> <char> <int>
#> 1:    SEX      M   Male     1
#> 2:    SEX      F Female     1
```
