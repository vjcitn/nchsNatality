# nchsNatality

**Read and losslessly pack NCHS natality public-use files.**

The [NCHS natality public-use file](https://www.cdc.gov/nchs/data_access/vitalstatsonline.htm#Downloadable)
is a fixed-width text file — one record per birth, no delimiters, no quoting.
That defeats delimiter-sniffing readers such as `data.table::fread()`.
`nchsNatality` reads the file by byte position from the official record layout,
optionally converts it to compact, lossless sharded Parquet (via DuckDB), and
round-trips it back to fixed-width for verification.

## Installation

```r
# from GitHub
remotes::install_github("vjcitn/nchsNatality")

# or from a local source checkout
devtools::install("path/to/nchsNatality")
```

**Runtime dependencies**: `data.table`, `vroom`.  
**Parquet functions** additionally require `duckdb` >= 1.1.0 and `DBI`.

## Workflow

The package assumes you obtain the data yourself and then convert it once to
Parquet; everything downstream (your own analysis, and any analysis script
you share with others) reads from that Parquet directory, not from the
original download.

1. **Read the data-use agreement.** Before downloading anything, read the
   terms at
   <https://www.cdc.gov/nchs/data_access/vitalstatsonline.htm#Downloadable>
   (and see [Legal](#legal) below).

2. **Download and unzip the file.** At that same URL, download the "U.S.
   Data" natality file for the year you want (2025 is the year this package
   currently bundles a layout for; see `natality_years()`) and unzip it to
   get the fixed-width `.txt` file.

   ```r
   library(nchsNatality)
   f <- "Nat2025PublicUS.c20260624.r20260922.txt"
   check_natality_file(f)   # sanity-check line endings / record length
   ```

3. **Pack it to sharded Parquet.** This is a one-time, lossless conversion
   (verified by `natality_pack()` itself) to a directory of compressed
   shards that every later step queries directly:

   ```r
   natality_pack(f, out_dir = "/path/to/nat_parquet")
   #> Packing 12 shards (DOB_MM 01–12) …
   #> Verifying … OK
   ```

4. **Point the package at that directory.** Either set an environment
   variable visible to R (e.g. in `.Renviron`), so every call resolves it
   automatically:

   ```r
   Sys.setenv(NCHS_NAT_PARQUET = "/path/to/nat_parquet")
   dt <- read_natality(cols = c("MAGER", "DBWT", "COMBGEST", "SEX", "DOB_MM"))
   ```

   or pass the location explicitly to a single call, without setting the
   environment variable:

   ```r
   dt <- read_natality(parquet_dir = "/path/to/nat_parquet",
                        cols = c("MAGER", "DBWT", "COMBGEST", "SEX", "DOB_MM"))
   ```

5. **Analyze.** For pure data manipulation, query the shards directly with
   SQL via DuckDB:

   ```r
   con <- DBI::dbConnect(duckdb::duckdb())
   DBI::dbExecute(con, "CREATE VIEW nat AS SELECT * FROM '/path/to/nat_parquet/*.parquet'")
   DBI::dbGetQuery(con, "SELECT SEX, COUNT(*) n FROM nat GROUP BY SEX")
   ```

   For statistical analysis in R, combine `dplyr` with `arrow`/DuckDB so the
   heavy lifting runs against the Parquet shards and only the (small)
   result is pulled into R, then attach value labels with
   `label_natality()`:

   ```r
   library(dplyr)
   nat <- arrow::open_dataset(Sys.glob(file.path(parquet_dir, "*.parquet")))
   by_sex <- nat |>
     filter(DBWT != 9999) |>
     group_by(SEX) |>
     summarise(n = n(), mean_dbwt = mean(DBWT)) |>
     collect() |>
     label_natality(cols = "SEX")
   ```

   See `vignette("tidy-parquet-queries")` for a fuller worked example, and
   `vignette("variable-dictionary")` for every field and its value labels.

`natality_unpack()` reconstructs the original fixed-width file from a
Parquet directory, if you ever need it back:

```r
natality_unpack("/path/to/nat_parquet", "Nat2025_copy.txt")
```

## Functions

| Function | Purpose |
|----------|---------|
| `check_natality_file()` | Report line endings and record length |
| `diagnose_layout()` | Check documented field positions against the file |
| `read_natality()` | Read fields into a `data.table`, typed or raw |
| `label_natality()` | Convert categorical codes to labelled factors |
| `natality_pack()` | Write sharded Parquet; optionally verify losslessness |
| `natality_verify()` | Verify an existing Parquet directory against the source file |
| `natality_unpack()` | Reconstruct the fixed-width file from Parquet |
| `natality_layout()` | Return the record layout as a `data.table` |
| `natality_values()` | Return value labels as a `data.table` |
| `natality_years()` | List years for which a layout is bundled |

## Record-layout notes (2025 file)

The User Guide documents a 1330-byte record. The 2025 public release
(`Nat2025PublicUS.c20260624.r20260922.txt`) has 1345-byte records with CRLF
line endings; bytes 1331–1345 are beyond the documented layout.
`check_natality_file()` reports this automatically.
`natality_pack()` detects the actual record length and keeps the extra bytes as
a trailing `FILLER_1331` column, so no data are lost.

The guide has a few typographic errors; `data-raw/parse_userguide.py` lists
all corrections made when the layout and value-label CSVs were generated.

## GitHub size limits

One year of sharded Parquet at compression level 22 is roughly 500 MB to
1 GB (actual size depends on data). That is too large for a GitHub repository
(100 MiB hard limit per file; 1 GB soft limit per repo).
Options:

- **GitHub Releases** – release assets can be up to 2 GB each.
- **Git LFS** – transparent large-file storage; free tier 1 GB.
- **Zenodo / OSF / AWS S3** – for public archival distribution.

## Legal

The NCHS natality public-use file is a US government work. Review the
[NCHS data-use agreement](https://www.cdc.gov/nchs/data_access/restrictions.htm)
before redistributing any derived file.

## Licence

Artistic-2.0
