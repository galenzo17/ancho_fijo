# ancho_fijo

[![Hex.pm](https://img.shields.io/hexpm/v/ancho_fijo.svg)](https://hex.pm/packages/ancho_fijo)
[![Docs](https://img.shields.io/badge/hexdocs-ancho__fijo-blue.svg)](https://hexdocs.pm/ancho_fijo)
[![CI](https://github.com/galenzo17/ancho_fijo/actions/workflows/ci.yml/badge.svg)](https://github.com/galenzo17/ancho_fijo/actions/workflows/ci.yml)

Fixed-width file reading that starts by distrusting the file.

This is the English guide. The API, the option names and the diagnostic prose
are in Spanish, on purpose; the [glossary](#glossary) at the end maps every
name, and [Why the API is in Spanish](#why-the-api-is-in-spanish) explains the
decision and the path for an English facade. The Spanish README,
[README.md](README.md), is the primary document; this one covers the same
ground and a test keeps the two glossaries in sync.

## The problem

The client sends the technical annex. It says: 120 positions per line, UTF-8,
amount in positions 61 to 72 with two implicit decimals. You write the parser,
try it on the sample file that came in the email, it works, it ships.

Then the real file arrives. It has 118 positions. Names come in latin-1 and the
accents turned into question marks. Three rows out of ten thousand have a blank
date. And in week two an operator exported the payroll from Excel and the file
became a semicolon-separated CSV, still called `nomina.txt`.

None of that is hard to handle. The problem is *when* you find out: after
writing the parser, with the project delivered, on a Friday. This library
exists to move that discovery to day one, and so that when something fails the
error says what happened instead of `{:error, :invalid}`.

## Installation

```elixir
def deps do
  [{:ancho_fijo, "~> 0.3.1"}]
end
```

No runtime dependencies.

## First, interrogate the file

Before writing a single line of layout: `detectar/2` (detect). It takes the
content or a path and answers "is this really what they told me it is?".

```elixir
{:ok, reporte} = AnchoFijo.detectar("nomina.txt")

reporte.probablemente_ancho_fijo?    # probably fixed width?
# => false

reporte.observaciones                # observations
# [
#   "hay 4 largos de línea distintos: 28 (1 línea), 41 (1 línea), 45 (1 línea), 46 (1 línea);
#    el predominante es 28, así que el resto son las filas sospechosas",
#   "todos los bytes son ASCII: latin-1 y UTF-8 dan el mismo resultado en este archivo",
#   "las líneas terminan en LF (\\n), estilo Unix",
#   "el carácter \";\" aparece 3 veces en todas las líneas y en posiciones variables:
#    esto parece un archivo delimitado, no de ancho fijo"
# ]
```

Four distinct line lengths; the `;` appears three times on every line at
varying positions: this looks like a delimited file, not fixed width. That file
was called `.txt` and was a CSV. The detection is not "it has semicolons": it is
that the count of semicolons per line is identical and their positions are not.
A fixed-width format that uses `|` as a decorative separator has the delimiter
in the same column every time, and `detectar/2` does not give that false
positive.

The other everyday case, the encoding:

```elixir
{:ok, reporte} = AnchoFijo.detectar("nomina.txt")

reporte.encoding_probable            # probable encoding
# => :latin1

reporte.observaciones
# [
#   "todas las 2 líneas miden 48 bytes",
#   "hay bytes que no son UTF-8 válido pero sí caracteres latin-1
#    (el byte 0xC9 en la posición 14 de la línea 1); declare encoding: :latin1 en el layout",
#   "las líneas terminan en LF (\\n), estilo Unix"
# ]
```

Bytes that are not valid UTF-8 but are latin-1 characters (byte 0xC9 at
position 14 of line 1): declare `encoding: :latin1` in the layout. And if you
already have the layout the annex declares, you can check the file against it:

```elixir
{:ok, reporte} = AnchoFijo.detectar("nomina.txt", layout: layout)

AnchoFijo.Detector.contrastar(reporte, layout)   # contrast
# [
#   %AnchoFijo.Diagnostico{
#     esperado: "un largo de línea de 50 bytes según el layout",
#     recibido: "48",
#     causa_probable: "el archivo tiene 2 bytes menos por línea: falta un campo,
#                      o el layout es de otra versión del formato"
#   }
# ]
```

Expected a 50-byte line according to the layout, got 48; the file has 2 bytes
less per line: a field is missing, or the layout is from another version of
the format. An empty list means the file and the specification agree on
everything that can be verified without parsing. That is what you want to see
on day one.

The full report has `:largos` (lengths), `:largo_consistente?`,
`:largo_predominante`, `:encoding_probable`, `:bytes_no_utf8`, `:terminador`
(line terminator), `:termina_con_terminador?`, `:delimitadores`,
`:delimitador_sugerido` and `:probablemente_ancho_fijo?`. See
`AnchoFijo.Detector`.

### From the terminal

On day one there is no project and no `iex`: there is a file that arrived by
email. The same question, as a command:

```
$ mix ancho_fijo.detectar nomina.txt
nomina.txt: probablemente de ancho fijo
  3 líneas · largo 48 bytes, consistente · ascii · LF
  - todas las 3 líneas miden 48 bytes
  - todos los bytes son ASCII: latin-1 y UTF-8 dan el mismo resultado en este archivo
  - las líneas terminan en LF (\n), estilo Unix
```

`--layout nomina.exs` contrasts against a layout, `--json` prints the report
for `jq`, and the exit code serves a pre-validation script: `0` if it looks
fixed width and agrees, `1` if not, `2` if the file could not be read. See
`mix help ancho_fijo.detectar`.

## Then, parse

The layout is data: a list of fields with name, length, type and cleanup
options. Changing formats is changing the map.

```elixir
layout =
  AnchoFijo.Layout.nuevo!(                       # new!
    nombre: "nómina banco X",                    # name
    encoding: :latin1,
    campos: [                                    # fields
      [nombre: :rut, largo: 10],                 # name, length
      [nombre: :beneficiario, largo: 20],
      [nombre: :monto, largo: 10, tipo: :decimal, precision: 2],
      [nombre: :fecha, largo: 8, tipo: :fecha, formato: :aaaammdd]   # date, format YYYYMMDD
    ]
  )

AnchoFijo.parsear(layout, "nomina.txt")          # parse
# {:ok,
#  [
#    %{rut: "12345678-9", beneficiario: "JOSÉ MUÑOZ PEÑA", monto: {125000, 2}, fecha: ~D[2024-01-15]},
#    %{rut: "98765432-1", beneficiario: "MARÍA ROJAS ÑAÑEZ", monto: {9990050, 2}, fecha: ~D[2024-01-15]}
#  ],
#  []}
```

Positions were omitted: each field chains after the previous one. When the
annex declares them ("positions 61 to 72"), you make them explicit with
`posicion:`, 1-based, just like the annex.

### The two modes

Both return `{:ok, registros, diagnosticos}` (records, diagnostics). The third
element carries the errors of the rows that could not be read and the warnings
of the rows that were read under an assumption; `AnchoFijo.Diagnostico.separar/1`
splits them in two.

Strict (`modo: :estricto`, the default) stops at the first line with problems:

```elixir
AnchoFijo.parsear(layout, "nomina.txt")
# {:error, [%AnchoFijo.Diagnostico{...}]}

# línea 2: se esperaban 48 bytes, llegaron 46; posible campo faltante o archivo delimitado
# (line 2: expected 48 bytes, got 46; possible missing field or delimited file)
```

Tolerant (`modo: :tolerante`) returns the good rows and the diagnostics of the
bad ones, because a 10,000-row payroll with 3 bad rows must report the 3, not
drop the batch:

```elixir
{:ok, buenas, malas} = AnchoFijo.parsear(layout, "nomina.txt", modo: :tolerante)

length(buenas)
# => 2

Enum.map(malas, &AnchoFijo.Diagnostico.mensaje/1)       # message
# ["línea 2: se esperaban 48 bytes, llegaron 46; posible campo faltante o archivo delimitado"]
```

Note that tolerant mode returns `:ok`: a batch with bad rows separated from
the good ones is a result, not a failure. `{:error, _}` is reserved for what
prevents processing anything at all, an invalid layout or an unreadable file,
where there is nothing to rescue.

In strict mode the list can only carry warnings: an error would have stopped
the run. And an error also drops the warnings of the lines already read: there
is no partial result to attach them to.

### When there is nothing to do but fail

A migration script, a `Mix.Task`, a pipeline where a bad file leaves nothing to
rescue: there the tuple gets in the way. `parsear!/3` and `detectar!/2` follow
the stdlib convention, return the value or raise `AnchoFijo.Error`, whose
message is the report of the diagnostics:

```elixir
registros = AnchoFijo.parsear!(layout, "nomina.txt")
# ** (AnchoFijo.Error) línea 2: se esperaban 48 bytes, llegaron 46; posible campo faltante o archivo delimitado
```

With `modo: :tolerante` the `!` still raises when there are bad rows, but the
exception carries **all** the errors of the file, not the first one: it is the
combination for the script that has to die, but whose operator needs the full
list to fix the file in one go. The alternative, returning the good rows and
discarding the diagnostics, would have made `!` a shortcut that loses
information silently, and a `!` is not a shortcut: it is another contract.

What `!` does not return are the warnings. They are rows that were read under
an assumption the layout declared, and the function returns a single value. If
they matter, `parsear/3` returns them in the third position.

### Large files

```elixir
"cartola.txt"
|> File.stream!()
|> then(&AnchoFijo.stream(layout, &1))
|> Stream.filter(&match?({:ok, _, _}, &1))
|> Stream.map(fn {:ok, registro, _advertencias} -> registro.monto end)
|> Enum.reduce(0, fn {unidades, _precision}, total -> total + unidades end)
```

Measured on a 100 MB file (two million lines): `stream/3` walks it in 5
seconds with a 34 KB heap peak that does not depend on the file size;
`parsear/3` in tolerant mode takes twice as long and retains 1.2 GB, because it
returns the two million records. Numbers, machine and script are in
`bench/README.md`.

`stream/3` emits `{:ok, registro, advertencias}` or `{:error, diagnosticos}`
per line. What to do with the errors is the consumer's decision: accumulating
every diagnostic of a 2 GB file to return them at the end would defeat the
point of being lazy. Warnings travel attached to their record for the same
reason: there is nowhere to collect them.

### Writing with the same layout

To send the payroll to the bank you have to generate it in the annex's format,
and the format is already written once. `escribir/3` (write) is the inverse of
`parsear/3`, and the property that defines it is the round trip: what is
written reads back the same.

```elixir
{:ok, contenido, []} = AnchoFijo.escribir(layout, registros)
File.write!("nomina.txt", contenido)

# or line by line, without building the file in memory:
layout
|> AnchoFijo.Escritor.stream(registros)
|> Stream.map(fn {:ok, linea, _advertencias} -> linea end)
|> Stream.into(File.stream!("nomina.txt"))
|> Stream.run()
```

There is no tolerant mode for writing: a payroll with one row less is another
file, and sending it is worse than not sending it. If a value cannot be
written, `escribir/3` returns every diagnostic of every record, with the record
number, the field, the positions and the cause.

**What does not fit is not truncated.** A truncated amount is another amount, a
truncated RUT is another person, a truncated free-text note is the only one of
the three that is sometimes acceptable. That is why a value wider than its
field is an error, and `truncar: true` (truncate) exists only for `:texto`,
with a warning per truncated field. Text is padded on the side that `:trim`
strips when reading, numbers with leading zeros and the sign only on negatives,
a `{unidades, precision}` must carry the field's precision (scaling is where
the cent gets lost), and the layout's encoding is respected: with
`encoding: :latin1` the file comes out in latin-1, and a character latin-1 does
not have is a diagnostic with the character and its position.

### Bytes or characters, also when writing

The classic bug of a fixed-width writer built on `String.pad_trailing` is to
measure characters: "José" is four of them, but in UTF-8 it takes five bytes,
and a four-byte field that receives five shifts every column that follows.
This library measures when writing in the same unit it reads: `:bytes` by
default, in the layout's encoding (or the field's, if it declares one), or
`:caracteres` (characters) if the layout says so.

```elixir
layout = AnchoFijo.Layout.nuevo!(campos: [[nombre: :nombre, largo: 4]])

AnchoFijo.escribir(layout, [%{nombre: "añ"}])
# => {:ok, "añ \n", []}            # 2 characters, 3 bytes: one byte left, one space goes in

{:error, [d]} = AnchoFijo.escribir(layout, [%{nombre: "José"}])
d.causa_probable
# => "el valor no cabe en el campo: 5 posiciones en 4 (5 bytes, 4 caracteres)"

AnchoFijo.escribir(layout, [%{nombre: "a€bc"}], truncar: true)
# => {:ok, "a€\n", [advertencia]}  # the cut lands on a character boundary: 1 + 3 bytes
```

With `truncar: true` the cut never splits a character: the text is trimmed by
graphemes until it fits and the leftover byte is filled with a space. Without
`truncar:`, the diagnostic states the length in both units when they differ,
which is what explains why "four letters" do not fit in four positions. With
`encoding: :latin1` the value is transcoded before measuring, so "añoo" takes
four bytes, and a character latin-1 does not have (`"€"`) is an `:encoding`
diagnostic with the character's position, never a silent `?`. With
`unidad: :caracteres` graphemes are counted, the same as when reading.

There is one case no measuring fixes: a `:relleno` (padding character) that
takes more than one byte (`"·"`) in a layout measured in bytes in UTF-8.
Repeating it as many times as bytes are missing cannot give the exact length.
`Layout.nuevo!/1` leaves a warning in `layout.advertencias`, and trying to
write that field is an error. The regression tests for all of this live in
`test/ancho_fijo/escritura_en_bytes_test.exs`, with a property that writes
texts with accents, ñ, `€` and emojis in the three configurations and measures
every line in the layout's unit.

### Short lines because the padding was trimmed

Some senders trim the trailing spaces of every line, or only of the last one.
With the layout as is, that line is a length diagnostic and the row is
dropped. If the format ends in a text field, a note, a reference, what is
missing is padding, not data, and you can declare it:

```elixir
layout = AnchoFijo.Layout.nuevo!(
  relleno_final: :tolerar,          # trailing padding: tolerate
  campos: [
    [nombre: :rut, largo: 10],
    [nombre: :fecha, largo: 8, tipo: :fecha, formato: :aaaammdd],
    [nombre: :monto, largo: 12, tipo: :decimal, precision: 2],
    [nombre: :glosa, largo: 30]
  ]
)

{:ok, registros, advertencias} = AnchoFijo.parsear(layout, "nomina.txt")

Enum.map(advertencias, &AnchoFijo.Diagnostico.mensaje/1)
# ["línea 1: se esperaban 60 bytes, llegaron 47; se completaron 13 bytes de relleno
#   al final de la línea; el emisor recorta los espacios finales y el layout lo tolera"]
```

The line is completed with the field's padding character and there is one
warning per completed line, with how many units were missing. The rule is
narrow on purpose: missing **padding** is tolerated, missing bytes are not.
The restorable zone starts at the end of the line and grows backwards while it
finds undeclared padding or `:texto` fields with the same padding character.
An `:entero`, a `:decimal` or a `:fecha` stop it: there the width is the data,
and a short line that reaches them is still a length error, even if a single
byte is missing. The diagnostic says how many units were missing and how many
were restorable.

Without the option nothing changes: the default is `:estricto`.

With `unidad: :caracteres` the count is in characters and the line is completed
after transcoding, so `"JOSÉ MUÑOZ"` in a 12-wide note is completed with 2
characters, not the 0 that counting bytes would suggest. With `unidad: :bytes`
only ASCII padding is restored: a multibyte character repeated as many times as
bytes are missing does not rebuild the line, and that field does not enter the
restorable zone.

## Header, detail and trailer

Real payrolls and statements carry several record types, each line says which
one it is in its first positions, order matters and the trailer has totals that
must add up. `AnchoFijo.Multiregistro` (multi-record) is a layout of layouts
plus those rules, and `parsear/3` and `stream/3` accept it in place of the
layout:

```elixir
nomina = AnchoFijo.Multiregistro.nuevo!(
  discriminador: [posicion: 1, largo: 2],              # discriminator
  registros: [                                         # records
    header:  [valor: "01", cantidad: :uno,          layout: layout_header],    # value, count: one
    detalle: [valor: "02", cantidad: :al_menos_uno, layout: layout_detalle],   # at least one
    trailer: [valor: "09", cantidad: :uno,          layout: layout_trailer]
  ],
  controles: [                                         # controls
    [en: :trailer, campo: :cantidad, cuenta: :detalle],               # count of details
    [en: :trailer, campo: :total, suma: {:detalle, :monto}]           # sum of detail amounts
  ]
)
```

Some formats have no type code: header and trailer are recognised because they
measure differently from the detail, or because they are the first and the last
line. The discriminator knows about that too:

```elixir
discriminador: [por: :largo]                 # by length: each type measures what its layout does
discriminador: [por: :posicion_en_archivo]   # by position in file: header: [ubicacion: :primera, ...], trailer: [ubicacion: :ultima, ...]
discriminador: [por: fn linea, numero -> ... end]   # for whatever does not fit above
```

Two types that measure the same are an invalid definition. With
`:posicion_en_archivo` the last line is recognised with one line of lookahead,
so `stream/3` stays in constant memory. A function is the last resort: it is
not serialised nor contrasted, `detectar/2` only counts what it returns.
`AnchoFijo.detectar(ruta, layout: multi)` says which criterion discriminates,
how many lines are of each type and how many are of none, and with a
multi-record a file with three line lengths is indeed fixed width.

When each layout declares its type code as a `:constante` field, the
discriminator points at the field and the values come from the literals:

```elixir
layout_header = [campos: [[nombre: :tipo, largo: 2, tipo: :constante, valor: "01"], ...]]

nomina = AnchoFijo.Multiregistro.nuevo!(
  discriminador: [campo: :tipo],
  registros: [header: [cantidad: :uno, layout: layout_header], ...]
)

{:ok, registros, []} = AnchoFijo.parsear(nomina, "nomina.txt")
# [header: %{...}, detalle: %{...}, detalle: %{...}, trailer: %{...}]

AnchoFijo.Multiregistro.agrupar(nomina, registros)    # group
# %{header: %{...}, detalle: [%{...}, %{...}], trailer: %{...}}
```

And the way back, with the controls computed instead of requested:

```elixir
registros = [
  header:  %{empresa: "76543210-3", fecha: ~D[2024-01-15], glosa: "SUELDOS ENERO"},
  detalle: %{rut: "12345678-5", nombre: "JUAN PEREZ SOTO", monto: {125_000, 2}, cuenta: 11_223_344},
  detalle: %{rut: "98765432-5", nombre: "ANA MARIA ROJAS", monto: {9_990_050, 2}, cuenta: 55_667_788},
  trailer: %{}                      # :cantidad and :total come from the details
]

{:ok, contenido, []} = AnchoFijo.escribir(nomina, registros)
{:ok, ^registros_con_totales, []} = AnchoFijo.parsear(nomina, contenido)
```

If the trailer carries `:cantidad` or `:total` with another value, it is a
`:control` diagnostic: nothing is overwritten silently. One trailer per
currency is declared with `agrupar_por: :moneda` (group by currency) in the
control, and is compared (when reading) or computed (when writing) against the
details of that currency. There is no lazy version of writing: the trailer
needs the totals, and the totals need every detail.

The decisions, and why:

- **Records come back as `{tipo, mapa}` in file order**, not as a map per
  type. Order is part of the data (some formats interleave types) and it is
  the only thing `stream/3` can emit one at a time. `agrupar/2` builds the map
  per type for the common case.
- **Structure is validated as lines go by; controls, at the end.** An unknown
  discriminator, a `:detalle` after the `:trailer`, a second `:header` or a
  missing `:trailer` are `:estructura` (structure) diagnostics, with the usual
  probable cause ("usually a file glued to another"). Totals need every
  detail, so they are compared at end of file: `:control` diagnostics that say
  the computed value, the declared one and what it was computed from.
- **In `stream/3` the controls come out as the last element.** An
  `{:error, diagnosticos}` after the last record if something does not add up
  or a mandatory record is missing, and nothing if everything does. The
  accumulator carries counts and sums, not records: memory stays constant.
- **In tolerant mode the controls are computed over what could be read.** An
  unreadable detail produces its diagnostic plus the one of the total that no
  longer adds up. Both are true and the second is the one the bank will
  report.
- **Sums are over integers or `{unidades, precision}`**, never floats; with
  different precisions they are compared at the larger one.

## The layout as data

A layout is an Elixir definition, and there are three situations where that is
not enough: sharing it with a service in another language, storing it in a
database next to the bank's sample files, or letting someone who does not
program edit it. `Layout.a_mapa/1` (to map) converts it into a string-keyed
map without atoms or functions, with the schema `"version"`, and
`desde_mapa/1` (from map) builds and validates it with the same diagnostics as
`nuevo/1` (an unknown key is reported). `a_json/1` and `desde_json/1` do the
same with JSON, without dependencies, and `Multiregistro` has all four.

```elixir
AnchoFijo.Layout.a_mapa(layout)
# %{"version" => 1, "nombre" => "nómina", "encoding" => "utf8", "unidad" => "bytes", "largo" => 48,
#   "campos" => [%{"nombre" => "rut", "posicion" => 1, "largo" => 10, "tipo" => "rut"}, ...]}

File.write!("nomina.json", AnchoFijo.Layout.a_json(layout))
{:ok, ^layout} = AnchoFijo.Layout.desde_json(File.read!("nomina.json"))
```

`mix ancho_fijo.detectar --layout nomina.json` and `mix ancho_fijo.documentar
nomina.json` accept the `.json` as well as the `.exs`. The JSON Schema to
validate a layout outside Elixir is in `priv/layout.schema.json`. YAML stays
out of the core on purpose, with no dependency: a `yaml_elixir` in your project
and `YamlElixir.read_from_file!/1 |> AnchoFijo.Layout.desde_mapa()` are enough,
because the map is the same. A custom type travels by its module name and comes
back through `AnchoFijo.Tipo.resolver/1`; a discriminator function cannot be
serialised and says so.

## The specification comes out of the layout

A format's specification lives twice: in the document sent to the bank and in
the layout in the code, and they drift apart without anyone noticing. If the
layout is the source of truth, the table has to come out of it. Every field
accepts `descripcion:` and `ejemplo:` (description, example), which the parser
ignores, and `mix ancho_fijo.documentar RUTA.exs [--formato markdown|csv|json] [--idioma es|en]`
(or `AnchoFijo.Layout.documentar/2` from code) prints the table. This is the
one for `test/fixtures/multiregistro_sin_codigo.exs` with `--idioma en`,
exactly as it comes out, and a test verifies this README has it without manual
editing:

## nómina sin código de tipo

Record type by line length

### header (exactly one)

| Field | Positions | Length | Type | Format | Optional | Rules | Description | Example |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `empresa` | 1-10 | 10 | RUT | check digit validated | no |  | RUT de la empresa pagadora | `76543210-3` |
| `fecha` | 11-18 | 8 | date | AAAAMMDD | no |  | Fecha de pago |  |
| `glosa` | 19-32 | 14 | text |  | no |  | Glosa libre del lote |  |

### detalle (at least one)

| Field | Positions | Length | Type | Format | Optional | Rules | Description | Example |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `rut` | 1-10 | 10 | RUT | check digit validated | no |  | RUT del beneficiario |  |
| `nombre` | 11-26 | 16 | text |  | no |  | Nombre del beneficiario |  |
| `monto` | 27-36 | 10 | decimal | 2 implicit decimals | no |  | Monto a pagar | `0000125000` |
| `cuenta` | 37-40 | 4 | integer |  | no |  | Cuenta de destino |  |

### trailer (exactly one)

| Field | Positions | Length | Type | Format | Optional | Rules | Description | Example |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `cantidad` | 1-6 | 6 | integer |  | no |  | Cantidad de detalles |  |
| `total` | 7-20 | 14 | decimal | 2 implicit decimals | no |  | Suma de los montos |  |

### Controls

- `trailer.cantidad` = count of `detalle`
- `trailer.total` = sum of `detalle.monto`

`--idioma en` translates the headers and the type names, not the field names,
which belong to the format, nor the descriptions, which the layout's author
wrote.

## Bundled formats

Real formats are public and stable, and transcribing them from scratch is the
central work of every integration. They come bundled, with their source cited
and their effective version, starting with NACHA/ACH (United States):

```elixir
{:ok, registros, []} = AnchoFijo.parsear(AnchoFijo.Formatos.nacha(), "ach.txt")
[] = AnchoFijo.Formatos.Nacha.validar(registros)   # hash, totals and counts of each batch and the file
lotes = AnchoFijo.Formatos.Nacha.lotes(registros)  # each batch with its entries and addenda
```

Formats change by regulator resolution, and a silently outdated layout is
worse than none. That is why each one is requested with its **effective
version** (`nacha(vigencia: "2021")`), which does not change when the catalogue
is updated; asking for the newest is for getting started, pinning it is for
production. `AnchoFijo.Formatos.catalogo/0` lists the versions with their
source and the date they were consulted. They are added one at a time and
complete: Previred (Chile) is next.

## Field types

| type | returned value | options |
| --- | --- | --- |
| `:texto` (text) | `String.t()` in UTF-8 | `:trim`, `:relleno` (padding), `:opcional` (optional) |
| `:entero` (integer) | `integer()` | `:opcional`, `:signo` (sign) |
| `:decimal` | `{unidades, precision}`; with `:moneda` (currency), an `AnchoFijo.Monto` | `:precision` (mandatory without `:moneda`), `:moneda`, `:separador` (separator), `:signo` |
| `:fecha` (date) | `Date.t()` | `:formato` (format, mandatory), `:pivote` (pivot), `:opcional` |
| `:hora` (time) | `Time.t()` | `:formato` (mandatory), `:opcional` |
| `:fecha_hora` (datetime) | `NaiveDateTime.t()` | `:formato` (mandatory), `:pivote`, `:opcional` |
| `:rut` | canonical `String.t()`, `"12345678-5"`; body only with `dv: :ausente` | `:dv` (check digit), `:opcional` |
| `:constante` (constant) | the literal declared in `:valor`, verified against the line | `:valor` (value, mandatory), `:relleno` |
| `:relleno` (filler) | nothing: the field does not appear in the record | `:relleno` |

An amount of `0000125000` with `precision: 2` reads as `{125000, 2}`: 125,000
minimal units with scale 2, that is 1,250.00. There is never a float on the
way. An amount that went through floating point stops reconciling with the
bank's accounting and nobody knows where the cent was lost.

`:moneda` turns the `:decimal` into an `AnchoFijo.Monto` with its ISO 4217
code, and the precision is no longer declared: it is the currency's scale. CLP
has no decimals, USD has two, KWD three; `moneda: :clp` with `precision: 2` is
an invalid layout, because reading Chilean pesos divided by a hundred is the
error nobody notices until reconciliation. `Monto.sumar/2` (add) demands the
same currency and returns a diagnostic otherwise; `total/1`, `formatear/2`
(format) and `a_decimal/1` (to Decimal) for whoever has `Decimal`.

`:signo` is `:inicial` (leading) by default: `-0125000`. Mainframe-era formats
write the sign after the digits, `0125000-`, and to read them you declare
`signo: :final` (trailing). A sign where the layout does not expect it is not a
"non-numeric character": the diagnostic says the sign is at the other end and
what to declare. EBCDIC *overpunch* (`12K` for -123) is out of scope.

`:rut` normalises whatever arrives (`12.345.678-5`, `123456785`,
`0000123456785`, with `k` or `K`) to `"12345678-5"` and validates the check
digit by modulo 11. A RUT with a bad check digit parses perfectly and the bank
rejects it days later: that is why validation is part of the type and not an
option you have to remember to turn on. Both exits are explicit:
`dv: :no_validar` to receive the data and decide later, and `dv: :ausente`
(absent) for formats that carry the body without the check digit.

`:formato` has no default on purpose. Guessing whether `01022024` is February
1st or January 2nd is exactly the silent error this library exists to prevent:
a `:fecha` field without `:formato` is an invalid layout. The named formats
cover what bank files carry (`:aaaammdd`, `:ddmmaaaa`, `:mmddaaaa`, `:aammdd`,
`:ddmmaa`, `:mmddaa`, Julian `:aaaaddd` and `:aaddd`; `:hhmmss` and `:hhmm`;
`:aaaammddhhmmss` and company, where `A` is year, `M` month, `D` day), and when
none fits `:formato` accepts a token pattern with separators: `"DD/MM/AAAA"`,
`"AAAA-MM-DD HH:MM:SS"`. A two-digit year is expanded with `:pivote`, the
first year of the hundred-year window (default `2000`): it is a decision of
the format, and that is why it is declared. The full table is in
`AnchoFijo.Tipo.Fecha`.

`:constante` and `:relleno` are the positions whose value is set by the format
and not by the data: the record type code, a literal like `"HEADER H2H"`, the
*fillers*. When reading, a literal different from the declared one is a
diagnostic with `esperado` and `recibido` (expected, received), and a filler is
not read and does not go into the record. When writing, both are emitted
without being in the map; a different literal in the map is a diagnostic,
because it is not different data, it is another format.

```elixir
[nombre: :tipo_registro, largo: 2, tipo: :constante, valor: "01"]
[nombre: :filler, largo: 946, tipo: :relleno]                 # spaces
[nombre: :ceros, largo: 15, tipo: :relleno, relleno: "0"]
```

## If you already use Decimal

`:decimal` fields return `{unidades, precision}` (or an `AnchoFijo.Monto` with
`:moneda`) so as not to force a dependency. If the project already works with
`Decimal`, as everything that goes through Ecto does, you declare it once:

```elixir
layout = AnchoFijo.Layout.nuevo!(
  decimales_como: :decimal,          # decimals as Decimal; or como: :decimal on a field
  campos: [
    [nombre: :rut, largo: 10, tipo: :rut],
    [nombre: :monto, largo: 10, tipo: :decimal, precision: 2]
  ]
)

{:ok, [%{monto: monto}], []} = AnchoFijo.parsear(layout, "12345678-50000125000\n")
# monto == Decimal.new("1250.00")

AnchoFijo.escribir(layout, [%{rut: "12345678-5", monto: Decimal.new("1250")}])
# {:ok, "12345678-50000125000\n", []}
```

When writing, any `:decimal` accepts a `%Decimal{}`, an integer (in whole
units) or a numeric string, besides the tuple and the `Monto`. A value with
more decimals than `:precision` is a diagnostic, never a silent rounding.
`Monto.desde_decimal/2` and `Monto.nuevo/3` with a `Decimal` are the way back
from `Monto.a_decimal/1`.

It is not the default on purpose: `Decimal` is optional in `ancho_fijo`, and
without the library `como: :decimal` is an invalid layout that says what to
add. The package stays free of runtime dependencies, and whoever does not use
`Decimal` does not pay for it.

## Custom types

The built-in types are implementations of the `AnchoFijo.Tipo` behaviour, and a
type that only makes sense for one user, a branch code, the "movement type"
enum of your bank, is added without touching the library: a module with
`opciones/0`, `validar/1` and `leer/3` (options, validate, read), and
`tipo: MyApp.Hora` in the layout.

```elixir
defmodule MiApp.Hora do
  @behaviour AnchoFijo.Tipo
  alias AnchoFijo.Tipo

  @impl true
  def opciones, do: []

  @impl true
  def validar(campo), do: if(campo.largo == 4, do: [], else: [Tipo.falla(campo, "un :largo de 4", campo.largo, nil)])

  @impl true
  def leer("", campo, contexto), do: {:error, Tipo.vacio(campo, contexto)}

  def leer(<<h::binary-2, m::binary-2>>, campo, contexto) do
    case Time.new(String.to_integer(h), String.to_integer(m), 0) do
      {:ok, hora} -> {:ok, hora}
      _ -> {:error, Tipo.diagnostico(campo, contexto, esperado: "una hora HHMM", recibido: inspect(h <> m))}
    end
  end
end

[nombre: :hora_pago, largo: 4, tipo: MiApp.Hora]
```

`validar/1` runs when the layout is built, not when parsing: a `:fecha`
without `:formato` is still an invalid layout, and a custom type can demand
the same. The diagnostics it produces with `Tipo.diagnostico/3` are
indistinguishable from the built-in ones. That the module implements the
behaviour is also verified when building the layout, with
`Code.ensure_loaded?/1` first: a module that does not exist or does not
implement the callbacks is a `:layout` diagnostic, not an
`UndefinedFunctionError` at line 40,000. The complete example, with a custom
option, the optional `escribir/2` (write) and `generador/1` (generator)
callbacks, is in `AnchoFijo.Tipo`.

## Domain rules go in the layout

A type says how the field is read; the domain says which values it admits. A
code that can only be `"01"`, `"02"` or `"09"`, an amount that cannot be
negative, an identifier with a fixed shape, a field that is mandatory only
when another one carries a certain value. If that is verified after
`parsear/3`, the error has already lost the line and the position. Rules are
declared on the field, with any type:

```elixir
campos: [
  [nombre: :tipo, largo: 2, en: ["01", "02", "09"]],                                            # in
  [nombre: :monto, largo: 10, tipo: :decimal, precision: 2, rango: {{0, 0}, nil}],             # range
  [nombre: :fecha, largo: 8, tipo: :fecha, formato: :aaaammdd, rango: {~D[2000-01-01], nil}],
  [nombre: :codigo, largo: 4, patron: ~r/^[A-Z]{2}\d{2}$/],                                      # pattern
  [nombre: :banco, largo: 3, tipo: :entero, opcional: true, requerido_si: [campo: :tipo, en: ["02"]]],   # required if
  [nombre: :glosa, largo: 20, opcional: true, prohibido_si: [campo: :banco]]                    # forbidden if
]
```

- `en:` is the catalogue: a list of admitted values, or a one-argument
  function for large or computed catalogues.
- `rango: {min, max}` works for `:entero`, `:decimal`, `:fecha`, `:hora` and
  `:fecha_hora`, with `nil` on the open end. It compares the converted value:
  a tuple, a `Monto`, a `Decimal` or a date, no matter how it was written.
- `patron:` is a regular expression over the trimmed text.
- `requerido_si:` and `prohibido_si:` look at another field of the same
  record: `[campo: :tipo, en: [...]]` holds when that field is one of those;
  `[campo: :banco]`, when it has a value. The layout checks that the named
  field exists.

Every failure is a `:regla` (rule) diagnostic, with the line, the field and
its positions, and `esperado` states the rule. In strict mode it rejects the
line; in tolerant mode the record is delivered and the diagnostic stays as an
error. A sensitive field redacts the value, as always. The same rules apply
when writing, so a record that does not meet them does not reach the file.
`documentar/2` shows them in the "Rules" column, the serialised layout keeps
them (except `en:` with a function, which is not data) and the generators of
`AnchoFijo.Test.Generadores` respect them: they pick from the catalogue, stay
within the range and satisfy the cross conditions. A `patron:` cannot be
inverted, so that field asks for `generador:` with a `StreamData` of your own.

## Testing your layout

Whoever adopts the library writes the same tests every time. `AnchoFijo.Test`
makes each one a single line, and with `StreamData` the round trip becomes a
property over records generated from the layout:

```elixir
defmodule MiApp.NominaTest do
  use ExUnit.Case
  use ExUnitProperties
  import AnchoFijo.Test

  @layout MiApp.Nomina.layout()

  test "a valid line" do
    assert_parsea(@layout, "12345678-5JUAN PEREZ  0012345620240131", %{rut: "12345678-5", monto: {123_456, 2}, ...})
  end

  test "an amount with letters is diagnosed on the amount" do
    @layout |> AnchoFijo.parsear("12345678-5JUAN PEREZ  00AB345620240131\n") |> assert_diagnostico(campo: :monto)
  end

  property "writing and reading gives the same for any record" do
    check all registro <- AnchoFijo.Test.Generadores.registro(@layout), do: assert_round_trip(@layout, registro)
  end
end
```

`assert_parsea` (asserts it parses), `assert_diagnostico`, `assert_round_trip`
and `assert_escribe` (asserts it writes). The generators respect every field
(length, sign, precision or currency, date format, RUT check digit, optionals,
constants, rules) and also generate the `{tipo, mapa}` list of a multi-record;
`linea_invalida/1` (invalid line) gives a line with one broken field annotated,
to test that the diagnostic points where it should. A custom type takes part
through the optional `generador/1` callback. The library's own suite runs these
properties over its fixtures, NACHA included.

## The layout is validated before seeing the file

```elixir
AnchoFijo.Layout.nuevo(campos: [
  [nombre: :rut, posicion: 1, largo: 10],
  [nombre: :nombre, posicion: 8, largo: 20]
])
# {:error, [%AnchoFijo.Diagnostico{...}]}

# layout, campo :nombre (posiciones 8-27): se esperaba que empezara en la posición 11
# o después, llegó 8; se solapa con el campo :rut (posiciones 1-10)
# (expected it to start at position 11 or later, got 8; it overlaps field :rut)
```

Gaps are different: they are warnings, not errors. A gap is usually a
legitimate reserved zone of the format, while an overlap is always a
transcription error from the annex.

```elixir
{:ok, layout} = AnchoFijo.Layout.nuevo(campos: [
  [nombre: :rut, posicion: 1, largo: 10],
  [nombre: :monto, posicion: 21, largo: 10, tipo: :decimal, precision: 2]
])

Enum.map(layout.advertencias, &AnchoFijo.Diagnostico.mensaje/1)
# ["layout, campo :monto (posiciones 21-30): se esperaba que empezara en la posición 11,
#   llegó 21; quedan 10 posiciones sin declarar entre :rut y :monto;
#   si el formato tiene relleno ahí, ignore esta advertencia"]
```

## Repeated groups and variants

Two constructs of mainframe-era formats: a block of fields that repeats N
times (`OCCURS`), and a stretch of the record that changes shape according to
the value of an earlier field (`REDEFINES`):

```elixir
[nombre: :totales, tipo: :grupo, repetir: 3, campos: [          # group, repeat
  [nombre: :moneda, largo: 3],
  [nombre: :importe, largo: 10, tipo: :decimal, precision: 2]
]]
# registro.totales == [%{moneda: "CLP", importe: {125_000, 2}}, %{moneda: "USD", ...}, %{moneda: "EUR", ...}]

[nombre: :destino, tipo: :variante, segun: :tipo_cuenta, variantes: %{    # variant, according to
  "01" => [[nombre: :banco, largo: 3], [nombre: :cuenta, largo: 15, tipo: :entero]],
  "02" => [[nombre: :clabe, largo: 18]]
}]
# registro.destino == %{banco: "001", cuenta: 12_345_678}  or  %{clabe: "0123..."}
```

The group's length is computed (`repetir` times that of one repetition) and
the variants measure the same, or the field declares a `largo` and the shorter
ones are padded. A value with no variant is a diagnostic listing the declared
ones, and a broken inner field is diagnosed with its path and its absolute
position in the line: `campo totales[2].importe (posiciones 29-38)`. Writing is
symmetric, `documentar` shows the inner fields with relative positions, and the
generators of `AnchoFijo.Test` produce the right list and variant.

## Mixed encodings per field

A frequent case in bank responses: the file is measured in bytes and comes in
latin-1, except the free-text field, which comes in UTF-8. Decoding everything
as latin-1 gives `operaciÃ³n`; decoding everything as UTF-8 shifts the
offsets. The encoding is declared per field:

```elixir
AnchoFijo.Layout.nuevo!(
  encoding: :latin1,
  campos: [
    [nombre: :rut, largo: 10, tipo: :rut],
    [nombre: :nombre, largo: 14],
    [nombre: :mensaje, largo: 24, encoding: :utf8],
    [nombre: :fecha, largo: 8, tipo: :fecha, formato: :aaaammdd]
  ]
)
```

`detectar/2` recognises the mix (`encoding_probable: :mixto`) and suggests that
declaration; `unidad_probable` says in which unit the lengths are consistent
when there are multibyte characters. And if a `:texto` arrives already
double-encoded, there is a `:doble_codificacion` warning with the repaired
text; `reparar_doble_codificacion: true` on the field applies the repair when
reading. A field that starts in the middle of a multibyte character says so,
instead of reporting some latin-1 byte.

## Diagnostics for end users and for an API

A diagnostic's message is for the integrator. A file-upload screen needs to
tell the user "line 42: the amount is not valid" in their language and without
layout options, and an API needs JSON:

```elixir
AnchoFijo.Diagnostico.mensaje(d, audiencia: :usuario)          # audience: user
# "Línea 42, campo monto: el valor no es válido (se esperaba 8 dígitos con 2 decimales implícitos, llegó "AB")."
AnchoFijo.Diagnostico.mensaje(d, audiencia: :usuario, idioma: :en)   # language: en
# "Line 42, field monto: the value is not valid (expected 8 dígitos con 2 decimales implícitos, got "AB")."

AnchoFijo.Diagnostico.a_mapa(d)        # stable keys, with :mensaje; and desde_mapa/1 for the way back
Jason.encode!(diagnosticos)            # with Jason in the project: optional Jason.Encoder, redacted

AnchoFijo.resumen(diagnosticos)        # summary
# %{errores: 2, advertencias: 1, lineas_afectadas: [2, 7, 9], veredicto: :rechazable,
#   texto: "2 errores en 2 líneas y 1 advertencia: el archivo se rechaza", ...}
```

What the library translates is the frame of the message and the explanation
per kind of problem; what each type describes in `esperado` and `recibido` is
Spanish prose and is shown as is. Every output respects `:sensible`.

## Personal data does not travel in diagnostics

The message pasted into an email for the bank is the same one that ends up in
a `Logger.error`, in Sentry and in a ticket. If the field that failed is a RUT
or a name, that is the path by which the data of thousands of beneficiaries
leaves the system without anyone deciding it (Law 19.628 in Chile, GDPR if
there are European customers). The uncomfortable part is that the information
that makes the diagnostic useful is the same that should not travel.

A field is declared sensitive in the layout, and `:rut` is by default:

```elixir
[nombre: :beneficiario, largo: 20, sensible: true]
```

Its diagnostics show the **shape** of the value, not the value, in
`Diagnostico.mensaje/1`, `reporte/1`, `to_string/1` and `inspect/1`:

```
línea 7, campo :rut (posiciones 1-10): se esperaban un RUT con dígito verificador,
llegaron <10 caracteres: 4 dígitos, 1 letra, 3 dígitos, "-", 1 dígito>; ...
```

Ten characters: four digits, one letter, three digits, a dash, one digit. The
shape is the redaction policy, and it is a decision. A partial mask
(`1234****-*`) shows enough to re-identify (four digits of a RUT leave ten
thousand candidates) and hides exactly what is needed to debug. Total
suppression says nothing. The shape says there is a letter where a digit
should be, and at which position, without saying which. The length is not
hidden: it is the field's width, which the layout already declares.

The full value stays in the struct's `:recibido`, and `mensaje(d, revelar: true)`
(reveal) or `reporte(lista, revelar: true)` show it for local, interactive
use. Redaction belongs to the representations, not to the data: whoever needs
it reads it on purpose, and the accidental path, `Logger.error(inspect(diagnostico))`,
does not carry it. It is the same pattern as `redact: true` in Ecto.

What is not redacted, and why: an invalid byte and its position (`el byte 0xC9
en la posición 14`) is not personal data and is the whole diagnostic of an
encoding problem; the measure of a short line is a number; and the
observations of `detectar/2` quote at most one byte and one delimiter, never a
field's content. Inputs that are not binaries are described by type ("a list
of 3 elements") instead of printed. A test walks every field type and every
possible failure and verifies the absence of the value in every
representation.

## Traceability: from the record to the byte, and the batch fingerprint

When the bank rejects a 40,000-line payroll, the conversation is "beneficiary
X's record is wrong", and the first thing asked for is to go back from the
data to the physical place in the file it came from. With `traza: true`
(trace), every record carries the reserved key `:__traza__`:

```elixir
{:ok, registros, []} = AnchoFijo.parsear(layout, "nomina.txt", traza: true)

registro = Enum.at(registros, 6)
registro.__traza__
# %AnchoFijo.Traza{linea: 7, offset: 288, largo: 48}

AnchoFijo.Traza.linea_original(registro.__traza__, File.read!("nomina.txt"))   # original line
# "12345678-5JUAN PEREZ          000012345620240115"
```

The return shape was a decision. A `{registro, traza}` tuple or a
`%Registro{valores: ..., traza: ...}` struct change the shape for all the code
that already reads `registro.monto`. The `:__traza__` key does not: the record
is still the map, the trace is next to it, and the two underscores are the
Elixir convention for metadata that does not collide with data (`__struct__`,
`__meta__` in Ecto). A layout field cannot be called that. Off, the option
costs nothing: the parsing path is the usual one and nothing is computed or
added; measured over 100,000 lines, turning it on costs 45 % of time and 35 %
of memory in `parsear/3`, and nothing measurable in `stream/3`, which carries
the offset in the accumulator without global state.

The batch fingerprint is the other half of traceability: proving *which* file
was processed.

```elixir
AnchoFijo.huella("nomina.txt")        # fingerprint
# {:ok, "sha256:3164aeb0f4d85eabb8bcc255402e83170729ffe8cb076483b98caf2407eca512"}
```

It is a SHA-256, stable between runs and sensitive to any data byte. What does
not change the fingerprint is what does not change what the parser reads: the
line terminator style (CRLF, LF or CR, normalised to LF) and the presence of
the terminator on the last line. A file that went through a Windows editor is
the same batch. What does change the fingerprint, on purpose: one padding space
more or less (it is a byte of the record) and the encoding (the bytes are the
data). With `normalizar: false` it is computed over the exact bytes, which is
what `sha256sum` gives. It is computed in blocks, so a multi-gigabyte file is
not loaded into memory.

## Observability

A library that processes 2 GB files at night and does not emit a single event
is a black box. `ancho_fijo` emits `:telemetry` events with the ecosystem's
`start`/`stop`/`exception` pattern, under the `[:ancho_fijo, ...]` prefix, for
`parsear/3`, `detectar/2` and `stream/3`. Subscribing is three lines:

```elixir
:telemetry.attach("nomina", [:ancho_fijo, :parsear, :stop], fn _evento, medidas, metadata, _ ->
  Logger.info("#{metadata.layout}: #{medidas.registros} registros, #{medidas.errores} errores")
end, nil)
```

The `stop` of `parsear/3` carries `duration`, `lineas`, `registros`, `errores`
and `advertencias` (lines, records, errors, warnings); the one of `stream/3`
the same, counted in the stream's accumulator without accumulating records or
breaking laziness, and it also fires if the enumeration is cut short. There is
no event per failing line: in a file with 10,000 bad rows that would be 10,000
events, each with a diagnostic that may carry personal data. The complete
contract, event by event, is in `AnchoFijo.Telemetria`.

`:telemetry` is an **optional** dependency: you have to add it to your project
to receive the events. See the decision below.

## Idempotency: recognising the file that was already processed

The most expensive operational error of a payroll is not a badly parsed row: it
is the same file processed twice, by a manual retry, a cron that ran twice or
a forwarded email. The library is the natural place to detect it, because it
sees the whole file before a single record exists in the database.

```elixir
layout = AnchoFijo.Layout.nuevo!(identidad: [campos: [:lote, :fecha]], campos: [...])   # identity

{:ok, identidad} = AnchoFijo.identidad(layout, "nomina.txt")
# %AnchoFijo.Identidad{declarada: %{lote: 1, fecha: ~D[2024-01-15]}, huella: "sha256:...", nombre: "nomina.txt"}

case AnchoFijo.Identidad.cotejar(identidad, identidades_ya_procesadas) do    # check against
  :nueva -> procesar(...)                                                     # new
  {:duplicada, vista} -> rechazar("ya se procesó el #{vista.nombre}")        # duplicate
  {:conflicto, diagnostico, _vista} -> escalar(AnchoFijo.Diagnostico.mensaje(diagnostico))   # conflict
end
```

With an `AnchoFijo.Multiregistro` the declared identity comes from the header,
which has its own layout: `AnchoFijo.identidad(AnchoFijo.Formatos.nacha(), ruta)`
brings the *immediate origin*, the date, the time and the *file ID modifier*.

Three sources, in decreasing order of reliability: what the file declares
about itself (the batch number and the date in the header, which the layout
points at with `identidad:`), the content fingerprint, and the file name,
which is informative and nothing more. The fingerprint rules: the same content
is a duplicate even if the name changes. And the same declared identity with
other content **is not a duplicate, it is something worse**: the sender reused
the batch number or someone edited the file, and it has its own diagnostic.

**The boundary.** The library persists nothing and has no state: it receives
the identities the caller has already seen, answers, and that is it. The day a
parser opens a table or an ETS it stops being a parser, and it also decides
for the user how long to remember and what to do with a duplicate. That
belongs to the system that pays: store the fingerprint and the declared
identity of every processed file and consult them before starting.

## Decisions and trade-offs

**Positions are counted in bytes, not characters.** A fixed-width format is
defined over the physical file: when the bank says "120 positions", it counts
bytes. With latin-1 it is the same thing. With UTF-8 it is not, and that is the
trade-off: if the sender counted characters, you have to declare
`unidad: :caracteres` or every line with an "ñ" shifts by a byte. The library
does not guess, but `detectar/2` reports both lengths when they differ, which
is the signal for which one to use.

**Amounts are `{unidades, precision}` and not `Decimal`, by default.** It
honours "no float on the way" without adding a dependency. The cost is
converting at the edge, or declaring `decimales_como: :decimal` if the project
already has `Decimal`: then the fields read and write `%Decimal{}`. For a
package sold as small, the mandatory dependency weighed more than a one-line
declaration.

**Gaps do not block, overlaps do.** Explained above. The consequence is that a
layout with a forgotten field in the middle parses anyway, and only
`layout.advertencias` keeps a record. It was chosen because the alternative,
forcing `:filler` fields to satisfy the validator, makes the definition stop
looking like the annex being transcribed.

**A line of wrong length reports a single diagnostic.** If the line does not
measure what it should, its fields are not read. A missing byte shifts every
field after it, and reporting the twelve derived diagnostics hides the only one
that matters. The cost: in tolerant mode you do not see the field detail of a
row with a bad length.

**Both modes return `{:ok, registros, diagnosticos}`.** Strict mode too, even
though on `:ok` the list can only carry warnings. The alternative, two elements
in strict and three in tolerant, forces the caller to know which mode it
called to know what to destructure, and leaves the warnings with nowhere to go
in the very mode used for files that are contracts. A warning discarded for not
being an error is an assumption nobody reviewed.

**A warning does not replace its record, it accompanies it.** The record is in
`registros` with its value, and the `:advertencia` diagnostic says what was
assumed to get there. An error, instead, leaves no record: there is no value
to deliver.

**Control characters are rejected in both encodings.** The 0x80–0x9F range is
control in latin-1 but carries quotes and dashes in Windows-1252. Finding it
is the most reliable signal that the file is cp1252 and not latin-1, and the
diagnostic says so instead of returning silent garbage. The cost is that a
file with a legitimate control byte, which does not exist in banking fixed
width but could, would need another strategy.

**No cp1252 or other encodings.** Only `:utf8` and `:latin1`. Adding a
transcoding table for every codepage in the world is how a small package stops
being finished. The diagnostic points at the problem and the prior conversion
is one line of `iconv`.

**Two ways to fail, and only two.** A problem with the data is an
`AnchoFijo.Diagnostico`, as a value or inside `AnchoFijo.Error`. A problem with
the call, an option that does not exist, a value of another type, is an
`ArgumentError` naming the function and the option, as in the stdlib: it is
not a diagnostic because there is nothing to send to the bank. An unknown key
in a layout (`enconding:`, `precison:`) is also an error of the definition,
not something ignored: it would leave a layout different from the one written,
without any signal. Support modules (`AnchoFijo.Rut`,
`AnchoFijo.Transcodificacion`, `AnchoFijo.Campo.extraer/3`) use guards and raise
`FunctionClauseError` on wrong types, like `String.upcase(42)`; the two-ways
contract belongs to the entry points. A test feeds garbage to each one to hold
it.

**`:telemetry` is optional, and the package stays free of runtime
dependencies.** The two options were declaring it mandatory (30 KB, no
dependencies, already installed in any Phoenix app) or `optional: true` with a
compile-time decision. The second was chosen because the zero-dependency
promise matters most outside Phoenix: the migration script, the `Mix.Task`,
the `escript` where every dependency is friction and nobody will look at a
dashboard. The cost is an `if Code.ensure_loaded?(:telemetry)` in a module
body: with the dependency present the calls compile, without it not one
exists, and at runtime there is no `if`. The ugly part: if `:telemetry` is
added after `ancho_fijo` was compiled, it has to be recompiled
(`mix deps.compile ancho_fijo --force`). It is in the module's docs.

**`moneda:` returns a struct; without `moneda:` the tuple stays.** The three
options were keeping `{unidades, precision}` and only validating (zero
migration, but adding CLP to USD still does not complain),
`{unidades, precision, moneda}` (breaks all the pattern matching published on
Hex) or a struct. The struct was chosen, but only when the layout declares the
currency: whoever does not declare it changes no line, and whoever declares it
asked on purpose for a value that knows its currency. `%AnchoFijo.Monto{}` has
three fields, five integer operations and an `Inspect`; it is not a money
library in disguise, and `a_decimal/1` hands the amount to whoever has one.
The ISO 4217 table is deliberately small: every currency with a scale other
than two, which are the ones that matter, plus the regional ones and the
reserve ones. A missing currency with explicit `:precision` is accepted with a
layout warning; without `:precision`, it is an error.

### Why the API is in Spanish

**The API, the options and the diagnostic prose are in Spanish, and will stay
that way.** It is an identity decision and the domain (RUT, Previred, Chilean
and Latin American payrolls) is Latin American; the field names in the bank
layouts are already in Spanish. The objection that comes up is not "I do not
understand Spanish" but "I do not want `Layout.nuevo!` mixed with the rest of
my code". Four options were weighed:

1. **Rename everything to English.** Breaks the API, loses the identity and
   leaves the diagnostics half done (the messages are Spanish prose).
   Discarded.
2. **Bilingual documentation.** This guide, the glossary below and the
   `idioma: :en` option of `Diagnostico.mensaje/2` for user-facing messages.
   Low cost, removes the barrier to reading and evaluating the library. Done.
3. **An English facade in the same package.** A `FixedWidth.*` module that
   translates options and delegates. Two names for everything in one package
   confuses the documentation and doubles the surface to maintain. Discarded.
4. **A sibling package `fixed_width`** that depends on `ancho_fijo` and
   exposes `FixedWidth.Layout.new!/1`, `FixedWidth.parse/3`,
   `FixedWidth.write/3` with English options translated at the boundary and
   diagnostics with `:language`. The core stays in Spanish; whoever wants
   English installs the sibling.

The written criterion for option 4: **the facade exists when there is a
project that needs it, not before.** If you are that project, open an issue.

## Maintenance, compatibility and support

Who maintains it, how to report a security problem, which Elixir and OTP
versions are supported, what counts as a breaking change, how long a series is
maintained and how the package is published: all of it is in the Spanish
README under "Mantenimiento, compatibilidad y soporte" and in
[SECURITY.md](SECURITY.md). In short: `elixir: "~> 1.14"`, CI runs the full
suite on Elixir 1.14 / OTP 25 through 1.20 / OTP 28, semantic versioning with
breaking changes under `### Cambiado — rompe compatibilidad` in the CHANGELOG
while the version is `0.x`, the latest series is maintained plus six months of
security fixes for the previous one, and releases are published only from CI
by tag.

## Glossary

The names of the library, Spanish to English. Function and option names are
exactly as you type them; the English column is what they mean.

| Español | English |
| --- | --- |
| `detectar/2`, `detectar!/2` | detect: inspect a file before parsing |
| `parsear/3`, `parsear!/3` | parse |
| `stream/3` | stream, lazy parse |
| `escribir/3` | write |
| `huella/2` | fingerprint (SHA-256 of the content) |
| `identidad/3` | identity of a batch (declared fields + fingerprint + name) |
| `resumen/2` | summary of a list of diagnostics |
| `Layout.nuevo/1`, `nuevo!/1` | new: build and validate a layout |
| `Layout.documentar/2` | document: the specification table (Markdown, CSV, JSON) |
| `a_mapa/1`, `desde_mapa/1`, `a_json/1`, `desde_json/1` | to map, from map, to JSON, from JSON |
| `Multiregistro` | multi-record: header, detail and trailer |
| `agrupar/2` | group records by type |
| `Diagnostico.mensaje/2`, `reporte/2`, `separar/1` | message, report, split errors from warnings |
| `Diagnostico.marcar_sensible/2` | mark as sensitive (redact) |
| `Detector.contrastar/2` | contrast a report against a layout |
| `Traza.linea_original/2` | original line of a traced record |
| `Identidad.cotejar/2` | check an identity against the ones already seen |
| `Monto.sumar/2`, `total/1`, `formatear/2`, `a_decimal/1` | add, total, format, to Decimal |
| `Test.assert_parsea/4`, `assert_escribe/4`, `assert_round_trip/3`, `assert_diagnostico/2` | asserts it parses, asserts it writes, round trip, diagnostic |
| `Test.Generadores.registro/1`, `linea/1`, `linea_invalida/1` | generators: record, line, invalid line |
| `Tipo` | type behaviour: `opciones/0`, `validar/1`, `leer/3`, `escribir/2`, `generador/1` are options, validate, read, write, generator |
| `campos:` | fields |
| `nombre:` | name |
| `largo:` | length |
| `posicion:` | position (1-based) |
| `tipo:` | type |
| `opcional:` | optional |
| `trim:` | trim side: `:ambos` both, `:izquierda` left, `:derecha` right, `false` |
| `relleno:` | padding character |
| `relleno_final:` | trailing padding: `:estricto` strict, `:tolerar` tolerate |
| `sensible:` | sensitive (redacted in diagnostics) |
| `encoding:`, `unidad:` | encoding; unit: `:bytes` or `:caracteres` (characters) |
| `precision:`, `moneda:`, `separador:`, `signo:` | precision, currency, decimal separator (`:implicito`, `:punto`, `:coma`), sign (`:inicial` leading, `:final` trailing) |
| `como: :decimal`, `decimales_como: :decimal` | read and write `%Decimal{}` |
| `formato:`, `pivote:` | date/time format, pivot year for two-digit years |
| `dv:` | check digit of a RUT: `:validar`, `:no_validar`, `:ausente` (absent) |
| `valor:` | value: the literal of a constant field |
| `descripcion:`, `ejemplo:` | description, example (for `documentar`) |
| `en:`, `rango:`, `patron:` | in (catalogue), range, pattern |
| `requerido_si:`, `prohibido_si:` | required if, forbidden if |
| `generador:` | generator (a `StreamData`) for the test generators |
| `campos:` + `repetir:` in a `:grupo` | repeated group (OCCURS) |
| `segun:` + `variantes:` in a `:variante` | variant chosen by another field (REDEFINES) |
| `identidad: [campos: ...]` | identity fields of the batch |
| `discriminador:`, `registros:`, `controles:` | discriminator, record types, controls |
| `cantidad:` | count: `:uno` exactly one, `:opcional` zero or one, `:varios` any number, `:al_menos_uno` at least one |
| `cuenta:`, `suma:`, `agrupar_por:` | count of, sum of, group by |
| `modo:` | mode: `:estricto` strict, `:tolerante` tolerant |
| `truncar:` | truncate text that does not fit |
| `traza:` | trace: attach `:__traza__` to each record |
| `revelar:` | reveal redacted values |
| `audiencia:`, `idioma:` | audience (`:desarrollador` developer, `:usuario` user), language (`:es`, `:en`) |
| `:texto`, `:entero`, `:decimal`, `:fecha`, `:hora`, `:fecha_hora`, `:rut`, `:constante`, `:relleno`, `:grupo`, `:variante` | text, integer, decimal, date, time, datetime, RUT, constant, filler, group, variant |
| `esperado`, `recibido`, `causa_probable` | expected, received, probable cause |
| `gravedad`: `:error`, `:advertencia` | severity: error, warning |
| `linea`, `campo`, `posicion`, `contenido` | line, field, position, content |
| Diagnostic types `:largo`, `:campo_invalido`, `:campo_truncado`, `:encoding`, `:doble_codificacion`, `:layout`, `:estructura`, `:control`, `:regla`, `:entrada` | length, invalid field, truncated field, encoding, double encoding, layout, structure, control, rule, input |
| `advertencias` | warnings |
| `registros` | records |

## Documentation

[hexdocs.pm/ancho_fijo](https://hexdocs.pm/ancho_fijo)

## License

MIT. See [LICENSE](LICENSE).
