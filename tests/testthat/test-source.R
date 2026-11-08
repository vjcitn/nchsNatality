## .resolve_natality_source() / read_natality() dispatch to text vs parquet.
## See inst/adrs/0001-0004.

with_envvar <- function(vars, code) {
  old <- Sys.getenv(names(vars), unset = NA, names = TRUE)
  on.exit({
    set <- !is.na(old)
    if (any(set)) do.call(Sys.setenv, as.list(old[set]))
    if (any(!set)) Sys.unsetenv(names(old)[!set])
  })
  do.call(Sys.setenv, as.list(vars))
  force(code)
}

make_parquet_dir <- function(n = 500, seed = 2) {
  skip_if_not_installed("duckdb")
  skip_if_not_installed("DBI")
  f <- fake_natality(n, seed = seed)
  out <- file.path(tempdir(), paste0("src_test_", seed))
  suppressMessages(natality_pack(f, out, level = 1))
  list(file = f, dir = out)
}

test_that(".valid_parquet_dir requires both storage.csv and a shard", {
  d <- make_parquet_dir()
  expect_true(.valid_parquet_dir(d$dir))
  expect_false(.valid_parquet_dir(tempfile()))

  empty <- tempfile(); dir.create(empty)
  expect_false(.valid_parquet_dir(empty))

  only_shard <- tempfile(); dir.create(only_shard)
  file.copy(list.files(d$dir, "\\.parquet$", full.names = TRUE)[1],
            file.path(only_shard, "x.parquet"))
  expect_false(.valid_parquet_dir(only_shard))
})

test_that("resolution precedence matches the ADRs", {
  d <- make_parquet_dir()

  ## explicit args always win, and file= ignores NCHS_NAT_PARQUET entirely
  with_envvar(c(NCHS_NAT_PARQUET = d$dir), {
    expect_equal(.resolve_natality_source(d$file, NULL)$kind, "text")
    expect_equal(.resolve_natality_source(NULL, d$dir)$kind, "parquet")
  })
  expect_error(.resolve_natality_source(NULL, tempfile()), "not a valid parquet directory")

  ## environment-only: parquet beats text when both are set
  with_envvar(c(NCHS_NAT_PATH = d$file, NCHS_NAT_PARQUET = d$dir), {
    src <- .resolve_natality_source(NULL, NULL)
    expect_equal(src$kind, "parquet")
    expect_equal(src$path, d$dir)
  })
  with_envvar(c(NCHS_NAT_PATH = d$file, NCHS_NAT_PARQUET = ""), {
    src <- .resolve_natality_source(NULL, NULL)
    expect_equal(src$kind, "text")
    expect_equal(src$path, d$file)
  })
  with_envvar(c(NCHS_NAT_PATH = "", NCHS_NAT_PARQUET = ""),
              expect_error(.resolve_natality_source(NULL, NULL), "no natality source"))
})

## natality_pack() sorts and shards rows for compression (documented), so
## rows from the parquet path are the same set but not the same order as
## from text; sort both by every column before comparing. as.data.frame()
## drops vroom's internal `spec`/`problems` attributes, which are irrelevant
## here (see test-read.R's similar use of all.equal() for the same reason).
sorted_rows <- function(dt) {
  dt <- setorderv(copy(dt), names(dt))
  attr(dt, "spec") <- NULL
  attr(dt, "problems") <- NULL
  as.data.frame(dt)
}

test_that("read_natality gives the same rows (as a set) from text and from parquet", {
  d <- make_parquet_dir()
  cols <- c("MAGER", "DBWT", "BMI", "SEX", "DOB_MM")

  for (raw in c(FALSE, TRUE)) for (nu in c(TRUE, FALSE)) {
    a <- read_natality(d$file, cols = cols, raw = raw, na_unknown = nu)
    b <- read_natality(parquet_dir = d$dir, cols = cols, raw = raw, na_unknown = nu)
    expect_equal(sorted_rows(a), sorted_rows(b), info = sprintf("raw=%s na_unknown=%s", raw, nu))
  }

  ## n_max is honoured by the parquet path too
  expect_equal(nrow(read_natality(parquet_dir = d$dir, cols = cols, n_max = 10)), 10L)

  ## resolves from the environment when neither argument is given
  with_envvar(c(NCHS_NAT_PATH = d$file, NCHS_NAT_PARQUET = d$dir), {
    env <- read_natality(cols = cols)
    expect_equal(sorted_rows(env), sorted_rows(read_natality(parquet_dir = d$dir, cols = cols)))
  })

  expect_error(read_natality(parquet_dir = d$dir, cols = "NOPE"), "unknown field")
})
