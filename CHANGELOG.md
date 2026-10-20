# Changelog

Este proyecto sigue [Versionado Semántico](https://semver.org/lang/es/).

## [No publicado]

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

- Un diagnóstico `:entrada` por un argumento que no es binario describe el
  tipo del argumento ("una lista de 3 elementos") en vez de imprimirlo.

### Infraestructura

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
