## Lossless, compact, sharded Parquet via DuckDB.
## SQL builders are internal (@noRd); the exported functions run them.

.q <- function(x) paste0('"', gsub('"', '""', x), '"')     # SQL identifier
.lit <- function(x) paste0("'", gsub("'", "''", x), "'")    # SQL string literal

.need_duckdb <- function() {
  for (p in c("DBI", "duckdb"))
    if (!requireNamespace(p, quietly = TRUE))
      stop("package '", p, "' is needed for this function", call. = FALSE)
}

.connect <- function(memory_limit = NULL) {
  .need_duckdb()
  con <- DBI::dbConnect(duckdb::duckdb())
  if (!is.null(memory_limit))
    DBI::dbExecute(con, sprintf("SET memory_limit = %s", .lit(memory_limit)))
  con
}

.disconnect <- function(con) DBI::dbDisconnect(con, shutdown = TRUE)

## DuckDB table function returning each record as one VARCHAR column `line`
.nat_src <- function(file)
  sprintf(paste0("read_csv(%s, columns = {'line': 'VARCHAR'}, header = false, ",
                 "delim = chr(1), quote = '', escape = '', auto_detect = false)"),
          .lit(normalizePath(file, mustWork = FALSE)))

#' SQL that reads natality records in DuckDB
#'
#' Returns a `SELECT` statement that slices fields out of each record in
#' DuckDB, without loading the file into R. Values are trimmed text, with blank
#' fields as `NULL`.
#'
#' @param file Path to the fixed-width natality file.
#' @param cols Field names to select; default all non-filler fields.
#' @param year Data year; see [natality_years()].
#' @return A character string of SQL.
#' @examples
#' cat(natality_sql("Nat2025PublicUS.txt", c("DOB_MM", "DBWT")))
#' \dontrun{
#' con <- DBI::dbConnect(duckdb::duckdb())
#' DBI::dbGetQuery(con, paste("SELECT DOB_MM, avg(CAST(DBWT AS INT)) FROM (",
#'                            natality_sql(f), ") GROUP BY 1"))
#' }
#' @export
natality_sql <- function(file, cols = NULL, year = 2025) {
  lay <- natality_layout(year)[kind != "filler"]
  if (!is.null(cols)) lay <- lay[match(cols, name)]
  if (anyNA(lay$name)) stop("unknown field(s) in `cols`", call. = FALSE)
  sel <- sprintf("nullif(trim(substr(line, %d, %d)), '') AS %s",
                 lay$start, lay$width, .q(lay$name))
  sprintf("SELECT\n  %s\nFROM %s", paste(sel, collapse = ",\n  "), .nat_src(file))
}

## ---- profile -------------------------------------------------------------------

.profile_sql <- function(file, lay, record_length) {
  s <- sprintf("substr(line, %d, %d)", lay$start, lay$width)
  b <- sprintf("%s = repeat(' ', %d)", s, lay$width)
  d <- lay$name != "FILLER"
  sd <- s[d]; bd <- b[d]; w <- lay$width[d]; cl <- lay$col[d]
  agg <- c(
    "count(*) AS n_records",
    "min(length(line)) AS min_len",
    "max(length(line)) AS max_len",
    sprintf("bool_and(length(line) = %d) AS len_ok", record_length),
    "bool_and(strlen(line) = length(line)) AS ascii_ok",
    sprintf("bool_and(%s) AS %s", b, .q(paste0(lay$col, "__blank"))),
    sprintf(paste0("bool_and(%s OR (regexp_full_match(%s, '[0-9]+') AND ",
                   "lpad(CAST(TRY_CAST(%s AS BIGINT) AS VARCHAR), %d, '0') = %s)) AS %s"),
            bd, sd, sd, w, sd, .q(paste0(cl, "__int"))),
    sprintf("max(CASE WHEN regexp_full_match(%s, '[0-9]+') THEN TRY_CAST(%s AS BIGINT) END) AS %s",
            sd, sd, .q(paste0(cl, "__max"))),
    sprintf("bool_and(%s OR left(%s, 1) <> ' ') AS %s", bd, sd, .q(paste0(cl, "__left"))),
    sprintf("bool_and(%s OR right(%s, 1) <> ' ') AS %s", bd, sd, .q(paste0(cl, "__right"))))
  sprintf("SELECT\n  %s\nFROM %s", paste(agg, collapse = ",\n  "), .nat_src(file))
}

