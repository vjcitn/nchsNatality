# Record layout of the natality public-use file

One row per field, including the FILLER blocks, in record order.

## Usage

``` r
natality_layout(year = 2025, record_length = NULL)
```

## Source

The underlying public-use file is downloaded from NCHS at
<https://www.cdc.gov/nchs/data_access/vitalstatsonline.htm#Downloadable>;
this layout describes its byte positions and is not itself downloaded
from there.

## Arguments

- year:

  Data year; see
  [`natality_years()`](https://github.com/vjcitn/nchsNatality/reference/natality_years.md).

- record_length:

  Actual record length of the file, if it differs from the length the
  User Guide gives (1330 for 2025). Extra bytes at the end are added as
  a trailing `FILLER`, so that
  [`natality_pack()`](https://github.com/vjcitn/nchsNatality/reference/natality_pack.md)
  keeps them. `NULL` (the default) uses the documented length.

## Value

A `data.table` with columns `start`, `end`, `width`, `name`, `group`,
`description`, `kind` (`"numeric"`, `"code"` or `"filler"`) and `col`, a
unique column name (`FILLER_<start>` for fillers, the field name
otherwise).

## Examples

``` r
lay <- natality_layout()
lay[name == "DBWT"]
#>    start   end width   name  group                             description
#>    <int> <int> <int> <char> <char>                                  <char>
#> 1:   504   507     4   DBWT        Birth Weight – Detail in Grams (Edited)
#>       kind    col
#>     <char> <char>
#> 1: numeric   DBWT
tail(natality_layout(record_length = 1345), 2)
#>    start   end width   name  group
#>    <int> <int> <int> <char> <char>
#> 1:   571  1330   760 FILLER       
#> 2:  1331  1345    15 FILLER       
#>                                               description   kind         col
#>                                                    <char> <char>      <char>
#> 1:                                                 Filler filler  FILLER_571
#> 2: Bytes beyond the record length given in the User Guide filler FILLER_1331
```
