# Changelog

Este proyecto sigue [Versionado Semántico](https://semver.org/lang/es/).

## [No publicado]

### Corregido

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

## Candidatos a 0.2

Ninguno de estos está implementado. Quedan anotados como lo que sigue:

- **Multiregistro (header / detalle / trailer).** Un layout por tipo de registro,
  discriminado por el contenido de un campo —típicamente las primeras una o dos
  posiciones— y validación cruzada del trailer contra los detalles (cantidad de
  registros y suma de montos). Es la funcionalidad que más piden las cartolas
  bancarias reales y la razón principal de que exista una 0.2.
- **Escritura y serialización.** Generar archivos de ancho fijo desde el mismo
  layout que los lee. Requiere decidir el comportamiento cuando un valor no cabe
  en el campo: truncar, fallar o rellenar.
- **Más encodings.** cp1252 y las variantes de EBCDIC que aparecen en
  integraciones con sistemas antiguos.