## one-row profile result -> storage table (one row per field, with its rule)
.storage_from_profile <- function(p, lay, record_length, int_codes = FALSE) {
  p <- as.list(p)
  as_lgl <- function(v) {
    v <- as.character(v)
    as.logical(ifelse(v %in% c("1", "0"), v == "1", v))
  }
  if (!isTRUE(as_lgl(p$len_ok)))
    stop(sprintf("records are not all %d characters long (min %s, max %s); see check_natality_file()",
                 record_length, p$min_len, p$max_len), call. = FALSE)
  if (!isTRUE(as_lgl(p$ascii_ok)))
    stop("the file has non-ASCII bytes, so byte and character positions differ",
         call. = FALSE)
  g <- function(what) vapply(lay$col, function(x) {
    v <- p[[paste0(x, "__", what)]]
    if (is.null(v) || !length(v) || is.na(v) || identical(v, "")) NA_character_
    else as.character(v)
  }, character(1), USE.NAMES = FALSE)
  st <- copy(lay)
  st[, `:=`(blank_all = as_lgl(g("blank")), int_ok = as_lgl(g("int")),
            max_int = as.numeric(g("max")), left_ok = as_lgl(g("left")),
            right_ok = as_lgl(g("right")))]
  st[, rule := fcase(
    name == "FILLER" & blank_all, "blank",
    name == "FILLER", "raw",
    int_ok & !blank_all & (kind == "numeric" | int_codes), "int",
    left_ok, "left",
    right_ok, "right",
    default = "raw")]
  st[, type := fcase(rule != "int", "VARCHAR",
                     max_int <= 127, "TINYINT",
                     max_int <= 32767, "SMALLINT",
                     default = "INTEGER")]
  st[, n_records := as.numeric(p$n_records)]
  st[, list(start, end, width, name, col, kind, rule, type, n_records)]
}

.detect_record_length <- function(con, file) {
  r <- DBI::dbGetQuery(con, sprintf(
    "SELECT max(length(line)) AS n FROM (SELECT line FROM %s LIMIT 10000)", .nat_src(file)))
  as.integer(r$n)
}

## ---- write -------------------------------------------------------------------

.select_sql <- function(file, st) {
  st <- st[rule != "blank"]
  s <- sprintf("substr(line, %d, %d)", st$start, st$width)
  e <- ifelse(st$rule == "int",   sprintf("CAST(nullif(trim(%s), '') AS %s)", s, st$type),
       ifelse(st$rule == "left",  sprintf("nullif(rtrim(%s), '')", s),
       ifelse(st$rule == "right", sprintf("nullif(ltrim(%s), '')", s),
              s)))   # raw: untrimmed, never NULL
  sprintf("SELECT\n  %s\nFROM %s", paste(e, "AS", .q(st$col), collapse = ",\n  "),
          .nat_src(file))
}

#' Default row order for natality_pack()
#'
#' Reporting flags first: they are constant within a reporting area, so sorting
#' on them groups records in state-like blocks. Then a few low-cardinality
#' fields. Sorting changes only how well the data compress, never the content.
#'
#' @param storage A storage table, as written to `storage.csv` by
#'   [natality_pack()].
#' @return Character vector of column names.
#' @keywords internal
#' @export
natality_default_sort <- function(storage) {
  st <- as.data.table(storage)
  flags <- st[grepl("^[Ff]_", col) & rule != "blank", col]
  c(flags, intersect(c("RESTATUS", "BFACIL", "MRACE6", "MHISP_R", "DMAR", "PAY_REC",
                       "MEDUC", "DPLURAL", "SEX", "ME_ROUT", "MAGER"), st$col))
}

