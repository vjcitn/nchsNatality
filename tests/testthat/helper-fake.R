## Synthetic records that follow the bundled layout (not real data).
fake_natality <- function(n = 200, tail = NULL, eol = "\n", shift_at = NULL, seed = 1) {
  set.seed(seed)
  lay <- natality_layout()
  val <- natality_values()[block == 1L]
  one <- function(nm, w) {
    cs <- val[name == nm, code]
    if (!length(cs)) return(strrep(" ", w))
    c <- sample(cs, 1)
    if (c == "Blank" || runif(1) < 0.02) return(strrep(" ", w))
    if (c == "nnnn") return("2024")
    if (grepl("^[0-9.]+-[0-9.]+$", c)) {
      r <- as.numeric(strsplit(c, "-")[[1]])
      if (grepl("\\.", c)) return(formatC(runif(1, r[1], r[2]), format = "f", digits = 1, width = w))
      return(formatC(sample(r[1]:r[2], 1), width = w, flag = "0"))
    }
    formatC(c, width = w)
  }
  rec <- vapply(seq_len(n), function(i)
    paste(mapply(function(nm, w) if (nm == "FILLER") strrep(" ", w) else one(nm, w),
                 lay$name, lay$width), collapse = ""), "")
  if (!is.null(tail)) rec <- paste0(rec, rep_len(tail, n))
  if (!is.null(shift_at))
    rec <- paste0(substr(rec, 1, shift_at), strrep("X", 15), substring(rec, shift_at + 1))
  f <- tempfile(fileext = ".txt")
  con <- file(f, "wb"); writeChar(paste0(rec, eol, collapse = ""), con, eos = NULL); close(con)
  f
}
