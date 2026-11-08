# nchsNatality: read and losslessly pack NCHS natality public-use files

The NCHS natality public-use file is fixed width: one record per birth,
no delimiters and no quoting. That defeats delimiter-sniffing readers
such as
[`data.table::fread()`](https://rdrr.io/pkg/data.table/man/fread.html).
This package reads the file by byte position, using a record layout and
value labels extracted from the NCHS User Guide.

## Details

Main functions:

- [`check_natality_file()`](https://github.com/vjcitn/nchsNatality/reference/check_natality_file.md)
  reports line endings and record length.

- [`diagnose_layout()`](https://github.com/vjcitn/nchsNatality/reference/diagnose_layout.md)
  checks that the documented layout fits the file.

- [`read_natality()`](https://github.com/vjcitn/nchsNatality/reference/read_natality.md)
  reads fields into a `data.table`, typed or raw.

- [`label_natality()`](https://github.com/vjcitn/nchsNatality/reference/label_natality.md)
  turns categorical codes into labelled factors.

- [`natality_pack()`](https://github.com/vjcitn/nchsNatality/reference/natality_pack.md)
  writes compact, sharded Parquet that is checked to be lossless;
  [`natality_verify()`](https://github.com/vjcitn/nchsNatality/reference/natality_verify.md)
  and
  [`natality_unpack()`](https://github.com/vjcitn/nchsNatality/reference/natality_unpack.md)
  go with it.

- [`natality_layout()`](https://github.com/vjcitn/nchsNatality/reference/natality_layout.md)
  and
  [`natality_values()`](https://github.com/vjcitn/nchsNatality/reference/natality_values.md)
  return the layout and the value labels.

## Layout source

"User Guide to the 2025 Natality Public Use File" (NCHS), record layout.
`data-raw/parse_userguide.py` in the source package regenerates the
tables and lists the corrections made to errors in the guide.

## Author

**Maintainer**: Vince Carey <stvjc@channing.harvard.edu>
