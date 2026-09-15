# Changelog

Este proyecto sigue [Versionado Semántico](https://semver.org/lang/es/).

## [No publicado]

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
- **Relleno faltante tolerado.** Archivos donde el emisor recorta los espacios
  finales y la última línea llega corta. Hoy es un diagnóstico de largo; podría
  ser una opción de layout que complete la línea y lo registre como advertencia.
- **Signo al final del campo.** El `123-` de los formatos heredados de mainframe.
- **Más encodings.** cp1252 y las variantes de EBCDIC que aparecen en
  integraciones con sistemas antiguos.
