#' nchsNatality: read and losslessly pack NCHS natality public-use files
#'
#' The NCHS natality public-use file is fixed width: one record per birth, no
#' delimiters and no quoting. That defeats delimiter-sniffing readers such as
#' [data.table::fread()]. This package reads the file by byte position, using a
#' record layout and value labels extracted from the NCHS User Guide.
#'
#' Main functions:
#' * [check_natality_file()] reports line endings and record length.
#' * [diagnose_layout()] checks that the documented layout fits the file.
#' * [read_natality()] reads fields into a `data.table`, typed or raw.
#' * [label_natality()] turns categorical codes into labelled factors.
#' * [natality_pack()] writes compact, sharded Parquet that is checked to be
#'   lossless; [natality_verify()] and [natality_unpack()] go with it.
#' * [natality_layout()] and [natality_values()] return the layout and the
#'   value labels.
#'
#' @section Data source:
#' The natality public-use files themselves are downloaded from NCHS at
#' <https://www.cdc.gov/nchs/data_access/vitalstatsonline.htm#Downloadable>;
#' this package does not bundle or redistribute them.
#'
#' @section Layout source:
#' "User Guide to the 2025 Natality Public Use File" (NCHS), record layout.
#' `data-raw/parse_userguide.py` in the source package regenerates the tables
#' and lists the corrections made to errors in the guide.
#'
#' @keywords internal
#' @import data.table
#' @importFrom vroom vroom_fwf fwf_positions cols col_character
"_PACKAGE"

utils::globalVariables(c(
  "start", "end", "width", "name", "col", "kind", "code", "label", "block",
  "group", "description", "rule", "type", "n_records", "blank_all", "int_ok",
  "max_int", "left_ok", "right_ok", "nonblank", "bad", "mb", "."))
