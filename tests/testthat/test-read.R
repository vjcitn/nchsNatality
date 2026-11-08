test_that("check_natality_file reports terminator and length", {
  f <- fake_natality(20, tail = strrep(" ", 15), eol = "\r\n")
  r <- check_natality_file(f)
  expect_equal(r$terminator, "CRLF")
  expect_equal(r$record_length, 1345L)
  expect_output(check_natality_file(f), "documents 1330")
})

test_that("read_natality matches substr of the raw records", {
  f <- fake_natality(300)
  L <- readLines(f)
  z <- read_natality(f, raw = TRUE)
  expect_equal(dim(z), c(300L, 234L))
  for (v in c("DOB_MM", "DBWT", "SEX", "BMI", "F_CA_HEART")) {
    s <- natality_layout()[name == v]
    x <- trimws(substr(L, s$start, s$end)); x[x == ""] <- NA
    expect_identical(z[[v]], x, info = v)
  }
})

test_that("typed read converts numerics and sentinels", {
  f <- fake_natality(300)
  z <- read_natality(f, cols = c("DBWT", "BMI", "MAGER", "SEX"))
  expect_type(z$DBWT, "integer")
  expect_type(z$BMI, "double")
  expect_type(z$SEX, "character")
  expect_false(any(z$DBWT == 9999L, na.rm = TRUE))
  zr <- read_natality(f, cols = "DBWT", na_unknown = FALSE)
  expect_true(all(is.na(z$DBWT) == (is.na(zr$DBWT) | zr$DBWT == 9999L)))
  expect_error(read_natality(f, cols = "NOPE"), "unknown field")
})

test_that("trailing bytes beyond the layout do not disturb reading", {
  f1 <- fake_natality(100, seed = 3)
  f2 <- fake_natality(100, seed = 3, tail = "ABCDEFGHIJKLMNO", eol = "\r\n")
  ## Use all.equal (not identical) so that vroom's internal problem-pointer
  ## attribute differences between LF and CRLF files do not cause spurious fails.
  expect_true(isTRUE(all.equal(as.data.frame(read_natality(f1)),
                               as.data.frame(read_natality(f2)))))
})

test_that("label_natality gives labelled factors", {
  dt <- data.table::data.table(SEX = c("M", "F", NA), MAGE_IMPFLG = c(NA, "1", NA),
                               RESTATUS = c("1", "4", "2"), DBWT = 1:3)
  l <- label_natality(dt)
  expect_equal(as.character(l$SEX), c("Male", "Female", NA))
  expect_equal(as.character(l$MAGE_IMPFLG)[1], natality_values()[name == "MAGE_IMPFLG" & code == "Blank", label])
  expect_identical(l$DBWT, 1:3)
  lt <- label_natality(dt, cols = "RESTATUS", territory = TRUE)
  expect_match(as.character(lt$RESTATUS[1]), "Territory")
  expect_equal(levels(label_natality(data.table::data.table(SEX = "Q"))$SEX), c("Male", "Female", "Q"))
})
