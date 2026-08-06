# 0001 — Creación inicial de la librería

**Fecha:** 2026-08-06
**Contexto:** repositorio vacío. Origen de la versión `0.1.0`.

## Prompt

> Crea desde cero una librería Elixir llamada "ancho_fijo", pensada para
> publicarse en Hex.
>
> **CONTEXTO DE NEGOCIO**
> En integraciones bancarias y de ERPs abundan los archivos de ancho fijo:
> cartolas, nóminas de pago, respuestas de bancos. El problema recurrente no
> es parsearlos, es que el archivo real nunca calza con el formato que el
> cliente declaró: llega con otro encoding, otro largo de línea, o resulta
> ser delimitado. Esta librería existe para detectar eso el día uno del
> proyecto, no después del desarrollo.
>
> **PRINCIPIOS DE DISEÑO**
> 1. El layout es data, no código. Se define con structs/mapas: campos con
>    nombre, posición, largo, tipo y opciones de limpieza (trim, padding,
>    relleno con ceros). Cambiar de formato es cambiar la definición.
> 2. Los errores diagnostican, nunca solo fallan. Prohibido `{:error, :invalid}`.
>    Cada error dice línea, qué se esperaba, qué llegó y una causa probable.
>    Ejemplo del tono: "línea 42: se esperaban 120 caracteres, llegaron 118;
>    posible campo faltante o archivo delimitado".
> 3. Antes de parsear, se puede interrogar el archivo.
>
> **API PÚBLICA (superficie mínima)**
> - `AnchoFijo.detectar/2` — recibe una muestra (binario o path) y devuelve un
>   diagnóstico: largos de línea encontrados y su consistencia, encoding
>   probable (latin-1 vs UTF-8), presencia de delimitadores frecuentes que
>   sugieran que NO es ancho fijo, terminadores de línea. Es la respuesta a
>   "¿esto es realmente lo que me dijeron que es?".
> - `AnchoFijo.parsear/3` — layout + input, devuelve `{:ok, registros}` o
>   `{:error, diagnosticos}`. Modo estricto (corta al primer error) y modo
>   tolerante (acumula errores y devuelve las filas buenas aparte).
> - `AnchoFijo.stream/3` — igual pero lazy sobre `File.stream!/2`, para archivos
>   grandes sin cargarlos en memoria.
> - `AnchoFijo.Layout` — struct de definición, con validación de la definición
>   misma (campos solapados, huecos, largo total inconsistente).
>
> **TIPOS DE CAMPO**
> `:texto`, `:entero`, `:decimal` (con precisión declarada, para montos),
> `:fecha` (con formato AAAAMMDD y DDMMAAAA). Los montos jamás pasan por
> float; usar enteros con escala declarada.
>
> **ENCODING**
> Soporte explícito de latin-1 con transcodificación a UTF-8, declarado en
> el layout. Bytes inválidos generan diagnóstico, no crash.
>
> **ESTRUCTURA**
> ```
> ancho_fijo/
>   lib/
>     ancho_fijo.ex            API pública y moduledoc principal
>     ancho_fijo/
>       layout.ex
>       campo.ex
>       detector.ex
>       parser.ex
>       diagnostico.ex         struct de error con línea, esperado, recibido, causa
>       transcodificacion.ex
>   test/
>   README.md
>   CHANGELOG.md
>   LICENSE (MIT)
> ```
>
> **CALIDAD (esto no es negociable)**
> - Doctests en toda la API pública, con ejemplos `iex>` reales que corren.
> - `@spec` en todas las funciones públicas; dialyzer limpio.
> - Credo estricto limpio.
> - Un property test con StreamData: generar layouts y registros válidos al
>   azar, serializar a línea de ancho fijo, parsear de vuelta, y verificar
>   round-trip. Otro property: mutar una línea válida (acortar, cambiar un
>   byte de encoding) y verificar que el diagnóstico detecta la mutación.
> - Fixtures en `test/fixtures`: un archivo correcto, uno en latin-1, uno con
>   una fila corta, uno que en realidad es CSV, uno con línea final sin
>   terminador.
>
> **COMENTARIOS**
> Sin comentarios de sintaxis. Sí bloques cortos de lógica de negocio donde
> haya una decisión de dominio, explicando el porqué. Ejemplo del tono:
> "el modo tolerante existe porque en producción una nómina de 10.000 filas
> con 3 malas debe reportar las 3, no botar el lote completo".
>
> **MIX.EXS Y PUBLICACIÓN**
> - version "0.1.0"
> - Bloque package completo: description en inglés de una línea, licenses
>   MIT, links a GitHub.
> - `ex_doc` como dependencia de dev; `@moduledoc` principal escrito como la
>   portada de hexdocs: el problema primero, el ejemplo de uso en las
>   primeras líneas.
> - README en español, abre con la anécdota del problema (el formato
>   declarado vs el formato real) y el ejemplo de `detectar/2` antes que el
>   de `parsear/3`. Sección final "decisiones y trade-offs".
>
> **ALCANCE**
> No agregues: escritura/serialización de archivos (solo lectura en 0.1),
> soporte de multiregistro (header/detalle/trailer) — déjalo anotado en el
> CHANGELOG como candidato a 0.2. Mantén el paquete chico y terminado.
>
> Empieza por `diagnostico.ex` y `layout.ex`, después `detector.ex`, y el parser
> al final. El detector es el corazón del paquete, no el parser.

