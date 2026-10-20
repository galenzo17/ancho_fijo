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
  [{:ancho_fijo, "~> 0.2.0"}]
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

`stream/3` emite `{:ok, registro, advertencias}` o `{:error, diagnosticos}` por
línea. Qué hacer con los errores es decisión del consumidor: acumular todos los
diagnósticos de un archivo de 2 GB para devolverlos al final anularía el punto de
ser lazy. Las advertencias viajan pegadas a su registro por la misma razón: no
hay dónde juntarlas.

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

## Tipos de campo

| tipo | valor devuelto | opciones |
| --- | --- | --- |
| `:texto` | `String.t()` en UTF-8 | `:trim`, `:relleno`, `:opcional` |
| `:entero` | `integer()` | `:opcional`, `:signo` |
| `:decimal` | `{unidades, precision}` | `:precision` (obligatoria), `:separador`, `:signo` |
| `:fecha` | `Date.t()` | `:formato` (obligatorio), `:opcional` |
| `:rut` | `String.t()` canónico, `"12345678-5"`; solo el cuerpo con `dv: :ausente` | `:dv`, `:opcional` |

Un monto de `0000125000` con `precision: 2` se lee como `{125000, 2}`: 125.000
unidades mínimas con escala 2, es decir 1.250,00. Nunca hay un float en el
camino. Un monto que pasó por punto flotante deja de cuadrar con la contabilidad
del banco y nadie sabe dónde se perdió el peso.

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
tipo ("una lista de 3 elementos") en vez de imprimirse. Hay un test que
recorre cada tipo de campo y cada falla posible y verifica la ausencia del
valor en cada representación.

## Decisiones y trade-offs

**Las posiciones se cuentan en bytes, no en caracteres.** Un formato de ancho
fijo se define sobre el archivo físico: cuando el banco dice "120 posiciones",
cuenta bytes. Con latin-1 es lo mismo. Con UTF-8 no, y ahí está el trade-off: si
el emisor contó caracteres, hay que declarar `unidad: :caracteres` o cada línea
con una "ñ" se corre un byte. La librería no lo adivina, pero `detectar/2`
reporta los dos largos cuando difieren, que es la señal para saber cuál usar.

**Los montos son `{unidades, precision}` y no `Decimal`.** Cumple con "ningún
float en el camino" sin sumar una dependencia. El costo es que hay que convertir
en el borde: `Decimal.new(1, unidades, -precision)` si se usa esa librería, o
`div/2` y `rem/2` para formatear. Para un paquete que se vende como chico, la
dependencia obligatoria pesaba más que la conversión de una línea.

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

**Solo lectura en 0.2.** Sin escritura de archivos y sin multiregistro
(header/detalle/trailer). Ver el [CHANGELOG](CHANGELOG.md).

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

## Documentación

[hexdocs.pm/ancho_fijo](https://hexdocs.pm/ancho_fijo)

## Licencia

MIT. Ver [LICENSE](LICENSE).
