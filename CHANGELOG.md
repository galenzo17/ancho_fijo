# Changelog

Este proyecto sigue [Versionado Semántico](https://semver.org/lang/es/).

## [No publicado]

### Cambiado — rompe compatibilidad

- Sin `desde:`, un binario que parece una ruta (termina en una extensión
  como `.txt`, o empieza con `/`, `./`, `../`, `~/` o una unidad de
  Windows) y no existe es un diagnóstico `:entrada`
  ("la ruta no existe; revise el directorio de trabajo; si quiso pasar el
  contenido y no una ruta, declare `desde: :contenido`") en `parsear/3`,
  `parsear!/3`, `stream/3`, `detectar/2`, `huella/2` e `identidad/3`, con
  `Layout` y con `Multiregistro`. Antes se trataba como el contenido de una
  línea: el diagnóstico culpaba al largo de la línea, y `huella/2` devolvía
  la huella del nombre del archivo. Qué tocar: un contenido de una sola
  línea sin terminador que termina en algo como `.txt` o empieza con `/`
  ahora necesita `desde: :contenido`; con terminador, o sin eso, nada
  cambia: `"01/01/1950"` sigue siendo contenido (#93).

### Corregido

- `AnchoFijo.Json.decodificar/1`, y con él `Layout.desde_json/1`,
  `Multiregistro.desde_json/1` y las tareas Mix que leen un `.json`, devuelve
  `{:error, motivo}` ante un escape `\u` que no es hexadecimal, un
  *surrogate* sin su par o un número que no cabe en un float (`1e999`).
  Antes escapaba un `throw` (o un `ArgumentError`) que nadie atrapaba y que
  tumbaba la tarea en vez de terminar con código 2. Una propiedad verifica
  que el decodificador nunca levanta (#89).
- `Layout.desde_mapa/1` y `Multiregistro.desde_mapa/1` (y `desde_json/1` y
  las tareas Mix) devuelven diagnósticos `:layout` con el campo y la clave
  ante un `"rango"` con una fecha, hora o decimal que no se puede leer, un
  `"patron"` que no compila o con opciones que no son texto, y un extremo
  decimal como texto en un proyecto sin `Decimal`. Antes levantaban
  `ArgumentError`, `Regex.CompileError` o `Decimal.Error`. Los extremos de
  un `"rango"` se exigen del tipo del campo. Dos propiedades con basura en
  cualquier clave del mapa, a cualquier profundidad, sostienen que nunca
  levantan, y destaparon otras cuatro excepciones que también se corrigen:
  un nombre de campo que no es átomo en un grupo o variante, un
  `:variantes` cuyo valor no es una lista, un control con `:en` que no es
  átomo y un nombre con bytes que no son UTF-8 (#90).
- Al escribir, los diagnósticos de un campo `sensible: true` (y `:rut` lo
  es por default) salen marcados con la forma del valor, como al leer: un
  texto que no cabe, un RUT con el DV malo, un entero donde iba una fecha,
  un monto de otra moneda, un carácter que latin-1 no tiene, una regla que
  no se cumple y la advertencia de un texto truncado ya no muestran el valor
  en `mensaje/1`, `reporte/1`, `inspect/1`, `a_mapa/1` ni en JSON; con
  `revelar: true` sí. Cubre los campos internos sensibles de un grupo o una
  variante. Un decimal sensible fuera de rango levantaba
  `Protocol.UndefinedError` al describir la tupla; ya no. La matriz de
  `sensibles_test.exs` recorre también la escritura (#91).
- Al escribir, las reglas `en:`, `rango:`, `patron:`, `requerido_si:` y
  `prohibido_si:` miran el valor canónico del campo, el que devolvería
  `parsear/3`: un `Decimal.new("1.00")`, un `1` o un `"1.00"` en un
  `:decimal` con `precision: 2` son `{100, 2}` para el catálogo y el rango,
  y un `:texto` se recorta antes del patrón. Antes un `Decimal` válido no
  pasaba el catálogo y un string fuera de rango se escribía igual. El
  catálogo compara las formas numéricas entre sí (`{100, 2}` es
  `Decimal.new("1.00")`) (#92).
- Los valores de `en:` y los extremos de `rango:` tienen que ser del tipo
  del campo: un rango de fechas en un `:entero` o un catálogo de textos en
  un `:entero` es un diagnóstico `:layout` por cada valor, no una regla que
  nunca falla o que falla siempre. `Reglas.comparar/2` levanta
  `ArgumentError` para lo incomparable en vez de contestar `:eq` (#92).
- Con `encoding: :latin1`, `relleno_final: :tolerar` y un `:relleno` no
  ASCII (`"·"`), el lector repone al final de la línea lo que el escritor
  completó: el relleno se transcodifica al encoding del campo o del layout
  antes de medirlo y de pegarlo. Antes se medía en UTF-8 (dos bytes) y la
  línea corta era un `:largo_de_linea`. Un relleno que no existe en latin-1
  (`"€"`) en un campo latin-1 es ahora una advertencia de `Layout.nuevo/1`
  (#94).
- `traza: true` ya no hace que `parsear/3` (y `Multiregistro.parsear/3`)
  parta y numere todas las líneas antes de leer la primera: la traza sale
  del mismo recorrido lazy que parte las líneas. En modo estricto sobre
  500.000 líneas con la primera mala, de 700–820 ms y 210–280 MB de heap a
  menos de 10 ms y ~5 KB (`bench/README.md`). Las trazas son las mismas
  para LF, CRLF y CR, con y sin terminador final (#96).

- La 0.4.0 leía menos líneas por segundo que la 0.3.1. Se recuperó casi
  todo: el patrón de `:fecha`, `:hora` y `:fecha_hora` se compila una vez
  en `Campo.nuevo/1` (antes, en cada lectura y cada escritura), `Patron`
  corta por bytes con un solo recorrido cuando el texto mide lo que el
  patrón, las reglas y las condiciones cruzadas no se evalúan cuando el
  layout no las declara, una línea ASCII se valida una vez y no tramo por
  tramo, y el terminador se recorta byte a byte. En la misma máquina,
  `Parser.parsear_linea/3` sobre cuatro campos pasó de 3,08 a 2,53 µs
  (0.3.1: 2,40) y `stream/3` de 256–273 a 303–315 líneas/ms (0.3.1:
  323–331). Sin cambios de comportamiento; `bench/README.md` tiene la
  tabla (#95).

### Agregado

- `encoding: :cp1252` (Windows-1252, lo que exportan Excel y Notepad) en el
  layout y por campo: latin-1 más los 27 caracteres de 0x80–0x9F (el euro,
  las comillas tipográficas, los guiones largos). Se lee, se escribe (un
  carácter que no tiene es un diagnóstico `:encoding` con su posición) y
  se repone como relleno; los cinco bytes que Windows-1252 no define son un
  diagnóstico. `detectar/2` lo reconoce (`encoding_probable: :cp1252`) y
  `contrastar/2` lo reclama frente a un layout UTF-8 o latin-1; los
  diagnósticos que antes decían "el archivo probablemente es cp1252" ahora
  dicen qué declarar. `Transcodificacion.de_utf8/2` es el inverso de
  `a_utf8/2` para los tres encodings (#99).
- `detectar/2` reconoce las marcas que Windows y los mainframes dejan en el
  archivo: el BOM UTF-8 de Notepad y Excel (clave `:bom`, los largos se
  cuentan sin él), UTF-16 con o sin BOM y EBCDIC (`encoding_probable:
  :utf16 | :ebcdic`, con el `iconv` que lo convierte en la observación y
  sin aconsejar `encoding: :latin1`) y el `0x1A` final de DOS
  (`marca_final_dos?`). `parsear/3` y `stream/3` aceptan `bom: :rechazar |
  :ignorar` (default `:rechazar`, y el diagnóstico de largo de la línea 1
  nombra el BOM; con `:ignorar` se salta y `parsear/3` deja una
  advertencia). Una última línea que es solo `0x1A` se omite con
  `omitir_vacias: true` y `parsear/3` lo advierte; sin `omitir_vacias`, el
  diagnóstico dice qué es. Fixtures con los cuatro casos (#98).
- `AnchoFijo.Campo` guarda el patrón compilado de un campo de fecha u hora
  en `:formato_compilado`, y `AnchoFijo.Layout` precalcula
  `:con_condiciones`: datos derivados, como `:modulo`, que la serialización
  no emite (#95).
- La tabla ISO 4217 de `AnchoFijo.Monto` trae ahora todas las monedas con
  escala distinta de dos (faltaban CLF y UYW, de cuatro decimales, y BIF y
  UYI, de cero) y las de la región que faltaban (VES, VED, CUP, BZD, SVC,
  HTG, JMD, TTD, BSD, BBD, XCD, XCG, GYD, SRD, AWG, ANG, COU, MXV, BOV).
  `moneda: :clf` lee la UF como `#AnchoFijo.Monto<1.234,5678 CLF>` sin
  declarar precisión. Un test contrasta la tabla con la lista de ISO 4217
  (#97).

## [0.4.0] — 2026-10-23

### Cambiado — rompe compatibilidad

- `AnchoFijo.Multiregistro.nuevo/1` rechaza las claves que no existen en la
  definición (`controls:`, `discriminator:`) con un diagnóstico `:layout`,
  como ya hacía `Layout.nuevo/1`. Antes se ignoraban en silencio. Qué tocar:
  corregir la clave; el diagnóstico la nombra.
- `AnchoFijo.Multiregistro.parsear/3`, `stream/3`, `AnchoFijo.escribir/3` y
  `Escritor.stream/3` validan sus opciones: una opción desconocida
  (`truncarr:`) o un valor fuera del esquema (`modo: :otro`,
  `terminador: :lf2`) es `ArgumentError` que nombra la función y la opción.
  Antes se ignoraban o fallaban con `KeyError`/`FunctionClauseError`. Qué
  tocar: corregir la opción.
- Un `:relleno` de más de un byte (`"·"`) en un layout que mide en bytes y
  codifica UTF-8 es un error al escribir y una advertencia de
  `Layout.nuevo/1`. Antes se escribía repetido tantas veces como bytes
  faltaban y la línea quedaba más ancha que su largo. Qué tocar: usar un
  relleno de un byte (`" "`, `"0"`) o declarar `unidad: :caracteres`.

### Cambiado

- Los diagnósticos de "no cabe" y de `truncar: true` dicen el largo en bytes
  y en caracteres cuando difieren ("5 posiciones en 4 (5 bytes, 4
  caracteres)"), que es lo que explica por qué un texto con tildes no cabe
  donde caben sus letras. Con solo ASCII el mensaje no cambia.

- El diagnóstico de una fecha con el largo equivocado dice "se esperaban 8
  posiciones (DDMMAAAA)" en vez de "8 dígitos", porque ahora un formato
  puede traer separadores.

### Corregido

- Un `:relleno` de más de un byte (`"·"`) en un layout que mide en bytes en
  UTF-8 se escribía repetido tantas veces como bytes faltaban y el campo
  quedaba más ancho que su largo, corriendo las columnas siguientes. Ahora
  es un error al escribir y una advertencia de `Layout.nuevo/1`.

- `AnchoFijo.parsear!/3` acepta un `AnchoFijo.Multiregistro`, como
  `parsear/3` y `stream/3`. Antes intentaba coercer el struct como layout y
  levantaba un diagnóstico `:layout` que culpaba a una definición válida.
  Nuevo `AnchoFijo.Multiregistro.parsear!/3`, con el contrato de
  `Parser.parsear!/3`: en `:tolerante` levanta con todos los errores, las
  advertencias no se devuelven.
- El mensaje de un diagnóstico `:estructura` sin línea (un trailer que no
  llegó) empieza con `estructura:` y no con `entrada:`, que culpaba a la
  lectura del archivo.
- `AnchoFijo.Multiregistro.parsear/3` y `stream/3` validan las opciones con
  el mismo esquema que `Parser`: una opción desconocida o `modo: :otro` es
  `ArgumentError`, no silencio ni `FunctionClauseError`. `traza: true`
  funciona (antes se aceptaba y no hacía nada): cada mapa trae `:__traza__`
  con el offset real. Y `parsear/3` parte el contenido de forma lazy, como
  `Parser` desde la 0.2.0.
- `Multiregistro.nuevo/1` rechaza las claves que no existen (`controls:`)
  con un diagnóstico `:layout`, como `Layout.nuevo/1`.
- `AnchoFijo.escribir/3` y `Escritor.stream/3` validan las opciones:
  `terminador: :lf2` era un `KeyError` desde `Map.fetch!/2` y `truncarr:`
  se ignoraba. Ahora son `ArgumentError` que nombra la función y la opción.
- `AnchoFijo.identidad/3` acepta un `Multiregistro`: la identidad declarada
  se lee del header, con el layout del primer tipo de `:registros` que
  tenga `identidad:`; si el archivo empieza por otro tipo, es un
  diagnóstico `:identidad`. Antes fallaba con los diagnósticos de layout
  engañosos de `parsear!/3`.

### Agregado

- `README.en.md`: la guía completa en inglés (detectar, parsear, escribir,
  multiregistro, tipos propios, reglas, pruebas, trazabilidad, decisiones),
  publicada también en hexdocs como "English guide", con la tabla generada
  por `documentar/2` en inglés. Glosario español → inglés de funciones,
  opciones, tipos y diagnósticos en los dos README, con un test que los
  mantiene iguales. La sección "Decisiones y trade-offs" explica por qué la
  API es en español y el criterio para una fachada en inglés.

- Reglas declarativas por campo, para cualquier tipo: `en:` (catálogo, lista
  o función), `rango: {min, max}` en `:entero`, `:decimal`, `:fecha`,
  `:hora` y `:fecha_hora`, `patron:` en `:texto`, y `requerido_si:` /
  `prohibido_si:` condicionadas a otro campo del registro. Se verifican al
  leer y al escribir, sobre el valor convertido; cada falla es un
  diagnóstico de tipo `:regla` (nuevo) con línea, campo y posiciones,
  redactado si el campo es sensible. En modo estricto rechaza la línea; en
  tolerante el registro se entrega y el diagnóstico queda como error.
  `Layout.nuevo/1` valida la forma de cada regla y que las condiciones
  nombren un campo del layout. `documentar/2` suma la columna "Reglas", la
  serialización conserva patrón, rangos y condiciones (`en:` con función es
  `ArgumentError`), y los generadores de `AnchoFijo.Test.Generadores`
  eligen del catálogo, respetan el rango y satisfacen las condiciones;
  `generador:` admite un `StreamData` propio para un campo, obligatorio si
  tiene `patron:`.
- Tipos `:grupo` y `:variante`, el `OCCURS` y el `REDEFINES` de los formatos
  heredados: `[tipo: :grupo, repetir: 3, campos: [...]]` lee una lista de
  mapas y `[tipo: :variante, segun: :tipo_cuenta, variantes: %{"01" =>
  [...], ...}]` el mapa de la variante que eligió el campo anterior. Largo
  calculado o verificado, campos internos validados como un layout chico,
  diagnósticos con la ruta del campo interno (`totales[2].importe`) y su
  posición absoluta, escritura simétrica, serialización, documentación con
  posiciones relativas y generadores.
- `AnchoFijo.Test`: `assert_parsea/4`, `assert_diagnostico/2`,
  `assert_round_trip/3` y `assert_escribe/4` para los tests de quien usa la
  librería, con los diagnósticos en el mensaje del fallo. Y
  `AnchoFijo.Test.Generadores` (con `StreamData` en el proyecto):
  `registro/1` genera registros válidos para cualquier layout o
  multiregistro a partir de sus campos, `linea/1` y `linea_invalida/1` con
  el campo roto anotado. Callback opcional `generador/1` en
  `AnchoFijo.Tipo` para los tipos propios. La suite de la librería corre el
  round-trip como propiedad sobre sus fixtures, NACHA incluido.
- Layouts como datos: `Layout.a_mapa/1` y `desde_mapa/1` (mapa de claves
  string, sin átomos ni funciones, con `"version"` del esquema y los mismos
  diagnósticos que `nuevo/1`), `a_json/1` y `desde_json/1` sin dependencias,
  y las cuatro también en `Multiregistro`. `mix ancho_fijo.detectar
  --layout` y `mix ancho_fijo.documentar` aceptan un `.json`. JSON Schema en
  `priv/layout.schema.json`. Un discriminador por función no se serializa.
- La especificación del formato generada desde el layout:
  `AnchoFijo.Documentacion.documentar/2` (también `Layout.documentar/2` y
  `Multiregistro.documentar/2`) en Markdown, CSV o JSON, en español o en
  inglés (encabezados y tipos; los nombres de campo son del formato), y
  `mix ancho_fijo.documentar RUTA.exs [--formato ...] [--idioma ...]`. Con
  un multiregistro, una tabla por tipo más los controles. Opciones de campo
  `descripcion:` y `ejemplo:`, que el parser ignora.
- Diagnósticos para el usuario final y para una API: `Diagnostico.mensaje/2`
  con `audiencia: :usuario` (sin causa probable ni sintaxis de átomos) e
  `idioma: :en` (el marco y la explicación por tipo en inglés; el detalle
  que cada tipo describe sigue en español); `Diagnostico.a_mapa/2` y
  `desde_mapa/1` con claves estables; `Jason.Encoder` opcional cuando
  `Jason` está en el proyecto; `AnchoFijo.resumen/2` con totales por
  gravedad, tipo y campo, las primeras líneas afectadas y el veredicto
  (`:aceptable`, `:aceptable_con_observaciones`, `:rechazable`) con su
  texto. Todas respetan `:sensible`.
- `AnchoFijo.escribir/3` con un `Multiregistro`: los `{tipo, mapa}` en el
  orden del archivo, cada uno con el layout de su tipo, con la estructura
  verificada (orden, cantidades, lo obligatorio que falta) y los controles
  calculados: `cuenta:` y `suma:` salen de los detalles sin que el trailer
  los traiga, y si los trae con otro valor es un diagnóstico `:control`.
  Con `discriminador: [campo: ...]` también acepta el mapa solo. Sin
  versión lazy: el trailer necesita los totales de todos los detalles, y
  `Escritor.stream/3` lo dice con un `ArgumentError`.
- Controles agrupados: `agrupar_por: campo` en un control compara (o
  calcula) el trailer contra los registros con el mismo valor en ese
  campo, para los formatos con un trailer por moneda.
- Las sumas de los controles también sobre `AnchoFijo.Monto` de la misma
  moneda y sobre `Decimal`; antes un campo con `moneda:` no cuadraba nunca.
- Interoperar con `Decimal` sin tuplas: `como: :decimal` en un campo
  `:decimal` (o `decimales_como: :decimal` en el layout, para todos) lee un
  `%Decimal{}` con la escala del campo; requiere la librería y sin ella el
  layout es inválido con un diagnóstico que dice qué agregar. Al escribir,
  cualquier `:decimal` acepta un `%Decimal{}`, un entero en unidades
  enteras o un string numérico, y más decimales que `:precision` es un
  diagnóstico, nunca un redondeo. `Monto.desde_decimal/2` y `Monto.nuevo/3`
  con un `Decimal`. El job de CI "Como dependencia" prueba el camino sin
  `Decimal`.
- `encoding:` por campo (`:utf8` o `:latin1`, por encima del encoding del
  layout; solo con `unidad: :bytes`), para los archivos que mezclan: latin-1
  en todo salvo el texto libre en UTF-8. Al leer y al escribir.
- Advertencia `:doble_codificacion` cuando un `:texto` trae UTF-8
  decodificado como latin-1 y vuelto a codificar (`operaciÃ³n`), con el
  texto reparado; `reparar_doble_codificacion: true` en el campo aplica la
  reparación al leer. `Campo.leer/3` devuelve las advertencias del campo y
  `parsear/3` las trae en la tercera posición.
- `detectar/2`: `encoding_probable: :mixto` cuando hay bytes latin-1 y
  secuencias UTF-8 en el mismo archivo, con la declaración sugerida;
  `unidad_probable` (`:bytes` o `:caracteres`) según en qué unidad son
  consistentes los largos; `contrastar/2` reporta un layout que declara la
  unidad o el encoding equivocados.
- Un campo que empieza en medio de un carácter multibyte se diagnostica como
  tal (`:continuacion_suelta`): el campo anterior lo cortó, pruebe
  `unidad: :caracteres`; antes decía que el byte era latin-1.
- Más formatos de fecha y dos tipos nuevos. `:fecha` acepta `:mmddaaaa`,
  `:aammdd`, `:ddmmaa`, `:mmddaa`, `:aaaaddd` y `:aaddd` (julianos) además
  de `:aaaammdd` y `:ddmmaaaa`, y un patrón explícito de tokens con
  separadores (`"DD/MM/AAAA"`, `"AAAA-MM-DD"`) cuando ninguno calza. Los
  años de dos dígitos se expanden con `:pivote` (default `2000`). `:hora`
  lee `Time` (`:hhmmss`, `:hhmm`, `"HH:MM:SS"`) y `:fecha_hora` lee
  `NaiveDateTime` (`:aaaammddhhmmss`, `:aaaammddhhmm`, `:ddmmaaaahhmmss`,
  `:ddmmaaaahhmm`, `"AAAA-MM-DD HH:MM:SS"`), con la misma política de
  blancos y ceros que `:fecha`. Escritura simétrica para todos, y un año
  fuera de la ventana del pivote es un diagnóstico al escribir.
- Tipos `:constante` y `:relleno`: las posiciones cuyo valor lo pone el
  formato y no el dato. `[tipo: :constante, valor: "01"]` se verifica al
  leer (un literal distinto es un diagnóstico con `esperado` y `recibido`)
  y se escribe solo; `[tipo: :relleno]` no se lee ni aparece en el
  registro, se escribe con su carácter de `:relleno`, y al final de la
  línea es relleno reponible con `relleno_final: :tolerar`. Un valor en el
  mapa para un relleno, o un literal distinto para una constante, es un
  diagnóstico al escribir.
- `Multiregistro`: `discriminador: [campo: :tipo]` toma la posición, el
  largo y el valor de cada tipo del campo `:constante` con ese nombre; y
  con `[posicion:, largo:]`, `:valor` se puede omitir cuando el layout
  tiene una constante justo ahí.
- `Multiregistro` sin código de tipo: `discriminador: [por: :largo]` elige
  el tipo por el largo de la línea (dos tipos iguales son una definición
  inválida); `[por: :posicion_en_archivo]` por dónde está, con
  `ubicacion: :primera | :resto | :ultima` en cada tipo y una línea de
  anticipación en `stream/3`; `[por: fun]` con una función
  `(linea, numero) -> tipo | nil` para lo que no cabe en lo anterior.
- `detectar/2` acepta un `Multiregistro` en `layout:` (también
  `mix ancho_fijo.detectar --layout`): dice qué criterio discrimina,
  cuántas líneas son de cada tipo, cuántas no son de ninguno y cuántas no
  miden lo que su tipo declara, y el veredicto de ancho fijo es por tipo:
  tres largos de línea con un tipo cada uno es un archivo de ancho fijo.
- `detectar/2` con `layout:` cuenta en cuántas líneas de la muestra aparece
  cada literal declarado: la forma más barata de confirmar que un archivo
  es del formato que uno cree.
- Eventos de telemetría `[:ancho_fijo, :parsear, ...]` y
  `[:ancho_fijo, :stream, ...]` también con un `Multiregistro`, con las
  mismas medidas; en la metadata, `:layout` es el `:nombre` del
  multiregistro y `:encoding` y `:unidad` son `nil`. Los diagnósticos de
  cierre cuentan en `errores` pero no en `lineas`.
- `:nombre` en la definición de un `Multiregistro`; el formato NACHA se
  llama `"NACHA"`.
- `Formatos.Nacha.encabezado_de_archivo/0` declara la identidad del archivo:
  `immediate_origin`, `file_creation_date`, `file_creation_time` y
  `file_id_modifier`, los campos que la especificación define para
  distinguir archivos del mismo originador.
- Eventos de telemetría para la escritura: `[:ancho_fijo, :escribir, ...]`
  en `escribir/3` (`start`, `stop`, `exception`, con `lineas`, `registros`,
  `errores` y `advertencias` como `parsear`, más `:terminador` y
  `:truncar` en la metadata) y `[:ancho_fijo, :escribir_stream, ...]` en
  `Escritor.stream/3`, con el contrato de `stream`.

### Infraestructura

- El paquete de Hex excluye `priv/plts/`: con un PLT de dialyzer construido en
  local, el tarball pasaba el tope de 16 MB y `mix hex.build` fallaba. Incluye
  `SECURITY.md`, que hexdocs publica como "Seguridad", y la documentación ya no
  enlaza a archivos que hexdocs no tiene ni a módulos ocultos
  (`AnchoFijo.Reglas` pasa a estar documentado: es el struct de
  `campo.reglas`).
- Gobernanza para depender del paquete: `SECURITY.md` con el canal de reporte
  privado y los plazos, `CODEOWNERS`, Dependabot para las dependencias de
  desarrollo y las acciones de CI, `mix deps.audit` en la CI junto a
  `mix hex.audit`, y la sección "Mantenimiento, compatibilidad y soporte" del
  README: versiones de Elixir y OTP soportadas, qué es un cambio
  incompatible, cuánto se mantiene una serie y cómo se publica.

- Tests para los dos caminos de `Campo.formatear/3` que ningún test
  ejercitaba: un tipo propio con `escribir/2` (round-trip, sin
  `escribir/2`, que devuelve `{:error, causa}`, que devuelve un texto de
  otro ancho) y un `:decimal` con `moneda:` que escribe un `Monto` (round-
  trip, otra moneda, otra precisión, la tupla). La propiedad de round-trip
  genera también campos con `moneda:`. Los módulos de `test/support` no
  cuentan para la cobertura.

## [0.3.1] — 2026-10-20

### Corregido

- `:crypto` declarado en `extra_applications`: sin eso, un release que no
  arrastre `:ssl` deja afuera la aplicación y `huella/2` e `identidad/3`
  fallan con `UndefinedFunctionError` recién en producción. Como dependencia
  también compilaba con warning.
- `AnchoFijo.Telemetria` ya no deja un atributo sin usar cuando el proyecto
  que la compila no tiene `:telemetry`: era un warning en cada compilación
  ajena.
- El `ArgumentError` de `Monto.a_decimal/1` nombra el requisito real,
  `{:decimal, "~> 2.0 or ~> 3.0"}`.

### Infraestructura

- Job de CI "Como dependencia": un proyecto vacío con `{:ancho_fijo, path: ...}`
  y sin dependencias opcionales compila la librería y falla ante cualquier
  warning. Es lo que CI no veía: en el repo, las deps de dev y test tapan
  estos problemas.

## [0.3.0] — 2026-10-20

### Cambiado — rompe compatibilidad

- Una opción desconocida o con un valor de otro tipo en `parsear/3`,
  `stream/3` o `detectar/2` levanta `ArgumentError` que nombra la función y
  la opción. Antes `modo: :otro` devolvía un diagnóstico `:entrada` y las demás
  opciones mal formadas reventaban con `FunctionClauseError` desde adentro.
- `AnchoFijo.Layout.nuevo/1` y `AnchoFijo.Campo.nuevo/1` rechazan las claves
  que no existen (`enconding:`, `precison:`) con un diagnóstico `:layout`, en
  vez de ignorarlas. También rechazan `:nombre` que no sea binario y
  `:opcional` que no sea booleano.
- `detectar/2` con un `:layout` inválido devuelve `{:error, diagnosticos}`, como
  `parsear/3`; antes los diagnósticos del layout iban en `:observaciones`.

### Agregado

- `AnchoFijo.Formatos` con el catálogo de formatos reales y su vigencia, y
  `AnchoFijo.Formatos.Nacha`: el formato NACHA/ACH completo (seis tipos de
  registro más el relleno) como multiregistro, `validar/1` con los
  controles propios del formato (cuentas, entry hash, débitos y créditos
  por código de transacción, por lote y por archivo) y `lotes/1` con la
  estructura anidada. Fuente citada en el módulo. Fixture `nacha_ppd.txt`
  con datos inventados.
- `AnchoFijo.Multiregistro` acepta varios valores de discriminador por tipo
  (`valor: ["62", "63"]`) y `orden: :libre` para formatos con lotes que se
  repiten.
- `AnchoFijo.identidad/3` y `AnchoFijo.Identidad`: la identidad del lote
  desde lo que el archivo declara (`identidad: [campos: [...]]` en el
  layout, leído del primer registro), la huella y el nombre. `cotejar/2`
  contra las identidades ya vistas responde `:nueva`, `{:duplicada, _}` o
  `{:conflicto, diagnostico, _}`; `duplicada?/2`. Sin estado ni
  persistencia. Diagnóstico nuevo `:identidad`.
- `AnchoFijo.Multiregistro`: archivos con header, detalle y trailer. Un
  discriminador por posición, un layout por tipo con cantidad (`:uno`,
  `:opcional`, `:varios`, `:al_menos_uno`) y orden, y controles cruzados
  (`cuenta:` y `suma:`) del trailer contra los detalles. `parsear/3` y
  `stream/3` lo aceptan en lugar del layout; los registros vuelven como
  `{tipo, mapa}` en el orden del archivo y `agrupar/2` los junta por tipo.
  Diagnósticos nuevos `:estructura` y `:control`.
- Fixture `nomina_multiregistro.txt`.
- `AnchoFijo.escribir/3`: el inverso de `parsear/3`. Escribe registros con
  el layout, todo o nada, con todos los diagnósticos si algo no se puede
  escribir. `AnchoFijo.Escritor.stream/3` es la versión lazy y
  `AnchoFijo.Campo.formatear/3` el inverso de `extraer/3`. Opciones
  `:terminador` y `truncar: true` (solo `:texto`, con advertencia
  `:campo_truncado`). Respeta encoding, unidad, relleno, signo, separador
  y formato de fecha; el round-trip con `parsear/3` es una propiedad.
- `moneda: :clp` en campos `:decimal`: el valor es un `AnchoFijo.Monto`
  (unidades, precisión, moneda) y la precisión se toma de la escala ISO 4217
  de la moneda; declararla distinta es un layout inválido. Una moneda fuera
  de la tabla con `:precision` es una advertencia del layout; sin
  `:precision`, un error.
- `AnchoFijo.Monto`: `nuevo/2,3`, `cero/1`, `sumar/2`, `sumar!/2`, `restar/2`,
  `negar/1`, `total/1,2`, `formatear/2`, `a_decimal/1`, `escala/1`,
  `monedas/0`. Monedas distintas son un diagnóstico de tipo `:moneda`.
- `Decimal` como dependencia opcional, solo para `a_decimal/1`.
- Behaviour `AnchoFijo.Tipo` con `opciones/0`, `validar/1`, `leer/3` y el
  opcional `escribir/2`. Los cinco tipos internos son implementaciones
  (`AnchoFijo.Tipo.Texto`, `.Entero`, `.Decimal`, `.Fecha`, `.Rut`) y un
  layout acepta `tipo: MiApp.Hora` con un módulo propio; sus opciones quedan
  en `campo.opciones`. Un módulo que no existe o no implementa el behaviour
  es un diagnóstico `:layout`. `Tipo.diagnostico/3`, `Tipo.vacio/2` y
  `Tipo.falla/4` para que los diagnósticos propios sean indistinguibles.
- `AnchoFijo.Campo` tiene `:modulo` (el tipo resuelto) y `:opciones`, y
  `Campo.texto?/1`.
- Eventos de `:telemetry` bajo `[:ancho_fijo, ...]`: `parsear` y `detectar`
  con `start`/`stop`/`exception` vía `:telemetry.span/3`, y `stream` con
  `start`/`stop` contados en el acumulador. Medidas de `stop`: `duration`,
  `lineas`, `registros`, `errores`, `advertencias`. El contrato está en
  `AnchoFijo.Telemetria`. La dependencia es opcional
  (`{:telemetry, "~> 1.3", optional: true}`); sin ella no se emite nada.
- `traza: true` en `parsear/3` y `stream/3`: cada registro trae la clave
  reservada `:__traza__` con un `AnchoFijo.Traza` (línea, offset de byte,
  largo). `AnchoFijo.Traza.linea_original/2` recupera la línea desde el
  contenido. Un campo no se puede llamar `:__traza__`.
- `AnchoFijo.huella/2`: SHA-256 del lote con los terminadores normalizados a
  LF, calculado por bloques; `normalizar: false` para los bytes exactos.
- `sensible: true` en los campos del layout (`:rut` lo es por default). Los
  diagnósticos de un campo sensible muestran la forma del valor y no el valor
  en `Diagnostico.mensaje/1`, `reporte/1`, `to_string/1` e `inspect/1`;
  `mensaje/2` y `reporte/2` con `revelar: true` muestran el valor.
  `Diagnostico.forma/1` describe un valor sin revelarlo y
  `Diagnostico.marcar_sensible/2` marca un diagnóstico.
- `AnchoFijo.Diagnostico` tiene `:sensible` y `:redactado`.
- `mix ancho_fijo.detectar RUTA`: `detectar/2` desde la terminal, con
  `--lineas`, `--bytes`, `--layout RUTA.exs` y `--json`. Código de salida `0`
  si parece ancho fijo y concuerda con el layout, `1` si no, `2` si no se
  pudo leer el archivo, el layout o las opciones.
- `AnchoFijo.parsear!/3` y `AnchoFijo.detectar!/2`: devuelven el valor o
  levantan `AnchoFijo.Error`. En modo `:tolerante`, `parsear!/3` levanta con
  todos los errores del archivo; las advertencias no se devuelven.
- `AnchoFijo.Error` documentado como módulo propio, con el contrato de las dos
  formas de fallar: diagnóstico para los datos, `ArgumentError` para la llamada.
- `stream/3` reporta como diagnóstico `:entrada`, en su posición, un elemento
  del enumerable que no sea binario; antes era un `FunctionClauseError`.
- `Layout.nuevo/1` y `Campo.nuevo/1` devuelven un diagnóstico cuando el
  argumento no es una definición (un entero, una lista que no es keyword).

### Cambiado

- `decimal`, la dependencia opcional de `Monto.a_decimal/1`, acepta la serie 3.x
  (`~> 2.0 or ~> 3.0`): la 2.4.1 tiene dos avisos de seguridad (#43).
- `parsear/3` parte y numera las líneas de a una en vez de materializar la
  lista completa antes de procesar la primera: en modo `:estricto` sobre un
  archivo de 100 MB con la primera fila mala en la línea 1000, de 0,46 s y
  390 MB de heap a 0,02 s y nada medible.
- Conversión de campos sin regex (`solo_digitos?`, fechas en ceros) y
  validación UTF-8 con `String.valid?/1` por delante: una línea de cuatro
  campos pasa de 3,2 µs a 1,9 µs, y `stream/3` sobre 100 MB de 7,7 s a
  5,2 s.
- Una opción de campo que ningún tipo conoce (`precison: 2`) es un
  diagnóstico `:layout`, en vez de ignorarse.
- Un diagnóstico `:entrada` por un argumento que no es binario describe el
  tipo del argumento ("una lista de 3 elementos") en vez de imprimirlo.

### Infraestructura

- `mix hex.audit` corre en CI junto con formato, credo y dialyzer.
- `bench/generar.exs` y `bench/parseo.exs`: fixture grande, Benchee y un
  medidor de memoria pico por proceso. Resultados en `bench/README.md`.

- `mix prompts.verificar`: el registro de `prompts/` se verifica contra git
  (numeración, frontmatter, fecha y autor del commit que agregó cada archivo,
  secciones e índice), con `--corregir` para alinear el frontmatter. Corre
  como job propio en CI. No forma parte del paquete publicado.
- CI en GitHub Actions: la suite corre en Elixir 1.14, 1.16, 1.18 y 1.20 con
  warnings como errores; formato, credo, dialyzer (con el PLT en caché) y
  cobertura con umbral del 90 % corren en la versión más nueva.
- Publicación en Hex al empujar un tag `vX.Y.Z`, previa verificación de que
  el tag coincide con `mix.exs` y el CHANGELOG.

## [0.2.0] — 2026-10-16

### Cambiado — rompe compatibilidad

- `AnchoFijo.parsear/3` devuelve `{:ok, registros, diagnosticos}` también en modo
  `:estricto`, donde antes devolvía `{:ok, registros}`. Al llegar a `:ok` en
  estricto la lista solo puede traer advertencias: un error habría cortado.
- `AnchoFijo.stream/3` y `AnchoFijo.Parser.parsear_linea/3` emiten
  `{:ok, registro, advertencias}` donde antes emitían `{:ok, registro}`. Un
  `match?({:ok, _}, resultado)` en el código llamador pasa a ser
  `match?({:ok, _, _}, resultado)`.

### Agregado

- `AnchoFijo.Diagnostico` tiene `:gravedad`, `:error` (default) o
  `:advertencia`. Una advertencia es una fila que sí se pudo leer, pero
  asumiendo algo que quien procesa el archivo debería saber.
- `AnchoFijo.Diagnostico.separar/1` parte una lista en `{errores, advertencias}`,
  y `solo_advertencias?/1` responde si el lote se puede procesar tal cual.
- `relleno_final: :tolerar` en `AnchoFijo.Layout`. Una línea más corta que el
  largo declarado se completa con el carácter de relleno cuando lo que falta
  cae entero en relleno no declarado o en campos `:texto` finales, y queda una
  advertencia `:relleno_completado` que dice cuántas unidades se completaron.
  Si el faltante alcanza a un `:entero`, `:decimal` o `:fecha`, sigue siendo un
  error de largo. El default `:estricto` no cambia nada.
- `signo: :final` en campos `:entero` y `:decimal`, para los formatos heredados
  de mainframe que escriben `0125000-`. El default `:inicial` no cambia. Un
  signo en el extremo que el layout no declara produce un diagnóstico que dice
  qué declarar, en vez de "caracteres no numéricos".
- Tipo `:rut` en `AnchoFijo.Campo`, que normaliza las variantes de presentación
  (puntos, guion, ceros a la izquierda, `k` o `K`) a `"12345678-5"` y valida el
  dígito verificador por módulo 11. `dv: :no_validar` y `dv: :ausente` son las
  salidas explícitas. `AnchoFijo.Rut` expone `normalizar/2`, `valido?/1` y
  `digito_verificador/1`.

## [0.1.0] — 2026-08-06

Primera versión. Solo lectura.

### Agregado

- `AnchoFijo.detectar/2`: interroga una muestra —binario o ruta— y devuelve un
  reporte con los largos de línea y su consistencia, el encoding probable
  (`:ascii`, `:utf8`, `:latin1`), los terminadores de línea, si la última línea
  trae terminador, y el análisis de delimitadores frecuentes (`;`, `,`, tab, `|`)
  que sugieran que el archivo no es de ancho fijo.
- `AnchoFijo.Detector.contrastar/2`: compara un reporte con un layout y devuelve
  los desacuerdos como diagnósticos, sin parsear el archivo.
- `AnchoFijo.parsear/3`: modo `:estricto` (corta en la primera línea con
  problemas) y modo `:tolerante` (devuelve las filas buenas y los diagnósticos de
  las malas por separado).
- `AnchoFijo.stream/3`: versión lazy, sobre un binario, una ruta o un
  `File.Stream` construido por el llamador.
- `AnchoFijo.Layout`: definición del formato como data, con validación de la
  definición misma. Los campos solapados, los nombres duplicados y un largo total
  declarado insuficiente son errores; los huecos y el relleno final son
  advertencias en `layout.advertencias`.
- `AnchoFijo.Campo`: tipos `:texto`, `:entero`, `:decimal` (con `:precision`
  obligatoria y `:separador` implícito, punto o coma) y `:fecha` (con `:formato`
  obligatorio, `:aaaammdd` o `:ddmmaaaa`). Opciones de limpieza `:trim`,
  `:relleno` y `:opcional`.
- `AnchoFijo.Diagnostico`: struct de error con línea, campo, rango de posiciones,
  qué se esperaba, qué llegó y una causa probable. `mensaje/1` lo redacta en una
  línea de español y `reporte/1` una lista completa.
- `AnchoFijo.Transcodificacion`: latin-1 a UTF-8 declarado en el layout, con
  diagnóstico del byte exacto cuando falla en vez de excepción. Detecta el rango
  0x80–0x9F y señala Windows-1252.
- `unidad: :bytes | :caracteres` en el layout, para archivos UTF-8 cuyo emisor
  contó caracteres en vez de bytes.

### Notas de diseño

- Los montos nunca pasan por punto flotante: un `:decimal` se devuelve como
  `{unidades, precision}`.
- Las posiciones son 1-based, como en las especificaciones bancarias.
- Cero dependencias de runtime.

## Candidatos

Ninguno de estos está implementado. Quedan anotados como lo que sigue:

- **Previred (Chile)** como formato incluido, con vigencia y fuente, como
  NACHA. Es el que convierte "un parser genérico" en "sabe leer lo que
  necesito" para el mercado al que apunta la librería.
- **Más encodings.** cp1252 (cuya señal `detectar/2` ya reconoce) y las
  variantes de EBCDIC que aparecen en integraciones con sistemas antiguos.
- **Escritura lazy de un multiregistro.** `Escritor.stream/3` lo rechaza
  porque el trailer necesita los totales; una primera pasada que acumule
  cuentas y sumas lo permitiría en memoria constante.
- **Una fachada en inglés** (`fixed_width`) como paquete hermano, cuando haya
  un proyecto que la necesite. El criterio está en el README.
