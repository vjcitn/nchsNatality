.nat_cache <- new.env(parent = emptyenv())

#' Years for which a record layout is bundled
#'
#' @return Integer vector of years.
#' @examples
#' natality_years()
#' @export
natality_years <- function() {
  f <- list.files(system.file("extdata", package = "nchsNatality"),
                  "^natality[0-9]{4}_layout\\.csv$")
  as.integer(sub("^natality([0-9]{4})_layout\\.csv$", "\\1", f))
}

.check_year <- function(year) {
  year <- as.integer(year)
  if (length(year) != 1L || !year %in% natality_years())
    stop("no bundled layout for year ", year, "; available: ",
         paste(natality_years(), collapse = ", "), call. = FALSE)
  year
}

.nat_tables <- function(year) {
  key <- as.character(.check_year(year))
  if (is.null(.nat_cache[[key]])) {
    dir <- system.file("extdata", package = "nchsNatality")
    lay <- fread(file.path(dir, sprintf("natality%s_layout.csv", key)),
                 colClasses = c(start = "integer", end = "integer",
                                width = "integer", name = "character",
                                group = "character", description = "character"),
                 na.strings = NULL)
    val <- fread(file.path(dir, sprintf("natality%s_values.csv", key)),
                 colClasses = "character", encoding = "UTF-8", na.strings = NULL)
    val[, block := as.integer(block)]

    ## numeric = a measured quantity documented by a range code
    ## (DBWT 0227-8165, BMI 13.0-69.9, ...); everything else is a code
    lay[, kind := "code"]
    num <- val[grepl("^[0-9.]+-[0-9.]+$|^nnnn$", code), unique(name)]
    lay[name %in% c(num, "MAGER", "DOB_YY"), kind := "numeric"]
    lay[name == "FILLER", kind := "filler"]

    ## sentinel codes of numeric fields: unknown / not stated / not applicable
    miss <- val[block == 1L & name %in% lay[kind == "numeric", name] &
                grepl("unknown|not stated|not applicable", label, ignore.case = TRUE),
                .(code = list(code)), by = name]

    .nat_cache[[key]] <- list(layout = lay, values = val, missing = miss,
                              doc_length = max(lay$end))
  }
  .nat_cache[[key]]
}

#' Record layout of the natality public-use file
#'
#' One row per field, including the FILLER blocks, in record order.
#'
#' @param year Data year; see [natality_years()].
#' @param record_length Actual record length of the file, if it differs from
#'   the length the User Guide gives (1330 for 2025). Extra bytes at the end are
#'   added as a trailing `FILLER`, so that [natality_pack()] keeps them. `NULL`
#'   (the default) uses the documented length.
#' @return A `data.table` with columns `start`, `end`, `width`, `name`, `group`,
#'   `description`, `kind` (`"numeric"`, `"code"` or `"filler"`) and `col`, a
#'   unique column name (`FILLER_<start>` for fillers, the field name otherwise).
#' @source The underlying public-use file is downloaded from NCHS at
#'   <https://www.cdc.gov/nchs/data_access/vitalstatsonline.htm#Downloadable>;
#'   this layout describes its byte positions and is not itself downloaded
#'   from there.
#' @examples
#' lay <- natality_layout()
#' lay[name == "DBWT"]
#' tail(natality_layout(record_length = 1345), 2)
#' @export
natality_layout <- function(year = 2025, record_length = NULL) {
  tb <- .nat_tables(year)
  lay <- copy(tb$layout)
  doc <- tb$doc_length
  if (!is.null(record_length)) {
    record_length <- as.integer(record_length)
    if (record_length < doc)
      stop(sprintf("record length %d is shorter than the documented %d",
                   record_length, doc), call. = FALSE)
    if (record_length > doc)
      lay <- rbind(lay, data.table(
        start = doc + 1L, end = record_length, width = record_length - doc,
        name = "FILLER", group = "",
        description = "Bytes beyond the record length given in the User Guide",
        kind = "filler"))
  }
  lay[, col := ifelse(name == "FILLER", paste0("FILLER_", start), name)]
  lay[]
}

#' Value labels of the natality public-use file
#'
#' @param year Data year; see [natality_years()].
#' @return A `data.table` with columns `name`, `code`, `label` and `block`.
#'   `block` 1 is the coding for US records. `block` 2 is the separate coding
#'   for Puerto Rico and the territories, where the guide gives one (RESTATUS,
#'   DMAR). Codes such as `"0227-8165"` are documented ranges of a numeric field.
#' @source The underlying public-use file is downloaded from NCHS at
#'   <https://www.cdc.gov/nchs/data_access/vitalstatsonline.htm#Downloadable>;
#'   these value labels describe its codes and are not themselves downloaded
#'   from there.
#' @examples
#' v <- natality_values()
#' v[name == "SEX"]
#' @export
natality_values <- function(year = 2025) copy(.nat_tables(year)$values)