.copy_sql <- function(where, path, sort_by, level, row_group_size, parquet_version) {
  ord <- if (length(sort_by)) paste("ORDER BY", paste(.q(sort_by), collapse = ", ")) else ""
  sprintf(paste0("COPY (SELECT * FROM nat %s %s) TO %s (FORMAT parquet, ",
                 "COMPRESSION zstd, COMPRESSION_LEVEL %d, ROW_GROUP_SIZE %d%s)"),
          where, ord, .lit(path), as.integer(level), as.integer(row_group_size),
          if (parquet_version == "V2") ", PARQUET_VERSION V2" else "")
}

#' Pack a natality file into compact, lossless, sharded Parquet
#'
#' Profiles every record, writes one Parquet file per value of `shard_by`, and
#' then checks that the original records can be rebuilt exactly from the
#' shards (see [natality_verify()]).
#'
#' @section How fields are stored:
#' The storage of each field is decided from the data, not assumed from the
#' guide:
#' * `int`: digits only, zero-padded to full width. Stored as the smallest
#'   integer type that fits; rebuilt by padding with `0`. Used for numeric
#'   fields, and for digit-only codes too if `int_codes = TRUE`.
#' * `left`: no leading blanks. Stored as trimmed text; rebuilt by padding on
#'   the right.
#' * `right`: no trailing blanks. Stored as trimmed text; rebuilt by padding on
#'   the left.
#' * `raw`: anything else. Stored untrimmed.
#' * `blank`: a FILLER that is blank in every record. Not stored.
#'
#' A blank field is stored as `NULL`. The rules are written to
#' `<out_dir>/storage.csv`, which [natality_verify()] and [natality_unpack()]
#' need, so keep it with the shards. Numeric fields keep their sentinel codes
#' (DBWT 9999, CIG_0 99, ...); turn them into `NA` when analysing.
#'
#' Bytes beyond the record length the guide documents (1330 for 2025) are kept
#' as a trailing column, `FILLER_1331`, unless they are blank in every record.
#'
#' @section What is not kept:
#' Record order (rows are sorted so that they compress better) and line
#' endings. The check compares the source and the rebuilt records as multisets.
#'
#' @section File size:
#' GitHub blocks files over 100 MiB and warns at 50 MiB, so `max_mb` defaults
#' to 95.
#'
#' @param file Path to the fixed-width natality file.
#' @param out_dir Directory for the shards and `storage.csv`. Its base name is
#'   used as the stem of the shard file names.
#' @param shard_by Field to shard on. The default, birth month, gives 12 files
#'   (plus one for blank months, if any). `NULL` writes a single file.
#' @param level zstd compression level, 1-22. High levels are slow to write but
#'   not slower to read.
#' @param row_group_size Rows per Parquet row group.
#' @param sort_by Columns to sort rows by within each shard. `NULL` uses
#'   [natality_default_sort()]; `character(0)` means no sorting.
#' @param int_codes Also store digit-only categorical codes (e.g. MEDUC,
#'   MRACE15) as integers. `FALSE` keeps them as the character codes that
#'   [label_natality()] expects.
#' @param parquet_version `"V1"` (most widely readable) or `"V2"`.
#' @param max_mb Warn if any shard is larger than this many MiB.
#' @param verify Run [natality_verify()] after writing.
#' @param record_length Record length of the file, excluding line endings.
#'   `NULL` detects it from the first 10,000 records; every record must then
#'   have that length.
#' @param memory_limit DuckDB memory limit, e.g. `"8GB"`.
#' @param year Data year; see [natality_years()].
#' @return Invisibly, a list with `storage` (the storage table), `report` (from
#'   [natality_report()]) and `verified` (`TRUE`, `FALSE`, or `NA` if not run).
#' @examples
#' \dontrun{
#' res <- natality_pack("Nat2025PublicUS.c20260624.r20260922.txt", "nat2025")
#' res$report
#' arrow::open_dataset("nat2025")
#' }
#' @export
natality_pack <- function(file, out_dir, shard_by = "DOB_MM", level = 22L,
                          row_group_size = 1e6, sort_by = NULL, int_codes = FALSE,
                          parquet_version = c("V1", "V2"), max_mb = 95,
                          verify = TRUE, record_length = NULL,
                          memory_limit = "8GB", year = 2025) {
  parquet_version <- match.arg(parquet_version)
  if (!file.exists(file)) stop("file not found: ", file, call. = FALSE)
  con <- .connect(memory_limit)
  on.exit(.disconnect(con))
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

  doc <- .nat_tables(year)$doc_length
  if (is.null(record_length)) record_length <- .detect_record_length(con, file)
  if (record_length != doc)
    message(sprintf("records are %d characters; the guide documents %d", record_length, doc))
  lay <- natality_layout(year, record_length = record_length)
  if (!is.null(shard_by) && !shard_by %in% lay[kind != "filler", name])
    stop("unknown `shard_by` field: ", shard_by, call. = FALSE)

  message("profiling fields ...")
  st <- .storage_from_profile(DBI::dbGetQuery(con, .profile_sql(file, lay, record_length)),
                              lay, record_length, int_codes)
  fwrite(st, file.path(out_dir, "storage.csv"))
  tb <- table(st$rule)
  message(sprintf("%s records; storage rules: %s", format(st$n_records[1], big.mark = ","),
                  paste(names(tb), tb, sep = "=", collapse = " ")))
  if (record_length > doc && st[start == doc + 1L, rule] == "raw")
    message(sprintf("bytes %d-%d are not blank; kept as column FILLER_%d",
                    doc + 1L, record_length, doc + 1L))

  message("loading ...")
  DBI::dbExecute(con, paste("CREATE TEMP TABLE nat AS", .select_sql(file, st)))
  if (is.null(sort_by)) sort_by <- natality_default_sort(st)
  bad <- setdiff(sort_by, st[rule != "blank", col])
  if (length(bad)) stop("unknown `sort_by` column(s): ", paste(bad, collapse = ", "), call. = FALSE)

  stem <- sub("\\.parquet$", "", basename(normalizePath(out_dir)))
  for (old in list.files(out_dir, "\\.parquet$", full.names = TRUE)) unlink(old)
  if (is.null(shard_by)) {
    shards <- list(list(where = "", path = file.path(out_dir, paste0(stem, ".parquet"))))
  } else {
    kexpr <- sprintf("coalesce(CAST(%s AS VARCHAR), 'NA')", .q(shard_by))
    keys <- DBI::dbGetQuery(con, sprintf("SELECT DISTINCT %s AS k FROM nat ORDER BY 1", kexpr))$k
    shards <- lapply(keys, function(k) {
      tag <- gsub("[^A-Za-z0-9]", "_", if (grepl("^[0-9]$", k)) paste0("0", k) else k)
      list(where = sprintf("WHERE %s = %s", kexpr, .lit(k)),
           path = file.path(out_dir, sprintf("%s_%s-%s.parquet", stem, shard_by, tag)))
    })
  }
  for (s in shards) {
    message("writing ", basename(s$path))
    DBI::dbExecute(con, .copy_sql(s$where, s$path, sort_by, level, row_group_size,
                                  parquet_version))
  }
  DBI::dbExecute(con, "DROP TABLE nat")

  rep <- natality_report(out_dir, file)
  if (any(rep$mb > max_mb))
    warning("shard(s) larger than ", max_mb, " MiB: ",
            paste(rep$file[rep$mb > max_mb], collapse = ", "), call. = FALSE)
  ok <- if (verify) natality_verify(file, out_dir, con = con) else NA
  invisible(list(storage = st, report = rep, verified = ok))
}

