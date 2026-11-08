#' derive path to text file for birth data
#' @export
nchs_nat_path = function() Sys.getenv("NCHS_NAT_PATH")

#' Derive path to a sharded Parquet directory for birth data
#'
#' @return The value of the `NCHS_NAT_PARQUET` environment variable (`""` if
#'   unset).
#' @export
nchs_nat_parquet_dir = function() Sys.getenv("NCHS_NAT_PARQUET")

## A directory counts as usable Parquet input only if storage.csv (written by
## natality_pack()) is there and at least one shard is there to query.
.valid_parquet_dir <- function(dir) {
  nzchar(dir) && file.exists(file.path(dir, "storage.csv")) &&
    length(list.files(dir, "\\.parquet$")) > 0
}

## Precedence: an explicit `parquet_dir` or `file` argument always wins over
## the environment; between the two environment variables, a valid
## NCHS_NAT_PARQUET wins over NCHS_NAT_PATH (querying shards is the point of
## having packed them). See inst/adrs/0002-parquet-before-text-resolution.md.
.resolve_natality_source <- function(file, parquet_dir) {
  if (!is.null(parquet_dir)) {
    if (!.valid_parquet_dir(parquet_dir))
      stop("not a valid parquet directory (needs storage.csv and *.parquet ",
           "files, as written by natality_pack()): ", parquet_dir, call. = FALSE)
    return(list(kind = "parquet", path = parquet_dir))
  }
  if (!is.null(file)) return(list(kind = "text", path = file))

  envp <- nchs_nat_parquet_dir()
  if (.valid_parquet_dir(envp)) return(list(kind = "parquet", path = envp))
  envf <- nchs_nat_path()
  if (nzchar(envf)) return(list(kind = "text", path = envf))
  stop("no natality source found: set NCHS_NAT_PATH (fixed-width file) and/or ",
       "NCHS_NAT_PARQUET (a directory written by natality_pack()), or pass ",
       "`file`/`parquet_dir` explicitly", call. = FALSE)
}

## Shared by the text (vroom) and parquet (DuckDB) read paths so that typing
## and sentinel-NA handling of numeric fields behave identically either way.
## `x` may already be numeric/integer (parquet's "int" storage rule) or still
## character (everything else); both are handled.
.apply_numeric_typing <- function(dt, lay, tb, na_unknown) {
  miss <- tb$missing
  for (v in lay[kind == "numeric", name]) {
    if (!v %in% names(dt)) next
    x <- dt[[v]]
    is_double <- v == "BMI"
    if (na_unknown && v %in% miss$name) {
      codes <- miss[name == v, code[[1]]]
      if (is.character(x)) x[x %chin% codes] <- NA
      else x[x %in% suppressWarnings(as.numeric(codes))] <- NA
    }
    set(dt, j = v, value = if (is_double) as.numeric(x) else as.integer(x))
  }
  dt[]
}

#' Check line endings and record length of a natality file
#'
#' Reads only the first `nbytes` bytes.
#'
#' @param file Path to the fixed-width natality file.
#' @param nbytes Number of bytes to inspect.
#' @param year Data year, used for the documented record length.
#' @return Invisibly, a list with `terminator` (`"LF"`, `"CRLF"`, `"CR only"`
#'   or `"none"`), `record_length` (the distinct lengths seen, excluding line
#'   endings), `documented_length` and `quotes` (number of `"` bytes). A summary
#'   is printed.
#' @examples
#' f <- tempfile()
#' writeLines(strrep(" ", 1330), f)
#' check_natality_file(f)
#' @export
check_natality_file <- function(file, nbytes = 100000L, year = 2025) {
  doc <- .nat_tables(year)$doc_length
  b <- readBin(file, "raw", nbytes)
  lf <- which(b == as.raw(0x0a))
  cr <- which(b == as.raw(0x0d))
  term <- if (length(lf) && length(cr) && all(cr + 1L %in% lf)) "CRLF"
          else if (length(lf)) "LF" else if (length(cr)) "CR only" else "none"
  ends <- switch(term, CRLF = lf, LF = lf, `CR only` = cr, integer())
  reclen <- unique(diff(c(0L, ends)) - if (term == "CRLF") 2L else 1L)
  quotes <- sum(b == as.raw(0x22))
  cat(sprintf(paste0("terminator: %s; record length(s) in first %d bytes: %s ",
                     "(guide documents %d); '\"' bytes: %d\n"),
              term, length(b), paste(reclen, collapse = ","), doc, quotes))
  if (term %in% c("CR only", "none"))
    warning("readers expect LF or CRLF line ends; convert the file first, ",
            "e.g. tr '\\r' '\\n' < in > out", call. = FALSE)
  invisible(list(terminator = term, record_length = reclen,
                 documented_length = doc, quotes = quotes))
}