## Resultado

Versión `0.1.0` completa: `AnchoFijo`, `Layout`, `Campo`, `Detector`, `Parser`,
`Diagnostico`, `Transcodificacion`, `Entrada` (interno). Tests unitarios,
doctests, dos property tests con StreamData y cinco fixtures.

## Decisiones tomadas

Cosas que el prompt no zanjaba y hubo que resolver:

1. **Representación de `:decimal`.** Se devuelve `{unidades, precision}` —por
   ejemplo `{123456, 2}` para `1234.56`— en vez de depender de la librería
   `Decimal`. Cumple "los montos jamás pasan por float" sin sumar una
   dependencia a un paquete que se vende como chico y terminado.

2. **Retorno del modo tolerante.** El prompt pedía `{:ok, registros}` o
   `{:error, diagnosticos}`. Pero un lote con 3 filas malas de 10.000 no es un
   error: es un éxito parcial. El modo tolerante devuelve
   `{:ok, registros, diagnosticos}` y `{:error, _}` queda reservado para fallas
   globales (layout inválido, archivo ilegible).

3. **Bytes vs caracteres.** Las posiciones se cuentan en bytes por default,
   porque un formato de ancho fijo se define sobre el archivo físico. Se agregó
   `unidad: :caracteres` para el caso de un UTF-8 cuyo emisor contó caracteres.

4. **Huecos: advertencia, no error.** El prompt los listaba junto a los
   solapamientos, pero un hueco suele ser zona reservada legítima del formato,
   mientras que un solapamiento es siempre un error de transcripción. Los huecos
   quedan en `layout.advertencias` y no impiden parsear.

5. **Un módulo interno extra.** Se agregó `AnchoFijo.Entrada`
   (`@moduledoc false`) fuera del árbol declarado, porque `detectar/2`,
   `parsear/3` y `stream/3` comparten la misma decisión de "¿esto es una ruta o
   es contenido?" y duplicarla en tres lugares era peor.

6. **Rechazo de caracteres de control.** Ambos encodings rechazan 0x00–0x1F
   (menos tab) y 0x7F–0x9F. El rango 0x80–0x9F es control en latin-1 pero trae
   comillas en Windows-1252: encontrarlo es la señal más confiable de que el
   archivo es cp1252 y no latin-1, y el diagnóstico lo dice.

7. **`:formato` de fecha sin default.** Adivinar si `01022024` es el 1 de
   febrero o el 2 de enero es exactamente el error silencioso que la librería
   existe para impedir. Un campo `:fecha` sin `:formato` es un layout inválido.