#' Sizes of the Parquet shards
#'
#' @param out_dir Directory written by [natality_pack()].
#' @param file Optional source file, to report the compression ratio.
#' @return A `data.table` with `file` and `mb` (MiB). A summary is shown as a
#'   message.
#' @export
natality_report <- function(out_dir, file = NULL) {
  f <- list.files(out_dir, "\\.parquet$", full.names = TRUE)
  rep <- data.table(file = basename(f), mb = round(file.size(f) / 2^20, 2))
  tot <- sum(file.size(f)) / 2^20
  msg <- sprintf("%d shard(s), %.1f MiB in total, largest %.1f MiB",
                 nrow(rep), tot, if (nrow(rep)) max(rep$mb) else 0)
  if (!is.null(file))
    msg <- paste0(msg, sprintf(" (source %.0f MiB, %.1fx smaller)",
                               file.size(file) / 2^20, file.size(file) / 2^20 / tot))
  message(msg)
  rep[]
}

## ---- rebuild / verify ---------------------------------------------------------

.storage <- function(out_dir) {
  f <- file.path(out_dir, "storage.csv")
  if (!file.exists(f)) stop("no storage.csv in ", out_dir, call. = FALSE)
  st <- fread(f, colClasses = c(name = "character", col = "character", rule = "character",
                                type = "character", kind = "character"))
  setorder(st, start)
  st[]
}

