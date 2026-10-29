# ancho_fijo

[![Hex.pm](https://img.shields.io/hexpm/v/ancho_fijo.svg)](https://hex.pm/packages/ancho_fijo)
[![Docs](https://img.shields.io/badge/hexdocs-ancho__fijo-blue.svg)](https://hexdocs.pm/ancho_fijo)
[![CI](https://github.com/galenzo17/ancho_fijo/actions/workflows/ci.yml/badge.svg)](https://github.com/galenzo17/ancho_fijo/actions/workflows/ci.yml)

Lectura de archivos de ancho fijo que empieza por desconfiar del archivo.

## El problema

El cliente manda el anexo técnico. Dice: 120 posiciones por línea, UTF-8, monto
en las posiciones 61 a 72 con dos decimales implícitos. Uno escribe el parser,
lo prueba con el archivo de ejemplo que venía en el correo, funciona, se sube a
producción.

Y ahí llega el archivo de verdad. Tiene 118 posiciones. Los nombres vienen en
latin-1 y las tildes se convirtieron en signos de pregunta. Tres filas de las
diez mil traen la fecha en blanco. Y en la segunda semana, un operador exportó
la nómina desde Excel y el archivo pasó a ser un CSV con punto y coma, aunque
siga llamándose `nomina.txt`.

Nada de eso es difícil de manejar. El problema es *cuándo* se descubre: después
de escribir el parser, con el proyecto entregado, un viernes. Esta librería
existe para mover ese descubrimiento al día uno, y para que cuando algo falle el
error diga qué pasó en vez de `{:error, :invalid}`.

## Instalación

```elixir
def deps do
  [{:ancho_fijo, "~> 0.4.0"}]
end
```

Sin dependencias de runtime.

## Primero se interroga el archivo

Antes de escribir una línea de layout: `detectar/2`. Recibe el contenido o una
ruta y responde "¿esto es realmente lo que me dijeron que es?".

```elixir
{:ok, reporte} = AnchoFijo.detectar("nomina.txt")

reporte.probablemente_ancho_fijo?
# => false

reporte.observaciones
# [
#   "hay 4 largos de línea distintos: 28 (1 línea), 41 (1 línea), 45 (1 línea), 46 (1 línea);
#    el predominante es 28, así que el resto son las filas sospechosas",
#   "todos los bytes son ASCII: latin-1 y UTF-8 dan el mismo resultado en este archivo",
#   "las líneas terminan en LF (\\n), estilo Unix",
#   "el carácter \";\" aparece 3 veces en todas las líneas y en posiciones variables:
#    esto parece un archivo delimitado, no de ancho fijo"
# ]
```

Ese archivo se llamaba `.txt` y era un CSV. La detección no es "tiene punto y
coma": es que la cantidad de punto y coma por línea es idéntica y sus posiciones
no lo son. Un formato de ancho fijo que usa `|` como separador decorativo tiene
el delimitador siempre en la misma columna, y `detectar/2` no da ese falso
positivo.

El otro caso de todos los días, el encoding:

```elixir
{:ok, reporte} = AnchoFijo.detectar("nomina.txt")

reporte.encoding_probable
# => :latin1

reporte.observaciones
# [
#   "todas las 2 líneas miden 48 bytes",
#   "hay bytes que no son UTF-8 válido pero sí caracteres latin-1
#    (el byte 0xC9 en la posición 14 de la línea 1); declare encoding: :latin1 en el layout",
#   "las líneas terminan en LF (\\n), estilo Unix"
# ]
```

Y las marcas que Windows y los mainframes dejan en el archivo, que no son datos
y que un diagnóstico de largo culparía de otra cosa: el BOM UTF-8 que dejan
Notepad y Excel (`reporte.bom == :utf8`; `bom: :ignorar` en `parsear/3` lo
salta con una advertencia), un archivo UTF-16 o EBCDIC
(`encoding_probable: :utf16 | :ebcdic`, con el `iconv` que lo convierte en la
observación), y el `0x1A` final de DOS (`marca_final_dos?`; `parsear/3` lo
omite con una advertencia). Los largos se cuentan sin ellas.

Y si ya se tiene el layout que el anexo declara, se puede contrastar directo:

```elixir
{:ok, reporte} = AnchoFijo.detectar("nomina.txt", layout: layout)

AnchoFijo.Detector.contrastar(reporte, layout)
# [
#   %AnchoFijo.Diagnostico{
#     esperado: "un largo de línea de 50 bytes según el layout",
#     recibido: "48",
#     causa_probable: "el archivo tiene 2 bytes menos por línea: falta un campo,
#                      o el layout es de otra versión del formato"
#   }
# ]
```

Una lista vacía significa que el archivo y la especificación concuerdan en todo
lo que se puede verificar sin parsear. Eso es lo que uno quiere ver el día uno.

El reporte completo trae `:largos`, `:largo_consistente?`, `:largo_predominante`,
`:encoding_probable`, `:bytes_no_utf8`, `:terminador`,
`:termina_con_terminador?`, `:delimitadores`, `:delimitador_sugerido` y
`:probablemente_ancho_fijo?`. Ver `AnchoFijo.Detector`.

### Desde la terminal

El día uno no hay proyecto ni `iex`: hay un archivo que llegó por correo. La
misma pregunta, como comando:

```
$ mix ancho_fijo.detectar nomina.txt
nomina.txt: probablemente de ancho fijo
  3 líneas · largo 48 bytes, consistente · ascii · LF
  - todas las 3 líneas miden 48 bytes
  - todos los bytes son ASCII: latin-1 y UTF-8 dan el mismo resultado en este archivo
  - las líneas terminan en LF (\n), estilo Unix
```

`--layout nomina.exs` contrasta con un layout, `--json` imprime el reporte
para `jq`, y el código de salida sirve para un script de validación previa:
`0` si parece ancho fijo y concuerda, `1` si no, `2` si no se pudo leer.
Ver `mix help ancho_fijo.detectar`.

## Después se parsea

El layout es data: una lista de campos con nombre, largo, tipo y opciones de
limpieza. Cambiar de formato es cambiar el mapa.

```elixir
layout =
  AnchoFijo.Layout.nuevo!(
    nombre: "nómina banco X",
    encoding: :latin1,
    campos: [
      [nombre: :rut, largo: 10],
      [nombre: :beneficiario, largo: 20],
      [nombre: :monto, largo: 10, tipo: :decimal, precision: 2],
      [nombre: :fecha, largo: 8, tipo: :fecha, formato: :aaaammdd]
    ]
  )

AnchoFijo.parsear(layout, "nomina.txt")
# {:ok,
#  [
#    %{rut: "12345678-9", beneficiario: "JOSÉ MUÑOZ PEÑA", monto: {125000, 2}, fecha: ~D[2024-01-15]},
#    %{rut: "98765432-1", beneficiario: "MARÍA ROJAS ÑAÑEZ", monto: {9990050, 2}, fecha: ~D[2024-01-15]}
#  ],
#  []}
```

Las posiciones se omitieron: cada campo se encadena al anterior. Cuando el anexo
las declara ("posiciones 61 a 72"), se ponen explícitas y son 1-based, igual que
en el anexo.

### Los dos modos

Los dos devuelven `{:ok, registros, diagnosticos}`. La tercera posición trae los
errores de las filas que no se pudieron leer y las advertencias de las que sí,
pero asumiendo algo; `AnchoFijo.Diagnostico.separar/1` las parte en dos.

Estricto (el default) corta en la primera línea con problemas:

```elixir
AnchoFijo.parsear(layout, "nomina.txt")
# {:error, [%AnchoFijo.Diagnostico{...}]}

# línea 2: se esperaban 48 bytes, llegaron 46; posible campo faltante o archivo delimitado
```

Tolerante devuelve las filas buenas y los diagnósticos de las malas, porque una
nómina de 10.000 filas con 3 malas debe reportar las 3, no botar el lote:

```elixir
{:ok, buenas, malas} = AnchoFijo.parsear(layout, "nomina.txt", modo: :tolerante)

length(buenas)
# => 2

Enum.map(malas, &AnchoFijo.Diagnostico.mensaje/1)
# ["línea 2: se esperaban 48 bytes, llegaron 46; posible campo faltante o archivo delimitado"]
```

Nótese que el modo tolerante devuelve `:ok`: un lote con filas malas separadas de
las buenas es un resultado, no una falla. `{:error, _}` queda para lo que impide
procesar cualquier cosa —layout inválido, archivo ilegible— donde no hay nada que
rescatar.

En estricto la lista solo puede traer advertencias: un error habría cortado. Y
un error corta también con las advertencias de las líneas ya leídas, que se van
con él: no hay resultado parcial que anotar.

### Cuando no hay nada que hacer salvo fallar

Un script de migración, un `Mix.Task`, un pipeline donde un archivo malo no
deja nada que rescatar: ahí la tupla estorba. `parsear!/3` y `detectar!/2`
siguen la convención de la stdlib, devuelven el valor o levantan
`AnchoFijo.Error`, cuyo mensaje es el reporte de los diagnósticos:

```elixir
registros = AnchoFijo.parsear!(layout, "nomina.txt")
# ** (AnchoFijo.Error) línea 2: se esperaban 48 bytes, llegaron 46; posible campo faltante o archivo delimitado
```

Con `modo: :tolerante` el `!` levanta igual si hay filas malas, pero la
excepción trae **todos** los errores del archivo, no el primero: es la
combinación para el script que tiene que morir, pero cuyo operador necesita la
lista completa para corregir el archivo de una vez. La alternativa, devolver las
filas buenas y descartar los diagnósticos, habría hecho del `!` un atajo que
pierde información en silencio, y un `!` no es un atajo: es otro contrato.

Lo que el `!` no devuelve son las advertencias. Son filas que se leyeron bien
bajo un supuesto que el layout declaró, y la función devuelve un solo valor. Si
importan, `parsear/3` las trae en la tercera posición.

### Archivos grandes

```elixir
"cartola.txt"
|> File.stream!()
|> then(&AnchoFijo.stream(layout, &1))
|> Stream.filter(&match?({:ok, _, _}, &1))
|> Stream.map(fn {:ok, registro, _advertencias} -> registro.monto end)
|> Enum.reduce(0, fn {unidades, _precision}, total -> total + unidades end)
```

Medido sobre un archivo de 100 MB (dos millones de líneas): `stream/3` lo
recorre en 5 segundos con un pico de heap de 34 KB, que no depende del
tamaño del archivo; `parsear/3` en modo tolerante tarda el doble y retiene
1,2 GB, porque devuelve los dos millones de registros. Los números, la
máquina y el script están en `bench/README.md`.

`stream/3` emite `{:ok, registro, advertencias}` o `{:error, diagnosticos}` por
línea. Qué hacer con los errores es decisión del consumidor: acumular todos los
diagnósticos de un archivo de 2 GB para devolverlos al final anularía el punto de
ser lazy. Las advertencias viajan pegadas a su registro por la misma razón: no
hay dónde juntarlas.

### Escribir con el mismo layout

Para mandarle la nómina al banco hay que generarla con el formato del anexo,
y el formato ya está escrito una vez. `escribir/3` es el inverso de
`parsear/3`, y la propiedad que lo define es el round-trip: lo que se escribe
se vuelve a leer igual.

```elixir
{:ok, contenido, []} = AnchoFijo.escribir(layout, registros)
File.write!("nomina.txt", contenido)

# o línea por línea, sin armar el archivo en memoria:
layout
|> AnchoFijo.Escritor.stream(registros)
|> Stream.map(fn {:ok, linea, _advertencias} -> linea end)
|> Stream.into(File.stream!("nomina.txt"))
|> Stream.run()
```

No hay modo tolerante para escribir: una nómina con una fila menos es otro
archivo, y mandarlo es peor que no mandarlo. Si algún valor no se puede
escribir, `escribir/3` devuelve todos los diagnósticos de todos los
registros, con el número de registro, el campo, las posiciones y la causa.

**Lo que no cabe no se trunca.** Un monto truncado es otro monto, un RUT
truncado es otra persona, una glosa truncada es la única de las tres que a
veces se acepta. Por eso un valor más ancho que su campo es un error, y
`truncar: true` existe solo para `:texto`, con una advertencia por cada
campo recortado. El texto se rellena del lado que `:trim` recorta al leer,
los números con ceros a la izquierda y el signo solo en los negativos, un
`{unidades, precision}` tiene que traer la precisión del campo (escalar es
donde se pierde el peso), y el encoding del layout se respeta: con
`encoding: :latin1` el archivo sale en latin-1, y un carácter que latin-1 no
tiene es un diagnóstico con el carácter y su posición.

### Bytes o caracteres, también al escribir

El error clásico de un escritor de ancho fijo hecho con `String.pad_trailing`
es medir caracteres: "José" mide cuatro, pero en UTF-8 ocupa cinco bytes, y
un campo de cuatro bytes que recibe cinco corre todas las columnas que
siguen. Esta librería mide al escribir en la misma unidad en que lee:
`:bytes` por default, en el encoding del layout (o del campo, si lo
declara), o `:caracteres` si el layout lo dice.

```elixir
layout = AnchoFijo.Layout.nuevo!(campos: [[nombre: :nombre, largo: 4]])

AnchoFijo.escribir(layout, [%{nombre: "añ"}])
# => {:ok, "añ \n", []}            # 2 caracteres, 3 bytes: sobra un byte, va un espacio

{:error, [d]} = AnchoFijo.escribir(layout, [%{nombre: "José"}])
d.causa_probable
# => "el valor no cabe en el campo: 5 posiciones en 4 (5 bytes, 4 caracteres)"

AnchoFijo.escribir(layout, [%{nombre: "a€bc"}], truncar: true)
# => {:ok, "a€\n", [advertencia]}  # el corte cae en una frontera de carácter: 1 + 3 bytes
```

Con `truncar: true` el corte nunca parte un carácter: se recorta por grafemas
hasta que quepa y el byte que sobra se completa con espacio. Sin `truncar:`,
el diagnóstico dice el largo en las dos unidades cuando difieren, que es lo
que explica por qué "cuatro letras" no caben en cuatro posiciones. Con
`encoding: :latin1` el valor se transcodifica antes de medir, así que "añoo"
ocupa cuatro bytes, y un carácter que latin-1 no tiene (`"€"`) es un
diagnóstico `:encoding` con la posición del carácter, nunca un `?` silencioso.
Con `unidad: :caracteres` se cuentan grafemas, igual que al leer.

Hay un caso que ninguna medición arregla: un `:relleno` que ocupa más de un
byte (`"·"`) en un layout que mide en bytes en UTF-8. Repetirlo tantas veces
como bytes faltan no puede dar el largo exacto. `Layout.nuevo!/1` lo deja en
`layout.advertencias` y, si se intenta escribir ese campo, es un error. Los
tests de regresión de todo esto están en `test/ancho_fijo/escritura_en_bytes_test.exs`,
con una propiedad que escribe textos con tildes, ñ, `€` y emojis en las tres
configuraciones y mide cada línea en la unidad del layout.

### Líneas cortas por relleno recortado

Hay emisores que recortan los espacios finales de cada línea, o solo de la
última. Con el layout tal cual, esa línea es un diagnóstico de largo y la fila se
bota. Si el formato termina en un campo de texto —una glosa, una referencia—,
lo que falta es relleno, no dato, y se puede declarar:

```elixir
layout = AnchoFijo.Layout.nuevo!(
  relleno_final: :tolerar,
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

La línea se completa con el carácter de relleno del campo y queda una
advertencia por cada línea completada, con cuántas unidades faltaban. La regla
es estrecha a propósito: se tolera **relleno** faltante, no bytes faltantes. La
zona reponible empieza al final de la línea y crece hacia atrás mientras
encuentre relleno no declarado o campos `:texto` con el mismo carácter de
relleno. Un `:entero`, un `:decimal` o una `:fecha` la cortan: ahí el ancho es
el dato, y una línea corta que los alcanza sigue siendo un error de largo,
aunque falte un solo byte. El diagnóstico dice cuántas unidades faltaban y
cuántas eran reponibles.

Sin la opción, nada cambia: el default es `:estricto`.

Con `unidad: :caracteres` la cuenta es en caracteres y la línea se completa
después de transcodificar, así que `"JOSÉ MUÑOZ"` en una glosa de 12 se
completa con 2 caracteres, no con los 0 que sugeriría contar bytes. Con
`unidad: :bytes` solo se repone un relleno ASCII: un carácter de más de un byte
repetido tantas veces como bytes faltan no reconstruye la línea, y ese campo no
entra en la zona reponible.

## Header, detalle y trailer

Las nóminas y cartolas reales traen varios tipos de registro, cada línea dice
cuál es en sus primeras posiciones, el orden importa y el trailer trae
totales que tienen que cuadrar. `AnchoFijo.Multiregistro` es un layout de
layouts más esas reglas, y `parsear/3` y `stream/3` lo aceptan en lugar del
layout:

```elixir
nomina = AnchoFijo.Multiregistro.nuevo!(
  discriminador: [posicion: 1, largo: 2],
  registros: [
    header:  [valor: "01", cantidad: :uno,          layout: layout_header],
    detalle: [valor: "02", cantidad: :al_menos_uno, layout: layout_detalle],
    trailer: [valor: "09", cantidad: :uno,          layout: layout_trailer]
  ],
  controles: [
    [en: :trailer, campo: :cantidad, cuenta: :detalle],
    [en: :trailer, campo: :total, suma: {:detalle, :monto}]
  ]
)
```

Hay formatos sin código de tipo: el header y el trailer se reconocen porque
miden distinto que el detalle, o porque son la primera y la última línea. El
discriminador también sabe de eso:

```elixir
discriminador: [por: :largo]                 # cada tipo mide lo que su layout
discriminador: [por: :posicion_en_archivo]   # header: [ubicacion: :primera, ...], trailer: [ubicacion: :ultima, ...]
discriminador: [por: fn linea, numero -> ... end]   # para lo que no cabe arriba
```

Dos tipos que miden lo mismo son una definición inválida. Con
`:posicion_en_archivo` la última línea se reconoce con una línea de
anticipación, así que `stream/3` sigue en memoria constante. Y una función es
el último recurso: no se serializa ni se contrasta, `detectar/2` solo cuenta
lo que devuelve. `AnchoFijo.detectar(ruta, layout: multi)` dice qué criterio
discrimina, cuántas líneas son de cada tipo y cuántas no son de ninguno, y
con un multiregistro un archivo con tres largos de línea sí es de ancho fijo.

Cuando cada layout declara su código de tipo como un campo `:constante`, el
discriminador apunta al campo y los valores salen de los literales:

```elixir
layout_header = [campos: [[nombre: :tipo, largo: 2, tipo: :constante, valor: "01"], ...]]

nomina = AnchoFijo.Multiregistro.nuevo!(
  discriminador: [campo: :tipo],
  registros: [header: [cantidad: :uno, layout: layout_header], ...]
)

{:ok, registros, []} = AnchoFijo.parsear(nomina, "nomina.txt")
# [header: %{...}, detalle: %{...}, detalle: %{...}, trailer: %{...}]

AnchoFijo.Multiregistro.agrupar(nomina, registros)
# %{header: %{...}, detalle: [%{...}, %{...}], trailer: %{...}}
```

Y el camino inverso, con los controles calculados en vez de pedidos:

```elixir
registros = [
  header:  %{empresa: "76543210-3", fecha: ~D[2024-01-15], glosa: "SUELDOS ENERO"},
  detalle: %{rut: "12345678-5", nombre: "JUAN PEREZ SOTO", monto: {125_000, 2}, cuenta: 11_223_344},
  detalle: %{rut: "98765432-5", nombre: "ANA MARIA ROJAS", monto: {9_990_050, 2}, cuenta: 55_667_788},
  trailer: %{}                      # :cantidad y :total salen de los detalles
]

{:ok, contenido, []} = AnchoFijo.escribir(nomina, registros)
{:ok, ^registros_con_totales, []} = AnchoFijo.parsear(nomina, contenido)
```

Si el trailer trae `:cantidad` o `:total` con otro valor, es un diagnóstico
`:control`: no se sobreescribe en silencio. Un trailer por moneda se declara
con `agrupar_por: :moneda` en el control, y se compara (al leer) o se calcula
(al escribir) contra los detalles de esa moneda. No hay versión lazy de la
escritura: el trailer necesita los totales, y los totales necesitan todos los
detalles.

Las decisiones, y por qué:

- **Los registros vuelven como `{tipo, mapa}` en el orden del archivo**, no
  como un mapa por tipo. El orden es parte del dato (hay formatos que
  intercalan tipos) y es lo único que `stream/3` puede emitir de a uno.
  `agrupar/2` arma el mapa por tipo para el caso común.
- **La estructura se valida al pasar; los controles, al final.** Un
  discriminador desconocido, un `:detalle` después del `:trailer`, un
  segundo `:header` o un `:trailer` que falta son diagnósticos
  `:estructura`, con la causa probable de siempre ("suele ser un archivo
  pegado a otro"). Los totales necesitan todos los detalles, así que se
  comparan al llegar al fin del archivo: diagnósticos `:control` que dicen
  el valor calculado, el declarado y de qué se calculó.
- **En `stream/3` los controles salen como último elemento.** Un
  `{:error, diagnosticos}` después del último registro si algo no cuadra o
  falta un registro obligatorio, y nada si todo cuadra. El acumulador lleva
  cuentas y sumas, no registros: la memoria sigue siendo constante.
- **En modo tolerante los controles se calculan sobre lo que se pudo leer.**
  Un detalle ilegible produce su diagnóstico y además el del total que ya no
  cuadra. Los dos son ciertos y el segundo es el que el banco va a reportar.
- **Las sumas son sobre enteros o `{unidades, precision}`**, nunca floats;
  con precisiones distintas se comparan a la mayor.

## El layout como datos

Un layout es una definición en Elixir, y hay tres situaciones donde eso no
alcanza: compartirlo con un servicio en otro lenguaje, guardarlo en una base
de datos junto a los archivos de muestra del banco, o dejar que lo edite
alguien que no programa. `Layout.a_mapa/1` lo convierte en un mapa de claves
string sin átomos ni funciones, con la `"version"` del esquema, y
`desde_mapa/1` lo construye y valida con los mismos diagnósticos que
`nuevo/1` (una clave desconocida se reclama). `a_json/1` y `desde_json/1`
hacen lo mismo con JSON, sin dependencias, y `Multiregistro` tiene las cuatro.

```elixir
AnchoFijo.Layout.a_mapa(layout)
# %{"version" => 1, "nombre" => "nómina", "encoding" => "utf8", "unidad" => "bytes", "largo" => 48,
#   "campos" => [%{"nombre" => "rut", "posicion" => 1, "largo" => 10, "tipo" => "rut"}, ...]}

File.write!("nomina.json", AnchoFijo.Layout.a_json(layout))
{:ok, ^layout} = AnchoFijo.Layout.desde_json(File.read!("nomina.json"))
```

`mix ancho_fijo.detectar --layout nomina.json` y `mix ancho_fijo.documentar
nomina.json` aceptan el `.json` además del `.exs`. El JSON Schema para
validar un layout fuera de Elixir está en `priv/layout.schema.json`. YAML
queda fuera del núcleo a propósito, sin dependencia: un `yaml_elixir` en el
proyecto y `YamlElixir.read_from_file!/1 |> AnchoFijo.Layout.desde_mapa()`
alcanzan, porque el mapa es el mismo. Un tipo propio viaja por el nombre de
su módulo y vuelve con `AnchoFijo.Tipo.resolver/1`; un discriminador por
función no se puede serializar y lo dice.

## La especificación sale del layout

La especificación de un formato vive dos veces: en el documento que se manda
al banco y en el layout del código, y divergen sin que nadie se entere. Si el
layout es la fuente de verdad, la tabla tiene que salir de él. Cada campo
acepta `descripcion:` y `ejemplo:`, que el parser ignora, y
`mix ancho_fijo.documentar RUTA.exs [--formato markdown|csv|json] [--idioma es|en]`
(o `AnchoFijo.Layout.documentar/2` desde el código) imprime la tabla. Esta es
la de `test/fixtures/multiregistro_sin_codigo.exs`, tal como sale, y un test
verifica que el README la tenga sin edición manual:

## nómina sin código de tipo

Tipo de registro por el largo de la línea

### header (exactamente uno)

| Campo | Posiciones | Largo | Tipo | Formato | Opcional | Reglas | Descripción | Ejemplo |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `empresa` | 1-10 | 10 | RUT | dígito verificador validado | no |  | RUT de la empresa pagadora | `76543210-3` |
| `fecha` | 11-18 | 8 | fecha | AAAAMMDD | no |  | Fecha de pago |  |
| `glosa` | 19-32 | 14 | texto |  | no |  | Glosa libre del lote |  |

### detalle (al menos uno)

| Campo | Posiciones | Largo | Tipo | Formato | Opcional | Reglas | Descripción | Ejemplo |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `rut` | 1-10 | 10 | RUT | dígito verificador validado | no |  | RUT del beneficiario |  |
| `nombre` | 11-26 | 16 | texto |  | no |  | Nombre del beneficiario |  |
| `monto` | 27-36 | 10 | decimal | 2 decimales implícitos | no |  | Monto a pagar | `0000125000` |
| `cuenta` | 37-40 | 4 | entero |  | no |  | Cuenta de destino |  |

### trailer (exactamente uno)

| Campo | Posiciones | Largo | Tipo | Formato | Opcional | Reglas | Descripción | Ejemplo |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `cantidad` | 1-6 | 6 | entero |  | no |  | Cantidad de detalles |  |
| `total` | 7-20 | 14 | decimal | 2 decimales implícitos | no |  | Suma de los montos |  |

### Controles

- `trailer.cantidad` = cantidad de `detalle`
- `trailer.total` = suma de `detalle.monto`

Con `--idioma en` se traducen los encabezados y los nombres de tipo, no los
nombres de los campos, que son del formato.

## Formatos incluidos

Los formatos de verdad son públicos y estables, y transcribirlos desde cero
es el trabajo central de cada integración. Vienen incluidos, con su fuente
citada y su vigencia, empezando por NACHA/ACH (Estados Unidos):

```elixir
{:ok, registros, []} = AnchoFijo.parsear(AnchoFijo.Formatos.nacha(), "ach.txt")
[] = AnchoFijo.Formatos.Nacha.validar(registros)   # hash, totales y cuentas de cada lote y del archivo
lotes = AnchoFijo.Formatos.Nacha.lotes(registros)  # cada lote con sus entradas y addendas
```

Los formatos cambian por resolución del regulador, y un layout
desactualizado en silencio es peor que no tenerlo. Por eso cada uno se pide
con su **vigencia** (`nacha(vigencia: "2021")`), que no cambia cuando el
catálogo se actualiza; pedir la más nueva es para empezar, fijarla es para
producción. `AnchoFijo.Formatos.catalogo/0` lista las vigencias con su fuente
y la fecha en que se consultó. Se agregan de a uno y completos: Previred
(Chile) es el siguiente.

## Tipos de campo

| tipo | valor devuelto | opciones |
| --- | --- | --- |
| `:texto` | `String.t()` en UTF-8 | `:trim`, `:relleno`, `:opcional` |
| `:entero` | `integer()` | `:opcional`, `:signo` |
| `:decimal` | `{unidades, precision}`; con `:moneda`, un `AnchoFijo.Monto` | `:precision` (obligatoria sin `:moneda`), `:moneda`, `:separador`, `:signo` |
| `:fecha` | `Date.t()` | `:formato` (obligatorio), `:pivote`, `:opcional` |
| `:hora` | `Time.t()` | `:formato` (obligatorio), `:opcional` |
| `:fecha_hora` | `NaiveDateTime.t()` | `:formato` (obligatorio), `:pivote`, `:opcional` |
| `:rut` | `String.t()` canónico, `"12345678-5"`; solo el cuerpo con `dv: :ausente` | `:dv`, `:opcional` |
| `:constante` | el literal declarado en `:valor`, verificado contra la línea | `:valor` (obligatorio), `:relleno` |
| `:relleno` | nada: el campo no aparece en el registro | `:relleno` |

Un monto de `0000125000` con `precision: 2` se lee como `{125000, 2}`: 125.000
unidades mínimas con escala 2, es decir 1.250,00. Nunca hay un float en el
camino. Un monto que pasó por punto flotante deja de cuadrar con la contabilidad
del banco y nadie sabe dónde se perdió el peso.

`:moneda` convierte el `:decimal` en un `AnchoFijo.Monto` con su código ISO
4217, y la precisión deja de declararse: es la escala de la moneda. CLP no
tiene decimales, USD tiene dos, KWD tres, CLF (la UF) cuatro; `moneda: :clp`
con `precision: 2`
es un layout inválido, porque leer pesos chilenos divididos por cien es el
error que nadie nota hasta la conciliación. `Monto.sumar/2` exige la misma
moneda y devuelve un diagnóstico si no; `total/1`, `formatear/2` y
`a_decimal/1` para quien tenga `Decimal`. Nunca hay un float en el camino.

`:signo` es `:inicial` por default: `-0125000`. Los formatos heredados de
mainframe escriben el signo después de los dígitos, `0125000-`, y para leerlos
se declara `signo: :final`. Un signo donde el layout no lo espera no es un
"carácter no numérico": el diagnóstico dice que el signo está en el otro
extremo y qué declarar. El *overpunch* EBCDIC (`12K` por -123) queda fuera.

`:rut` normaliza lo que llegue —`12.345.678-5`, `123456785`, `0000123456785`,
con `k` o `K`— a `"12345678-5"` y valida el dígito verificador por módulo 11.
Un RUT con el DV malo parsea perfecto y el banco lo rechaza días después: por
eso la validación es parte del tipo y no una opción que hay que acordarse de
activar. Las dos salidas son explícitas: `dv: :no_validar` para recibir el dato
y decidir después, y `dv: :ausente` para los formatos que traen el cuerpo sin
DV.

`:formato` no tiene default a propósito. Adivinar si `01022024` es el 1 de
febrero o el 2 de enero es exactamente el error silencioso que esta librería
existe para impedir: un campo `:fecha` sin `:formato` es un layout inválido.
Los formatos con nombre cubren lo que traen los archivos bancarios
(`:aaaammdd`, `:ddmmaaaa`, `:mmddaaaa`, `:aammdd`, `:ddmmaa`, `:mmddaa`,
`:aaaaddd` y `:aaddd` julianos; `:hhmmss` y `:hhmm`; `:aaaammddhhmmss` y
compañía), y cuando ninguno calza, `:formato` acepta un patrón de tokens con
separadores: `"DD/MM/AAAA"`, `"AAAA-MM-DD HH:MM:SS"`. Un año de dos dígitos
se expande con `:pivote`, el primer año de la ventana de cien (default
`2000`): es una decisión del formato, y por eso se declara. La tabla completa
está en `AnchoFijo.Tipo.Fecha`.

`:constante` y `:relleno` son las posiciones cuyo valor lo pone el formato y
no el dato: el código de tipo de registro, un literal como `"HEADER H2H"`,
los *fillers*. Al leer, un literal distinto al declarado es un diagnóstico
con `esperado` y `recibido`, y un relleno no se lee ni va al registro. Al
escribir, los dos se emiten sin que estén en el mapa; un literal distinto en
el mapa es un diagnóstico, porque no es un dato distinto, es otro formato.

```elixir
[nombre: :tipo_registro, largo: 2, tipo: :constante, valor: "01"]
[nombre: :filler, largo: 946, tipo: :relleno]                 # espacios
[nombre: :ceros, largo: 15, tipo: :relleno, relleno: "0"]
```

## Si ya usas Decimal

Los campos `:decimal` entregan `{unidades, precision}` (o un `AnchoFijo.Monto`
con `:moneda`) para no obligar a una dependencia. Si el proyecto ya trabaja
con `Decimal`, como todo lo que pasa por Ecto, se declara una vez:

```elixir
layout = AnchoFijo.Layout.nuevo!(
  decimales_como: :decimal,          # o como: :decimal en un campo
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

Al escribir, cualquier `:decimal` acepta un `%Decimal{}`, un entero (en
unidades enteras) o un string numérico, además de la tupla y del `Monto`. Un
valor con más decimales que `:precision` es un diagnóstico, nunca un redondeo
silencioso. `Monto.desde_decimal/2` y `Monto.nuevo/3` con un `Decimal` hacen
el camino inverso de `Monto.a_decimal/1`.

No es el default a propósito: `Decimal` es opcional en `ancho_fijo`, y sin la
librería `como: :decimal` es un layout inválido que dice qué agregar. El
paquete sigue sin dependencias de runtime, y quien no usa `Decimal` no paga
por ella.

## Tipos propios

Los cinco tipos son implementaciones del behaviour `AnchoFijo.Tipo`, y un
tipo que solo tiene sentido para un usuario —`:hora`, `:codigo_sucursal`, el
enum de "tipo de movimiento" de su banco— se agrega sin tocar la librería:
un módulo con `opciones/0`, `validar/1` y `leer/3`, y `tipo: MiApp.Hora` en
el layout.

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

`validar/1` corre al construir el layout, no al parsear: un `:fecha` sin
`:formato` sigue siendo un layout inválido, y un tipo propio puede exigir lo
mismo. Los diagnósticos que produce con `Tipo.diagnostico/3` son
indistinguibles de los internos. Que el módulo implemente el behaviour se
verifica también al construir el layout, con `Code.ensure_loaded?/1` por
delante: un módulo que no existe o no implementa los callbacks es un
diagnóstico `:layout`, no un `UndefinedFunctionError` en la línea 40.000. El
ejemplo completo, con una opción propia, está en `AnchoFijo.Tipo`.

## Las reglas del dominio van en el layout

Un tipo dice cómo se lee el campo; el dominio dice qué valores admite. Un
código que solo puede ser `"01"`, `"02"` o `"09"`, un importe que no puede
ser negativo, un identificador con una forma fija, un campo que es
obligatorio solo cuando otro trae cierto valor. Si eso se verifica después
de `parsear/3`, el error ya perdió la línea y la posición. Las reglas se
declaran en el campo, con cualquier tipo:

```elixir
campos: [
  [nombre: :tipo, largo: 2, en: ["01", "02", "09"]],
  [nombre: :monto, largo: 10, tipo: :decimal, precision: 2, rango: {{0, 0}, nil}],
  [nombre: :fecha, largo: 8, tipo: :fecha, formato: :aaaammdd, rango: {~D[2000-01-01], nil}],
  [nombre: :codigo, largo: 4, patron: ~r/^[A-Z]{2}\d{2}$/],
  [nombre: :banco, largo: 3, tipo: :entero, opcional: true, requerido_si: [campo: :tipo, en: ["02"]]],
  [nombre: :glosa, largo: 20, opcional: true, prohibido_si: [campo: :banco]]
]
```

- `en:` es el catálogo: una lista de valores admitidos, o una función de un
  argumento para catálogos grandes o calculados.
- `rango: {min, max}` vale para `:entero`, `:decimal`, `:fecha`, `:hora` y
  `:fecha_hora`, con `nil` en el extremo abierto. Se compara sobre el valor
  ya convertido: una tupla, un `Monto`, un `Decimal` o una fecha, da igual
  cómo venga escrito.
- Al escribir, las reglas miran el mismo valor que devolvería `parsear/3`:
  un `Decimal.new("1.00")`, un `1` o un `"1.00"` en un `:decimal` con
  `precision: 2` son `{100, 2}` para el catálogo y el rango, y un `:texto`
  se recorta antes del patrón.
- Los valores de `en:` y los extremos de `rango:` tienen que ser del tipo
  del campo: un rango de fechas en un `:entero` o un catálogo de textos en
  un `:entero` es un diagnóstico del layout, no una regla que nunca falla o
  que falla siempre.
- `patron:` es una expresión regular sobre el texto recortado.
- `requerido_si:` y `prohibido_si:` miran otro campo del mismo registro:
  `[campo: :tipo, en: [...]]` se cumple cuando ese campo vale alguno de esos;
  `[campo: :banco]`, cuando tiene valor. El layout verifica que el campo
  nombrado exista.

Cada falla es un diagnóstico de tipo `:regla`, con la línea, el campo y sus
posiciones, y `esperado` dice la regla ("un valor en `"01"`, `"02"`",
"un valor de ~D[2000-01-01] en adelante", "un valor, porque :tipo es `"02"`").
En modo estricto rechaza la línea; en tolerante el registro se entrega y el
diagnóstico queda como error. Un campo sensible redacta el valor, como
siempre. Las mismas reglas se aplican al escribir, así que un registro que
no las cumple no sale al archivo. `documentar/2` las muestra en la columna
"Reglas", el layout serializado las conserva (salvo `en:` con función, que
no es un dato) y los generadores de `AnchoFijo.Test.Generadores` las
respetan: eligen del catálogo, se quedan dentro del rango y satisfacen las
condiciones cruzadas. Un `patron:` no se puede invertir, así que ese campo
pide `generador:` con un `StreamData` propio.

## Probar tu layout

Quien adopta la librería escribe siempre los mismos tests. `AnchoFijo.Test`
los deja en una línea cada uno, y con `StreamData` el round-trip se vuelve
una propiedad sobre registros generados a partir del layout:

```elixir
defmodule MiApp.NominaTest do
  use ExUnit.Case
  use ExUnitProperties
  import AnchoFijo.Test

  @layout MiApp.Nomina.layout()

  test "una línea válida" do
    assert_parsea(@layout, "12345678-5JUAN PEREZ  0012345620240131", %{rut: "12345678-5", monto: {123_456, 2}, ...})
  end

  test "un monto con letras se diagnostica en el monto" do
    @layout |> AnchoFijo.parsear("12345678-5JUAN PEREZ  00AB345620240131\n") |> assert_diagnostico(campo: :monto)
  end

  property "escribir y leer da lo mismo para cualquier registro" do
    check all registro <- AnchoFijo.Test.Generadores.registro(@layout), do: assert_round_trip(@layout, registro)
  end
end
```

Los generadores respetan cada campo (largo, signo, precisión o moneda,
formato de fecha, dígito verificador del RUT, opcionales, constantes) y
generan también la lista de `{tipo, mapa}` de un multiregistro;
`linea_invalida/1` da una línea con un campo roto anotado para probar que el
diagnóstico apunta donde debe. Un tipo propio participa con el callback
opcional `generador/1`. La propia suite de la librería corre estas
propiedades sobre sus fixtures, NACHA incluido.

## El layout se valida antes de ver el archivo

```elixir
AnchoFijo.Layout.nuevo(campos: [
  [nombre: :rut, posicion: 1, largo: 10],
  [nombre: :nombre, posicion: 8, largo: 20]
])
# {:error, [%AnchoFijo.Diagnostico{...}]}

# layout, campo :nombre (posiciones 8-27): se esperaba que empezara en la posición 11
# o después, llegó 8; se solapa con el campo :rut (posiciones 1-10)
```

Los huecos son distintos: son advertencias, no errores. Un hueco suele ser una
zona reservada legítima del formato, mientras que un solapamiento es siempre un
error de transcripción del anexo.

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

## Grupos repetidos y variantes

Dos construcciones de los formatos heredados de mainframe: un bloque de campos
que se repite N veces (`OCCURS`), y un tramo del registro que cambia de forma
según el valor de un campo anterior (`REDEFINES`):

```elixir
[nombre: :totales, tipo: :grupo, repetir: 3, campos: [
  [nombre: :moneda, largo: 3],
  [nombre: :importe, largo: 10, tipo: :decimal, precision: 2]
]]
# registro.totales == [%{moneda: "CLP", importe: {125_000, 2}}, %{moneda: "USD", ...}, %{moneda: "EUR", ...}]

[nombre: :destino, tipo: :variante, segun: :tipo_cuenta, variantes: %{
  "01" => [[nombre: :banco, largo: 3], [nombre: :cuenta, largo: 15, tipo: :entero]],
  "02" => [[nombre: :clabe, largo: 18]]
}]
# registro.destino == %{banco: "001", cuenta: 12_345_678}  ó  %{clabe: "0123..."}
```

El largo del grupo se calcula (`repetir` por el de una repetición) y las
variantes miden lo mismo, o el campo declara un `largo` y las más cortas se
completan. Un valor sin variante es un diagnóstico que lista las declaradas, y
un campo interno roto se diagnostica con su ruta y su posición absoluta en la
línea: `campo totales[2].importe (posiciones 29-38)`. La escritura es
simétrica, `documentar` muestra los campos internos con posiciones relativas, y
los generadores de `AnchoFijo.Test` producen la lista y la variante correctas.

## Encodings mezclados por campo

Un caso frecuente en las respuestas de los bancos: el archivo se mide en
bytes y viene en latin-1, salvo el campo de texto libre, que viene en UTF-8.
Decodificar todo como latin-1 da `operaciÃ³n`; decodificar todo como UTF-8
corre los offsets. El encoding se declara por campo:

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

`detectar/2` reconoce la mezcla (`encoding_probable: :mixto`) y sugiere esa
declaración; `unidad_probable` dice en qué unidad son consistentes los largos
cuando hay caracteres multibyte. Y si un `:texto` llega ya con doble
codificación, hay una advertencia `:doble_codificacion` con el texto
reparado; `reparar_doble_codificacion: true` en el campo aplica la
reparación al leer. Un campo que empieza en medio de un carácter multibyte
lo dice así, en vez de reportar un byte latin-1 cualquiera.

## Diagnósticos para el usuario final y para una API

El mensaje de un diagnóstico es para quien integra. Una pantalla de carga
necesita decirle al usuario "línea 42: el monto no es válido" en su idioma y
sin opciones del layout, y una API necesita JSON:

```elixir
AnchoFijo.Diagnostico.mensaje(d, audiencia: :usuario)
# "Línea 42, campo monto: el valor no es válido (se esperaba 8 dígitos con 2 decimales implícitos, llegó "AB")."
AnchoFijo.Diagnostico.mensaje(d, audiencia: :usuario, idioma: :en)
# "Line 42, field monto: the value is not valid (expected 8 dígitos con 2 decimales implícitos, got "AB")."

AnchoFijo.Diagnostico.a_mapa(d)        # claves estables, con :mensaje; y desde_mapa/1 para la vuelta
Jason.encode!(diagnosticos)            # con Jason en el proyecto: Jason.Encoder opcional, redactado

AnchoFijo.resumen(diagnosticos)
# %{errores: 2, advertencias: 1, lineas_afectadas: [2, 7, 9], veredicto: :rechazable,
#   texto: "2 errores en 2 líneas y 1 advertencia: el archivo se rechaza", ...}
```

Lo que la librería traduce es el marco del mensaje y la explicación por tipo
de problema; lo que cada tipo describe en `esperado` y `recibido` es prosa en
español y se muestra tal cual. Todas las salidas respetan `:sensible`.

## Los datos personales no viajan en los diagnósticos

El mensaje que se pega en un correo para el banco es el mismo que termina en un
`Logger.error`, en Sentry y en un ticket. Si el campo que falló es un RUT o un
nombre, ese es el camino por el que los datos de miles de beneficiarios salen
del sistema sin que nadie lo haya decidido (Ley 19.628 en Chile, GDPR si hay
clientes europeos). Lo incómodo es que la información que hace útil al
diagnóstico es la misma que no debería viajar.

Un campo se declara sensible en el layout, y `:rut` lo es por default:

```elixir
[nombre: :beneficiario, largo: 20, sensible: true]
```

Sus diagnósticos muestran la **forma** del valor, no el valor, en
`Diagnostico.mensaje/1`, `reporte/1`, `to_string/1` e `inspect/1`:

```
línea 7, campo :rut (posiciones 1-10): se esperaban un RUT con dígito verificador,
llegaron <10 caracteres: 4 dígitos, 1 letra, 3 dígitos, "-", 1 dígito>; ...
```

La forma es la política de redacción, y es una decisión. Una máscara parcial
(`1234****-*`) deja ver lo suficiente para reidentificar —cuatro dígitos de un
RUT dejan diez mil candidatos— y oculta justo lo que hace falta para depurar.
La supresión total no dice nada. La forma dice que hay una letra donde debía
haber un dígito, y en qué posición, sin decir cuál. El largo no se oculta: es
el ancho del campo, que el layout ya declara.

El valor completo sigue en `:recibido` del struct, y `mensaje(d, revelar: true)`
o `reporte(lista, revelar: true)` lo muestran para uso local e interactivo. La
redacción es de las representaciones, no del dato: quien lo necesita lo lee a
propósito, y el camino accidental —`Logger.error(inspect(diagnostico))`— no lo
lleva. Es el mismo patrón que `redact: true` en Ecto.

Lo que no se redacta, y por qué: un byte inválido y su posición (`el byte 0xC9
en la posición 14`) no es un dato personal y es el diagnóstico entero de un
problema de encoding; la medida de una línea corta es un número; y las
observaciones de `detectar/2` citan a lo sumo un byte y un delimitador, nunca
el contenido de un campo. Las entradas que no son binarios se describen por
tipo ("una lista de 3 elementos") en vez de imprimirse. Lo mismo al
escribir: un valor que no cabe, un RUT con el DV malo o un texto truncado
se reportan con la forma del valor, no con el valor. Hay un test que recorre
cada tipo de campo y cada falla posible, al leer y al escribir, y verifica la
ausencia del valor en cada representación.

## Trazabilidad: del registro al byte, y la huella del lote

Cuando el banco rechaza una nómina de 40.000 líneas, la conversación es "el
registro del beneficiario X está mal", y lo primero que se pide es volver del
dato al lugar físico del archivo del que salió. Con `traza: true`, cada
registro trae la clave reservada `:__traza__`:

```elixir
{:ok, registros, []} = AnchoFijo.parsear(layout, "nomina.txt", traza: true)

registro = Enum.at(registros, 6)
registro.__traza__
# %AnchoFijo.Traza{linea: 7, offset: 288, largo: 48}

AnchoFijo.Traza.linea_original(registro.__traza__, File.read!("nomina.txt"))
# "12345678-5JUAN PEREZ          000012345620240115"
```

La forma de retorno fue una decisión. Una tupla `{registro, traza}` o un
struct `%Registro{valores: ..., traza: ...}` cambian la forma para todo el
código que ya lee `registro.monto`. La clave `:__traza__` no: el registro
sigue siendo el mapa, la traza está al lado, y los dos guiones bajos son la
convención de Elixir para metadatos que no chocan con datos (`__struct__`,
`__meta__` en Ecto). Un campo del layout no se puede llamar así. Apagada, la
opción no cuesta nada: el camino de parseo es el mismo de siempre y no se
calcula ni se agrega nada; medido sobre 100.000 líneas, encenderla cuesta un
45 % de tiempo y un 35 % de memoria en `parsear/3`, y nada medible en
`stream/3`, que lleva el offset en el acumulador sin estado global.

La huella del lote es la otra mitad de la trazabilidad: demostrar *qué*
archivo se procesó.

```elixir
AnchoFijo.huella("nomina.txt")
# {:ok, "sha256:3164aeb0f4d85eabb8bcc255402e83170729ffe8cb076483b98caf2407eca512"}
```

Es un SHA-256 estable entre corridas y sensible a cualquier byte de datos. Lo
que no cambia la huella es lo que no cambia lo que el parser lee: el estilo
de terminador de línea (CRLF, LF o CR, normalizados a LF) y la presencia del
terminador en la última línea. Un archivo que pasó por un editor de Windows es
el mismo lote. Lo que sí cambia la huella, a propósito: un espacio de relleno
de más o de menos (es un byte del registro) y el encoding (los bytes son el
dato). Con `normalizar: false` se calcula sobre los bytes exactos, que es lo
que da `sha256sum`. Se calcula por bloques, así que un archivo de gigabytes
no se carga en memoria.

## Observabilidad

Una librería que procesa archivos de 2 GB de noche y no emite un solo evento
es una caja negra. `ancho_fijo` emite eventos de `:telemetry` con el patrón
`start`/`stop`/`exception` del ecosistema, bajo el prefijo `[:ancho_fijo, ...]`,
para `parsear/3`, `detectar/2` y `stream/3`. Suscribirse son tres líneas:

```elixir
:telemetry.attach("nomina", [:ancho_fijo, :parsear, :stop], fn _evento, medidas, metadata, _ ->
  Logger.info("#{metadata.layout}: #{medidas.registros} registros, #{medidas.errores} errores")
end, nil)
```

El `stop` de `parsear/3` trae `duration`, `lineas`, `registros`, `errores` y
`advertencias`; el de `stream/3` lo mismo, contado en el acumulador del stream
sin acumular registros ni romper la laziness, y sale también si la
enumeración se corta. No hay un evento por línea que falla: en un archivo con
10.000 filas malas serían 10.000 eventos, cada uno con un diagnóstico que
puede traer datos personales. El contrato completo, evento por evento, está
en `AnchoFijo.Telemetria`.

`:telemetry` es una dependencia **opcional**: hay que agregarla al proyecto
para recibir los eventos. Ver la decisión más abajo.

## Idempotencia: reconocer el archivo que ya se procesó

El error operacional más caro de una nómina no es una fila mal parseada: es
el mismo archivo procesado dos veces, por un reintento manual, un cron que
corrió dos veces o un correo reenviado. La librería es el punto natural para
detectarlo, porque ve el archivo completo antes de que exista un solo
registro en la base de datos.

```elixir
layout = AnchoFijo.Layout.nuevo!(identidad: [campos: [:lote, :fecha]], campos: [...])

{:ok, identidad} = AnchoFijo.identidad(layout, "nomina.txt")
# %AnchoFijo.Identidad{declarada: %{lote: 1, fecha: ~D[2024-01-15]}, huella: "sha256:...", nombre: "nomina.txt"}

case AnchoFijo.Identidad.cotejar(identidad, identidades_ya_procesadas) do
  :nueva -> procesar(...)
  {:duplicada, vista} -> rechazar("ya se procesó el #{vista.nombre}")
  {:conflicto, diagnostico, _vista} -> escalar(AnchoFijo.Diagnostico.mensaje(diagnostico))
end
```

Con un `AnchoFijo.Multiregistro` la identidad declarada sale del header, que
tiene su propio layout: `AnchoFijo.identidad(AnchoFijo.Formatos.nacha(), ruta)`
trae el *immediate origin*, la fecha, la hora y el *file ID modifier*.

Tres fuentes, en orden de confiabilidad decreciente: lo que el archivo
declara de sí mismo (el número de lote y la fecha del header, que el layout
señala con `identidad:`), la huella del contenido, y el nombre del archivo,
que es informativo y nada más. La huella manda: el mismo contenido es un
duplicado aunque cambie el nombre. Y la misma identidad declarada con otro
contenido **no es un duplicado, es algo peor**: el emisor reutilizó el número
de lote o alguien editó el archivo, y tiene su propio diagnóstico.

**La frontera.** La librería no persiste nada ni tiene estado: recibe las
identidades que el llamador ya vio, responde, y punto. El día en que un
parser abre una tabla o un ETS deja de ser un parser, y además decide por el
usuario cuánto tiempo recordar y qué hacer con un duplicado. Eso es del
sistema que paga: guardar la huella y lo declarado de cada archivo procesado
y consultarlos antes de empezar.

## Decisiones y trade-offs

**Las posiciones se cuentan en bytes, no en caracteres.** Un formato de ancho
fijo se define sobre el archivo físico: cuando el banco dice "120 posiciones",
cuenta bytes. Con latin-1 es lo mismo. Con UTF-8 no, y ahí está el trade-off: si
el emisor contó caracteres, hay que declarar `unidad: :caracteres` o cada línea
con una "ñ" se corre un byte. La librería no lo adivina, pero `detectar/2`
reporta los dos largos cuando difieren, que es la señal para saber cuál usar.

**Los montos son `{unidades, precision}` y no `Decimal`, por default.** Cumple
con "ningún float en el camino" sin sumar una dependencia. El costo es que hay
que convertir en el borde, o declarar `decimales_como: :decimal` si el proyecto
ya tiene `Decimal`: entonces los campos leen y escriben `%Decimal{}`. Para un
paquete que se vende como chico, la dependencia obligatoria pesaba más que una
declaración de una línea.

**Los huecos no bloquean, los solapamientos sí.** Explicado arriba. La
consecuencia es que un layout con un campo olvidado en el medio parsea igual, y
solo queda constancia en `layout.advertencias`. Se eligió así porque la
alternativa —obligar a declarar campos `:filler` para satisfacer al validador—
hace que la definición deje de parecerse al anexo que se está transcribiendo.

**Una línea de largo incorrecto reporta un solo diagnóstico.** Si la línea no
mide lo que debe, no se intentan leer sus campos. Un byte faltante corre todos
los campos que vienen después, y reportar los doce diagnósticos derivados
esconde el único que importa. El costo: en modo tolerante no se ve el detalle
de los campos de una fila con largo malo.

**Los dos modos devuelven `{:ok, registros, diagnosticos}`.** El modo estricto
también, aunque al llegar a `:ok` la lista solo pueda traer advertencias. La
alternativa —dos elementos en estricto, tres en tolerante— obliga al llamador a
saber en qué modo llamó para saber qué desestructurar, y deja las advertencias
sin dónde ir en el modo que se usa justamente para archivos que son contratos.
Una advertencia que se descarta por no ser un error es un supuesto que nadie
revisó.

**Una advertencia no reemplaza a su registro, lo acompaña.** El registro está en
`registros` con su valor, y el diagnóstico de gravedad `:advertencia` dice qué
se asumió para llegar a él. Un error, en cambio, no deja registro: no hay valor
que entregar.

**Se rechazan los caracteres de control en ambos encodings.** El rango
0x80–0x9F es control en latin-1 pero trae comillas y guiones en Windows-1252.
Encontrarlo es la señal más confiable de que el archivo es cp1252 y no latin-1,
y el diagnóstico lo dice en vez de devolver basura silenciosa. El costo es que un
archivo con un byte de control legítimo —no existe en ancho fijo bancario, pero
podría existir— necesitaría otra estrategia.

**No hay soporte de cp1252 ni de otros encodings.** Solo `:utf8` y `:latin1`.
Agregar una tabla de transcodificación por cada codepage del mundo es cómo un
paquete chico deja de estar terminado. El diagnóstico apunta al problema y la
conversión previa es una línea de `iconv`.

**Dos formas de fallar, y solo dos.** Un problema con los datos es un
`AnchoFijo.Diagnostico`, como valor o dentro de `AnchoFijo.Error`. Un problema
con la llamada —una opción que no existe, un valor de otro tipo— es un
`ArgumentError` que nombra la función y la opción, como en la stdlib: no es un
diagnóstico porque no hay nada que mandarle al banco. Una clave desconocida en
un layout (`enconding:`, `precison:`) también es un error de la definición, no
algo que se ignora: dejaría un layout distinto del que se escribió sin ninguna
señal. Los módulos de apoyo (`AnchoFijo.Rut`, `AnchoFijo.Transcodificacion`,
`AnchoFijo.Campo.extraer/3`) usan guardas y levantan `FunctionClauseError` ante
tipos equivocados, igual que `String.upcase(42)`; el contrato de las dos formas
es de los puntos de entrada. Hay un test que le pasa basura a cada uno para
sostenerlo.

**`:telemetry` es opcional, y el paquete sigue sin dependencias de runtime.**
Las dos opciones eran declararla obligatoria (30 KB, sin dependencias, ya
instalada en cualquier app Phoenix) o `optional: true` con una decisión en
tiempo de compilación. Se eligió la segunda porque la promesa de cero
dependencias vale sobre todo fuera de Phoenix: el script de migración, el
`Mix.Task`, el `escript` donde cada dependencia es fricción y nadie va a
mirar un dashboard. El costo es un `if Code.ensure_loaded?(:telemetry)` en el
cuerpo de un módulo: con la dependencia presente las llamadas se compilan,
sin ella no existe ni una, y en runtime no hay ningún `if`. La parte fea:
si se agrega `:telemetry` después de haber compilado `ancho_fijo`, hay que
recompilarlo (`mix deps.compile ancho_fijo --force`). Está en la doc del
módulo.

**`moneda:` devuelve un struct; sin `moneda:` sigue la tupla.** Las tres
opciones eran seguir con `{unidades, precision}` y solo validar (cero
migración, pero sumar CLP con USD sigue sin quejarse), `{unidades, precision,
moneda}` (rompe todo el pattern matching publicado en Hex) o un struct. Se
eligió el struct, pero solo cuando el layout declara la moneda: quien no la
declara no cambia una línea, y quien la declara pidió a propósito un valor
que sabe de qué moneda es. `%AnchoFijo.Monto{}` tiene tres campos, cinco
operaciones sobre enteros y un `Inspect`; no es una librería de dinero
disfrazada, y `a_decimal/1` entrega el monto a quien sí tenga una. La tabla
ISO 4217 es acotada a propósito: todas las monedas con escala distinta de
dos, que son las que importan, más las de la región y las de reserva. Una
moneda que falta con `:precision` explícita se acepta con una advertencia
del layout; sin `:precision`, es un error.

**La API es en español, y va a seguir siéndolo.** Es una decisión de
identidad, y el dominio (RUT, Previred, nóminas chilenas y latinoamericanas)
es latinoamericano: los nombres de los campos en los layouts de los bancos ya
vienen en español. La objeción que aparece no es "no entiendo español" sino
"no quiero mezclar `Layout.nuevo!` con el resto de mi código". Se pesaron
cuatro opciones: renombrar todo a inglés (rompe la API, pierde la identidad y
deja los diagnósticos a medias, porque los mensajes son prosa en español);
documentación bilingüe ([README.en.md](README.en.md), el glosario de abajo y
`idioma: :en` en `Diagnostico.mensaje/2` para los mensajes al usuario), que
es lo que hay; una fachada en inglés dentro del mismo paquete (dos nombres
para cada cosa confunden la documentación y duplican la superficie); y un
paquete hermano `fixed_width` que dependa de este y exponga
`FixedWidth.Layout.new!/1`, `FixedWidth.parse/3` y `FixedWidth.write/3` con
las opciones traducidas en la frontera. El criterio para la última, escrito:
**la fachada existe cuando hay un proyecto que la necesita, no antes.**

## Glosario

Los nombres de la librería, del español al inglés, para quien evalúa el
paquete desde una base de código en inglés. La guía completa en inglés es
[README.en.md](README.en.md), y un test verifica que los dos glosarios sean el
mismo.

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

## Mantenimiento, compatibilidad y soporte

Lo que un equipo necesita saber antes de depender de esto, en un lugar.

**Quién lo mantiene.** [@galenzo17](https://github.com/galenzo17), que es
también el dueño del paquete en Hex. Los PRs piden su revisión por
[`CODEOWNERS`](https://github.com/galenzo17/ancho_fijo/blob/main/.github/CODEOWNERS). Cada cambio tiene su prompt en
[`prompts/`](prompts/README.md), con el pedido, el resultado y las decisiones.

**Cómo reportar un problema de seguridad.** Por el reporte privado de GitHub,
como dice [SECURITY.md](SECURITY.md): acuse en 3 días hábiles, plan en 14,
corrección publicada en Hex con una entrada `### Seguridad` en el CHANGELOG.
No en un issue público.

**Qué versiones de Elixir y OTP.** `elixir: "~> 1.14"`. La CI corre la suite
completa, con warnings como errores, en Elixir 1.14 / OTP 25, 1.16 / OTP 26,
1.18 / OTP 27 y 1.20 / OTP 28, y además compila la librería como dependencia
de un proyecto vacío en la versión más vieja y en la más nueva. Una versión
de Elixir sale de la matriz solo en una versión mayor o menor nueva de la
librería, y el CHANGELOG lo dice. No hay dependencias de runtime; `:decimal`
y `:telemetry` son opcionales y la librería compila con y sin ellas.

**Qué es un cambio incompatible.** El paquete sigue
[versionado semántico](https://semver.org/lang/es/). Mientras la versión sea
`0.x`, una versión menor (`0.3` → `0.4`) puede romper compatibilidad, siempre
bajo un título `### Cambiado — rompe compatibilidad` en el CHANGELOG que dice
qué hay que tocar; una versión de corrección (`0.3.1` → `0.3.2`) nunca. Es
incompatible todo lo que obligue a cambiar código que hoy funciona: la forma
de los valores devueltos (`{unidades, precision}`, `%Monto{}`, `%Decimal{}`),
las opciones de layout y de campo y su significado, los campos de
`%Diagnostico{}` y la forma de los mapas de `a_mapa/1`. No lo es agregar
tipos, opciones, diagnósticos nuevos o texto a los mensajes, ni cambiar
módulos `@moduledoc false`.

**Cuánto dura una serie.** Se mantiene la última serie publicada. Cuando sale
una serie nueva que rompe compatibilidad, la anterior recibe correcciones de
seguridad durante los seis meses siguientes, si el arreglo es acotado.
[SECURITY.md](SECURITY.md) tiene la tabla.

**Cómo se publica.** Solo desde CI, al empujar un tag `vX.Y.Z`
([`release.yml`](.github/workflows/release.yml)): el workflow verifica que el
tag coincida con `mix.exs` y el CHANGELOG, corre la suite y publica paquete y
docs con la credencial del repositorio. Las dependencias de desarrollo pasan
por `mix hex.audit` y `mix deps.audit` en cada CI y Dependabot propone las
actualizaciones.

## Documentación

[hexdocs.pm/ancho_fijo](https://hexdocs.pm/ancho_fijo)

## Licencia

MIT. Ver [LICENSE](LICENSE).
