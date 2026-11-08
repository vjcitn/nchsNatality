#' derive path to text file for birth data
#' @export
nchs_nat_path = function() Sys.getenv("NCHS_NAT_PATH")

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
#' Reads fields by byte position with [vroom::vroom_fwf()]. Bytes beyond the
#' last documented field are never read, so a file whose records are longer
#' than the guide says is read correctly as long as the documented fields are
#' where the guide puts them (see [diagnose_layout()]).
#'
#' @param file Path to the fixed-width natality file.
#' @param cols Field names to read. The default is every field except FILLER.
#' @param n_max Number of records to read.
#' @param raw If `TRUE`, return every field as the character code in the file.
#' @param na_unknown For numeric fields, turn the documented "unknown", "not
#'   stated" and "not applicable" codes (e.g. DBWT 9999, BMI 99.9, ILLB_R
#'   888/999, APGAR10 88) into `NA`.
#' @param year Data year; see [natality_years()].
#' @param ... Passed to [vroom::vroom_fwf()], e.g. `num_threads`.
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
read_natality <- function(file, cols = NULL, n_max = Inf, raw = FALSE,
                          na_unknown = TRUE, year = 2025, ...) {
  tb <- .nat_tables(year)
  lay <- natality_layout(year)[kind != "filler"]
  if (!is.null(cols)) {
    bad <- setdiff(cols, lay$name)
    if (length(bad)) stop("unknown field(s): ", paste(bad, collapse = ", "), call. = FALSE)
    lay <- lay[match(cols, name)]
  }
  dt <- vroom_fwf(file,
                  col_positions = fwf_positions(lay$start, lay$end, lay$name),
                  col_types = cols(.default = col_character()),
                  n_max = n_max, na = "", trim_ws = TRUE, progress = FALSE, ...)
  setDT(dt)
  if (raw) return(dt[])
  miss <- tb$missing
  for (v in lay[kind == "numeric", name]) {
    x <- dt[[v]]
    if (na_unknown && v %in% miss$name)
      x[x %chin% miss[name == v, code[[1]]]] <- NA
    set(dt, j = v, value = if (v == "BMI") as.numeric(x) else as.integer(x))
  }
  dt[]
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
