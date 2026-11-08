test_that("natality_sql builds a select", {
  s <- natality_sql("x.txt", c("DOB_MM", "DBWT"))
  expect_match(s, "substr\\(line, 13, 2\\)")
  expect_match(s, "substr\\(line, 504, 4\\)")
  expect_error(natality_sql("x.txt", "NOPE"))
})

test_that("pack, verify and unpack are lossless, including trailing bytes", {
  skip_if_not_installed("duckdb")
  skip_if_not_installed("DBI")
  f <- fake_natality(400, tail = c("   2025  0001  ", strrep(" ", 15)), eol = "\r\n")
  out <- file.path(tempdir(), "nat2025test")
  res <- suppressMessages(natality_pack(f, out, level = 3))
  expect_true(res$verified)
  expect_equal(res$storage[start == 1331L, rule], "raw")
  expect_true(all(res$storage[kind == "numeric" & name != "BMI", rule] == "int"))
  expect_true(file.exists(file.path(out, "storage.csv")))
  expect_gte(nrow(res$report), 12L)

  rb <- tempfile(fileext = ".txt")
  suppressMessages(natality_unpack(out, rb))
  expect_identical(sort(readLines(rb)), sort(readLines(f)))

  ## a one-byte change in the source must be detected
  L <- readLines(f); substr(L[7], 504, 504) <- if (substr(L[7], 504, 504) == "1") "2" else "1"
  f2 <- tempfile(fileext = ".txt"); writeLines(L, f2)
  expect_false(suppressMessages(natality_verify(f2, out)))

  ## single file, unsorted, 1330-byte records
  f3 <- fake_natality(100)
  r3 <- suppressMessages(natality_pack(f3, file.path(tempdir(), "single"), shard_by = NULL,
                                       sort_by = character(0), level = 3))
  expect_true(r3$verified)
  expect_equal(nrow(r3$report), 1L)
  expect_false(any(r3$storage$start > 1330L))
  expect_error(suppressMessages(natality_pack(f3, tempdir(), shard_by = "NOPE")), "shard_by")
})
