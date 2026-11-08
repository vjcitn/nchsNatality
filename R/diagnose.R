#' Check the documented record layout against a natality file
#'
#' Looks at the first `n` records. For each field it computes the share of
#' non-blank values that are not a documented code, or that fall outside every
#' documented range. If the layout is shifted somewhere, a run of bad fields
#' starts at the shift, and FILLER bytes that should be blank are not.
#' Bytes beyond the documented record length are summarised separately.
#'
#' @param file Path to the fixed-width natality file.
#' @param n Number of records to inspect.
#' @param year Data year; see [natality_years()].
#' @param threshold Fields whose share of undocumented values exceeds this are
#'   reported.
#' @return An object of class `natality_diagnosis`: a list with
#'   `record_lengths` (table), `fields` (one row per field with `nonblank` and
#'   `bad` shares), `anchors` (value tables for a few fields with known codes),
#'   `filler_nonblank`, `bad_fields`, and, for records longer than documented,
#'   `tail_values` and `tail_nonblank`. It has a print method.
#' @examples
#' \dontrun{
#' diagnose_layout("Nat2025PublicUS.c20260624.r20260922.txt")
#' }
#' @export
diagnose_layout <- function(file, n = 20000L, year = 2025, threshold = 0.01) {
  L <- readLines(file, n = n, warn = FALSE)
  doc <- .nat_tables(year)$doc_length
  rl <- max(nchar(L, type = "bytes"))
  val <- .nat_tables(year)$values
  codes <- split(val$code, val$name)

  bad_share <- function(x, cs) {
    x <- trimws(x)
    x <- x[x != ""]
    if (!length(x) || is.null(cs)) return(NA_real_)
    ok <- x %in% cs | ("nnnn" %in% cs & grepl("^[0-9]{4}$", x))
    m <- regmatches(cs, regexec("^([0-9.]+)-([0-9.]+)$", cs))
    m <- m[lengths(m) == 3L]
    if (length(m)) {
      lo <- as.numeric(vapply(m, `[`, "", 2L))
      hi <- as.numeric(vapply(m, `[`, "", 3L))
      v <- suppressWarnings(as.numeric(x))
      ok <- ok | vapply(v, function(z) !is.na(z) && any(z >= lo & z <= hi), TRUE)
    }
    mean(!ok)
  }

  lay <- natality_layout(year, record_length = max(rl, doc))[start <= rl]
  fields <- lay[, {
    x <- substr(L, start, pmin(end, rl))
    list(nonblank = mean(trimws(x) != ""),
         bad = if (name == "FILLER") NA_real_ else bad_share(x, codes[[name]]))
  }, by = list(start, end, name)]

  anchors <- lapply(c("DOB_YY", "DOB_MM", "SEX", "DPLURAL", "F_BFED"), function(v) {
    s <- lay[name == v]
    sort(table(substr(L, s$start, s$end)), decreasing = TRUE)
  })
  names(anchors) <- c("DOB_YY", "DOB_MM", "SEX", "DPLURAL", "F_BFED")

  out <- list(file = file, n = length(L), documented_length = doc,
              record_lengths = table(nchar(L, type = "bytes")),
              fields = fields, anchors = anchors,
              filler_nonblank = fields[name == "FILLER" & start <= doc & nonblank > 0],
              bad_fields = fields[!is.na(bad) & bad > threshold][order(start)])
  if (rl > doc) {
    tl <- substr(L, doc + 1L, rl)
    out$tail_values <- sort(table(tl), decreasing = TRUE)
    out$tail_nonblank <- stats::setNames(
      vapply((doc + 1L):rl, function(p) mean(substr(L, p, p) != " "), 0),
      (doc + 1L):rl)
  }
  class(out) <- "natality_diagnosis"
  out
}

#' @param x A `natality_diagnosis`.
#' @param ... Ignored.
#' @rdname diagnose_layout
#' @export
print.natality_diagnosis <- function(x, ...) {
  rl <- x$record_lengths
  cat(sprintf("%s records of %s: record length %s (guide documents %d)\n",
              format(x$n, big.mark = ","), basename(x$file),
              paste(sprintf("%s x%d", names(rl), rl), collapse = ", "),
              x$documented_length))
  cat("\nanchor fields (most common values):\n")
  for (v in names(x$anchors)) {
    tb <- x$anchors[[v]]
    k <- seq_len(min(6L, length(tb)))
    cat(sprintf("  %-8s %s\n", v,
                paste(sprintf("'%s' %d", names(tb)[k], tb[k]), collapse = ", ")))
  }
  cat("\nnon-blank FILLER within the documented record: ")
  if (nrow(x$filler_nonblank)) { cat("\n"); print(x$filler_nonblank[, list(start, end, nonblank)]) }
  else cat("none\n")
  cat("fields with undocumented values: ")
  if (nrow(x$bad_fields)) {
    cat("\n")
    print(utils::head(x$bad_fields[, list(start, end, name, nonblank, bad = round(bad, 3))], 25))
  } else cat("none\n")
  if (!is.null(x$tail_values)) {
    p <- x$tail_nonblank
    cat(sprintf("\nbytes %s-%s (not in the guide): non-blank share by position\n",
                names(p)[1], names(p)[length(p)]))
    print(round(p, 3))
    cat("most common values:\n")
    print(utils::head(x$tail_values, 10))
  }
  invisible(x)
}
