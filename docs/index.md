# nchsNatality

**Read and losslessly pack NCHS natality public-use files.**

The [NCHS natality public-use
file](https://www.cdc.gov/nchs/data_access/vitalstatsonline.htm) is a
fixed-width text file — one record per birth, no delimiters, no quoting.
That defeats delimiter-sniffing readers such as
[`data.table::fread()`](https://rdrr.io/pkg/data.table/man/fread.html).
`nchsNatality` reads the file by byte position from the official record
layout, optionally converts it to compact, lossless sharded Parquet (via
DuckDB), and round-trips it back to fixed-width for verification.

## Installation

``` r

# from GitHub
remotes::install_github("vjcitn/nchsNatality")

# or from a local source checkout
devtools::install("path/to/nchsNatality")
```

**Runtime dependencies**: `data.table`, `vroom`.  
**Parquet functions** additionally require `duckdb` \>= 1.1.0 and `DBI`.

## Quick start

``` r

library(nchsNatality)

f <- "Nat2025PublicUS.c20260624.r20260922.txt"

# 1. Sanity-check the file
check_natality_file(f)
#> terminator: CRLF; record length(s) in first 100000 bytes: 1345
#> (guide documents 1330); '"' bytes: 0

# 2. Read selected fields into a data.table
dt <- read_natality(f, cols = c("MAGER", "DBWT", "COMBGEST", "SEX", "DOB_MM"))

# 3. Attach value labels (turns character codes into factors)
dt <- label_natality(dt)

# 4. Pack to sharded Parquet (requires duckdb)
natality_pack(f, out_dir = "nat_parquet/")
#> Packing 12 shards (DOB_MM 01–12) …
#> Verifying … OK

# 5. Query the Parquet directly with duckdb (no unpacking needed)
con <- DBI::dbConnect(duckdb::duckdb())
DBI::dbExecute(con, "CREATE VIEW nat AS SELECT * FROM 'nat_parquet/*.parquet'")
DBI::dbGetQuery(con, "SELECT SEX, COUNT(*) n FROM nat GROUP BY SEX")

# 6. Unpack to a fresh fixed-width file
natality_unpack("nat_parquet/", "Nat2025_copy.txt")
```

## Functions

| Function | Purpose |
|----|----|
| [`check_natality_file()`](https://github.com/vjcitn/nchsNatality/reference/check_natality_file.md) | Report line endings and record length |
| [`diagnose_layout()`](https://github.com/vjcitn/nchsNatality/reference/diagnose_layout.md) | Check documented field positions against the file |
| [`read_natality()`](https://github.com/vjcitn/nchsNatality/reference/read_natality.md) | Read fields into a `data.table`, typed or raw |
| [`label_natality()`](https://github.com/vjcitn/nchsNatality/reference/label_natality.md) | Convert categorical codes to labelled factors |
| [`natality_pack()`](https://github.com/vjcitn/nchsNatality/reference/natality_pack.md) | Write sharded Parquet; optionally verify losslessness |
| [`natality_verify()`](https://github.com/vjcitn/nchsNatality/reference/natality_verify.md) | Verify an existing Parquet directory against the source file |
| [`natality_unpack()`](https://github.com/vjcitn/nchsNatality/reference/natality_unpack.md) | Reconstruct the fixed-width file from Parquet |
| [`natality_layout()`](https://github.com/vjcitn/nchsNatality/reference/natality_layout.md) | Return the record layout as a `data.table` |
| [`natality_values()`](https://github.com/vjcitn/nchsNatality/reference/natality_values.md) | Return value labels as a `data.table` |
| [`natality_years()`](https://github.com/vjcitn/nchsNatality/reference/natality_years.md) | List years for which a layout is bundled |

## Record-layout notes (2025 file)

The User Guide documents a 1330-byte record. The 2025 public release
(`Nat2025PublicUS.c20260624.r20260922.txt`) has 1345-byte records with
CRLF line endings; bytes 1331–1345 are beyond the documented layout.
[`check_natality_file()`](https://github.com/vjcitn/nchsNatality/reference/check_natality_file.md)
reports this automatically.
[`natality_pack()`](https://github.com/vjcitn/nchsNatality/reference/natality_pack.md)
detects the actual record length and keeps the extra bytes as a trailing
`FILLER_1331` column, so no data are lost.

The guide has a few typographic errors; `data-raw/parse_userguide.py`
lists all corrections made when the layout and value-label CSVs were
generated.

## GitHub size limits

One year of sharded Parquet at compression level 22 is roughly 500 MB to
1 GB (actual size depends on data). That is too large for a GitHub
repository (100 MiB hard limit per file; 1 GB soft limit per repo).
Options:

- **GitHub Releases** – release assets can be up to 2 GB each.
- **Git LFS** – transparent large-file storage; free tier 1 GB.
- **Zenodo / OSF / AWS S3** – for public archival distribution.

## Legal

The NCHS natality public-use file is a US government work. Review the
[NCHS data-use
agreement](https://www.cdc.gov/nchs/data_access/restrictions.htm) before
redistributing any derived file.

## Licence

Artistic-2.0
