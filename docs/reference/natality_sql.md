# SQL that reads natality records in DuckDB

Returns a `SELECT` statement that slices fields out of each record in
DuckDB, without loading the file into R. Values are trimmed text, with
blank fields as `NULL`.

## Usage

``` r
natality_sql(file, cols = NULL, year = 2025)
```

## Arguments

- file:

  Path to the fixed-width natality file.

- cols:

  Field names to select; default all non-filler fields.

- year:

  Data year; see
  [`natality_years()`](https://github.com/vjcitn/nchsNatality/reference/natality_years.md).

## Value

A character string of SQL.

## Examples

``` r
cat(natality_sql("Nat2025PublicUS.txt", c("DOB_MM", "DBWT")))
#> SELECT
#>   nullif(trim(substr(line, 13, 2)), '') AS "DOB_MM",
#>   nullif(trim(substr(line, 504, 4)), '') AS "DBWT"
#> FROM read_csv('Nat2025PublicUS.txt', columns = {'line': 'VARCHAR'}, header = false, delim = chr(1), quote = '', escape = '', auto_detect = false)
if (FALSE) { # \dontrun{
con <- DBI::dbConnect(duckdb::duckdb())
DBI::dbGetQuery(con, paste("SELECT DOB_MM, avg(CAST(DBWT AS INT)) FROM (",
                           natality_sql(f), ") GROUP BY 1"))
} # }
```
