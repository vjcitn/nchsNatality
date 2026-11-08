test_that("diagnose_layout finds no problems in a conforming file", {
  d <- diagnose_layout(fake_natality(300))
  expect_s3_class(d, "natality_diagnosis")
  expect_equal(nrow(d$bad_fields), 0L)
  expect_equal(nrow(d$filler_nonblank), 0L)
  expect_output(print(d), "undocumented values: none")
})

test_that("diagnose_layout locates a shift and summarises trailing bytes", {
  d <- diagnose_layout(fake_natality(300, shift_at = 300))
  expect_gt(nrow(d$bad_fields), 0L)
  ## The shift is inserted at byte 300, inside the field that starts at 299.
  ## So the first bad field's start is <= 300.
  expect_lte(min(d$bad_fields$start), 300L)
  expect_gte(min(d$bad_fields$start), 295L)
  dt <- diagnose_layout(fake_natality(50, tail = "   2025  0001  "))
  expect_equal(names(dt$tail_nonblank)[1], "1331")
  expect_equal(unname(dt$tail_nonblank["1331"]), 0)
  expect_equal(unname(dt$tail_nonblank["1334"]), 1)
})