.rebuild_sql <- function(out_dir, st = .storage(out_dir)) {
  pad <- function(f) sprintf("coalesce(%s, repeat(' ', %d))", f, st$width)
  e <- ifelse(st$rule == "blank", sprintf("repeat(' ', %d)", st$width),
       ifelse(st$rule == "int",   pad(sprintf("lpad(CAST(%s AS VARCHAR), %d, '0')", .q(st$col), st$width)),
       ifelse(st$rule == "left",  pad(sprintf("rpad(%s, %d, ' ')", .q(st$col), st$width)),
       ifelse(st$rule == "right", pad(sprintf("lpad(%s, %d, ' ')", .q(st$col), st$width)),
              .q(st$col)))))
  sprintf("SELECT concat(\n  %s) AS line\nFROM read_parquet(%s)",
          paste(e, collapse = ",\n  "),
          .lit(file.path(normalizePath(out_dir), "*.parquet")))
}

.fingerprint_sql <- function(from)
  sprintf(paste0("SELECT count(*) AS n, CAST(sum(hash(line)) AS VARCHAR) AS s, ",
                 "CAST(bit_xor(hash(line)) AS VARCHAR) AS x, ",
                 "CAST(sum(hash(md5(line))) AS VARCHAR) AS s2 FROM (%s)"), from)

#' Check that Parquet shards rebuild the source records exactly
#'
#' Rebuilds every record from the shards and compares the result with the
#' source file using order-independent hashes of all records (a count, a sum
#' and an xor of 64-bit hashes, and a sum of hashes of MD5 digests).
#'
#' @param file Path to the source fixed-width file.
#' @param out_dir Directory written by [natality_pack()].
#' @param con Optional open DuckDB connection.
#' @return `TRUE` if the two sets of records are identical, else `FALSE`.
#' @export
natality_verify <- function(file, out_dir, con = NULL) {
  if (is.null(con)) {
    con <- .connect()
    on.exit(.disconnect(con))
  }
  a <- DBI::dbGetQuery(con, .fingerprint_sql(paste("SELECT line FROM", .nat_src(file))))
  b <- DBI::dbGetQuery(con, .fingerprint_sql(.rebuild_sql(out_dir)))
  ok <- isTRUE(all.equal(as.list(a), as.list(b), check.attributes = FALSE))
  message(if (ok) sprintf("verified: all %s records rebuild exactly", format(as.numeric(a$n), big.mark = ","))
          else "MISMATCH between the source records and those rebuilt from the shards")
  ok
}

#' Rebuild the fixed-width file from Parquet shards
#'
#' @param out_dir Directory written by [natality_pack()].
#' @param outfile Path of the fixed-width file to write (LF line endings).
#'   Records come out in shard order, not the original order.
#' @return `outfile`, invisibly.
#' @export
natality_unpack <- function(out_dir, outfile) {
  con <- .connect()
  on.exit(.disconnect(con))
  DBI::dbExecute(con, sprintf(
    "COPY (%s) TO %s (FORMAT csv, HEADER false, DELIMITER chr(1), QUOTE '', ESCAPE '')",
    .rebuild_sql(out_dir), .lit(outfile)))
  invisible(outfile)
}
