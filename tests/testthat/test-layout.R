test_that("layout is contiguous and matches the guide", {
  lay <- natality_layout()
  expect_equal(lay$start[1], 1L)
  expect_equal(lay$start[-1], lay$end[-nrow(lay)] + 1L)
  expect_equal(max(lay$end), 1330L)
  expect_equal(sum(lay$name != "FILLER"), 234L)
  expect_true(all(lay$end - lay$start + 1L == lay$width))
  expect_false(anyDuplicated(lay$col) > 0)
  expect_equal(lay[name == "DBWT", c(start, end)], c(504L, 507L))
})

test_that("record_length adds a trailing filler", {
  lay <- natality_layout(record_length = 1345)
  expect_equal(tail(lay, 1)[, c(start, end, width)], c(1331L, 1345L, 15L))
  expect_equal(tail(lay$col, 1), "FILLER_1331")
  expect_error(natality_layout(record_length = 1000), "shorter")
  expect_error(natality_layout(1999), "no bundled layout")
})

test_that("value labels look right", {
  v <- natality_values()
  expect_setequal(v[name == "SEX", code], c("M", "F"))
  expect_true(all(v[name == "DMAR", unique(block)] %in% 1:2))
  expect_equal(v[name == "ILP_R11" & block == 1, code][1:9], sprintf("%02d", 0:8))
})