#' Read the natality public-use file
#'
#' Reads fields by byte position with [vroom::vroom_fwf()], or, if a sharded
#' Parquet directory (as written by [natality_pack()]) is available, queries
#' that instead via DuckDB — same result, far less I/O. Bytes beyond the last
#' documented field are never read, so a file whose records are longer than
#' the guide says is read correctly as long as the documented fields are
#' where the guide puts them (see [diagnose_layout()]).
#'
#' @section Choosing text vs Parquet:
#' `file` and `parquet_dir` default to `NULL`, meaning "resolve from the
#' environment": `NCHS_NAT_PARQUET`, if it names a directory with a
#' `storage.csv` and at least one `*.parquet` file in it, is used; otherwise
#' `NCHS_NAT_PATH` is used. Passing `file` or `parquet_dir` explicitly pins
#' the source and skips that resolution. Either way the result has the same
#' shape: same columns, same types, same `na_unknown` sentinel handling — see
#' `inst/adrs/` for the reasoning. Row order is **not** part of that
#' contract: [natality_pack()] sorts and shards rows for compression (see its
#' documentation), so reading from Parquet returns the same rows as from
#' text, as a set, but not necessarily in the same order.
#'
#' @param file Path to the fixed-width natality file. `NULL` (the default)
#'   resolves from `NCHS_NAT_PATH` or `NCHS_NAT_PARQUET`; see above.
#' @param cols Field names to read. The default is every field except FILLER.
#' @param n_max Number of records to read.
#' @param raw If `TRUE`, return every field as the character code in the file.
#' @param na_unknown For numeric fields, turn the documented "unknown", "not
#'   stated" and "not applicable" codes (e.g. DBWT 9999, BMI 99.9, ILLB_R
#'   888/999, APGAR10 88) into `NA`.
#' @param year Data year; see [natality_years()].
#' @param parquet_dir A directory written by [natality_pack()] to query
#'   instead of `file`. `NULL` (the default) resolves from `NCHS_NAT_PARQUET`;
#'   see above. Ignored if `file` is given explicitly.
#' @param ... Passed to [vroom::vroom_fwf()] when reading text, e.g.
#'   `num_threads`. Ignored when reading from Parquet.
#' @return A `data.table`. Numeric fields (`kind == "numeric"` in
#'   [natality_layout()]) are integer (BMI is double). Categorical fields are
#'   character codes, for use with [label_natality()]. Blank fields, which the
#'   guide uses for items not on the certificate or from non-reporting areas,
#'   are `NA`.
#' @examples
#' if (nchar(f <- Sys.getenv("NCHS_NAT_PATH"))>0) {
#'   z <- read_natality(f, n_max = 10000)
#'   z <- read_natality(f, cols = c("MAGER", "DBWT", "COMBGEST", "SEX"))
#'   } else { "NCHS_NAT_PATH not set in visible environment" }
#' @export
read_natality <- function(file = NULL, cols = NULL, n_max = Inf, raw = FALSE,
                          na_unknown = TRUE, year = 2025, parquet_dir = NULL, ...) {
  src <- .resolve_natality_source(file, parquet_dir)
  if (src$kind == "parquet")
    return(.read_natality_parquet(src$path, cols, n_max, raw, na_unknown, year))

  tb <- .nat_tables(year)
  lay <- natality_layout(year)[kind != "filler"]
  if (!is.null(cols)) {
    bad <- setdiff(cols, lay$name)
    if (length(bad)) stop("unknown field(s): ", paste(bad, collapse = ", "), call. = FALSE)
    lay <- lay[match(cols, name)]
  }
  dt <- vroom_fwf(src$path,
                  col_positions = fwf_positions(lay$start, lay$end, lay$name),
                  col_types = cols(.default = col_character()),
                  n_max = n_max, na = "", trim_ws = TRUE, progress = FALSE, ...)
  setDT(dt)
  if (raw) return(dt[])
  .apply_numeric_typing(dt, lay, tb, na_unknown)
}

#' Turn categorical codes into labelled factors
#'
#' @param dt A `data.table` from [read_natality()].
#' @param cols Fields to label; the default is every categorical field in `dt`.
#' @param territory If `TRUE`, use the Puerto Rico / territory coding (block 2
#'   of [natality_values()]) where the guide gives one (RESTATUS, DMAR). If
#'   `FALSE`, use the US coding.
#' @param year Data year; see [natality_years()].
#' @return A copy of `dt` with those columns as factors. A field whose codes
#'   include `"Blank"` maps `NA` to that label (e.g. MAGE_IMPFLG
#'   "Age not imputed"). Codes in the data that the guide does not list become
#'   levels of their own, unchanged.
#' @examples
#' dt <- data.table::data.table(SEX = c("M", "F"), MAGE_IMPFLG = c(NA, "1"))
#' label_natality(dt)
#' @export
label_natality <- function(dt, cols = NULL, territory = FALSE, year = 2025) {
  dt <- copy(as.data.table(dt))
  val <- .nat_tables(year)$values
  cand <- intersect(names(dt), natality_layout(year)[kind == "code", name])
  if (!is.null(cols)) cand <- intersect(cand, cols)
  for (v in cand) {
    lab <- val[name == v]
    if (!nrow(lab)) next
    b <- if (territory && any(lab$block == 2L)) 2L else 1L
    lab <- lab[block == b]
    x <- as.character(dt[[v]])
    if ("Blank" %in% lab$code) x[is.na(x)] <- "Blank"
    extra <- setdiff(sort(unique(stats::na.omit(x))), lab$code)
    set(dt, j = v, value = factor(x, levels = c(lab$code, extra),
                                  labels = c(lab$label, extra)))
  }
  dt[]
}
