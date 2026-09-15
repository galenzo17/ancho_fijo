---
prompt: 0007
fecha: 2026-09-15T18:52:40-03:00
autor: Agustin Bereciartua <bereciartua.agustin@gmail.com>
modelo: claude-fable-5-1
issue: 5
---

# 0007 — Tipo `:rut` con validación de dígito verificador (issue #5)

**Fecha:** 2026-09-15
**Contexto:** tercera issue del plan de práctica, después de `0005` y `0006`.
Las nóminas bancarias chilenas traen RUT en casi todos los registros, y un
RUT con el DV malo es el error silencioso típico: el archivo parsea y el
banco lo rechaza días después.

## Prompt

El mismo `/loop` que gobierna toda la serie, sin prompt nuevo para esta issue:

> y cada una un pr, bien explicado, bien paso a paso, la meta es entender
> aprender a full, respeta guardar los promp de cada issues, senior level

## Resultado

- Módulo público `AnchoFijo.Rut` con `normalizar/2`, `valido?/1`,
  `digito_verificador/1` y `modos/0`, documentado y con doctests.
- Tipo `:rut` en `AnchoFijo.Campo`, con la opción `dv: :validar` (default),
  `:no_validar` o `:ausente`. Valor canónico `"12345678-5"`; con `:ausente`,
  `"12345678"`.
- Dos diagnósticos: DV que no cuadra (dice cuál correspondía) y formato que
  no es un RUT (dice qué se esperaba). Tipo `:campo_invalido` como el resto.
- Generador `rut_valido/0` en `test/support/generadores.ex`, con las cinco
  presentaciones que llegan en archivos reales, y `:rut` entra al generador
  de campos: las cinco propiedades de round-trip lo cubren.
- Dos propiedades nuevas: toda representación normaliza al canónico, y
  cambiar el DV siempre se detecta.
- Tabla de respuestas conocidas en `rut_test.exs`.
- Fila en la tabla de tipos del README, párrafo con la decisión, CHANGELOG, y
  `AnchoFijo.Rut` en el grupo "Definición del formato" de hexdocs.
- Suite: 248 verdes, credo estricto y dialyzer limpios.

## Decisiones tomadas

1. **El módulo 11 lo escribió el modelo.** Como en `0005` y `0006`: el
   `TODO(human)` quedó sin respuesta en la ventana del loop. El andamiaje se
   había verificado antes con una implementación temporal, así que los 22
   tests rojos que quedaban dependían solo de esa función.

2. **La validación es parte del tipo, con dos salidas explícitas.** La issue
   preguntaba si validar era parte del tipo o una opción. Se eligió que el
   default valide, porque el DV malo es exactamente el error que la librería
   existe para impedir, y que las excepciones se declaren: `:no_validar` para
   el campo que trae DV pero cuyo emisor no lo garantiza, `:ausente` para el
   formato que trae solo el cuerpo. Son dos situaciones distintas y un
   booleano `validar_dv: false` las habría mezclado.

3. **El valor es un `String.t()` canónico, no un struct.** `"12345678-5"` es
   lo que se compara, se loguea y se manda al banco. Un struct obligaría a
   todos los consumidores a desarmarlo para lo más común.

4. **Qué se tolera al leer.** Puntos, guion opcional, ceros a la izquierda,
   espacios en los bordes, `k` minúscula. No se tolera: letras que no sean K,
   un guion sin DV, el cuerpo en cero. Con `:ausente`, un DV pegado al cuerpo
   es error de formato: si el layout dice que no hay DV y hay uno, el layout
   está mal o el campo está corrido.

5. **El generador usa la misma función que el parser, y por eso hay tabla.**
   El round-trip solo prueba consistencia: una implementación equivocada del
   módulo 11 se validaría a sí misma. Los casos de tabla de `rut_test.exs`,
   incluidos el que da K, el que da 0 y uno de nueve dígitos que obliga a la
   serie a dar la vuelta, son los que anclan la corrección.

6. **`Rut.modos/0` es público** para que `Campo` valide la opción sin
   duplicar la lista. Costó una función pública más; la alternativa era un
   atributo repetido en dos módulos.
