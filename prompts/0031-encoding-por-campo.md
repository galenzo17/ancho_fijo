---
prompt: 0031
fecha: 2026-10-21T23:00:00-03:00
autor: Agustín Bereciartúa <bereciartua.agustin@gmail.com>
modelo: claude-fable-5-1
issue: 51
---

# 0031 — Encodings mezclados por campo y doble codificación (issue #51)

**Contexto:** novena iteración del loop sobre las issues abiertas; la rama
parte de la de #50 (prompt 0030). El encoding era una propiedad del
archivo entero, y las respuestas de los bancos lo contradicen: latin-1 y
offsets en bytes en todo, UTF-8 en el campo de texto libre.

## Prompt

> anda a main y revisa luego las issues, arma un /loop cada issue un pr si
> es necesario, senior level ultra mega pro ultrathink

## Resultado

- `encoding:` por campo, aplicado al leer (`Campo.leer/3`) y al escribir
  (`Campo.formatear/3`); el layout lo rechaza con `unidad: :caracteres`.
- `Transcodificacion.doble_codificacion/1` con una prueba exacta (el texto
  reinterpretado como latin-1 es UTF-8 válido con multibyte), y la
  advertencia `:doble_codificacion` en los `:texto`, con el texto reparado
  en `esperado` (o en `contenido`, redactado, si el campo es sensible);
  `reparar_doble_codificacion: true` aplica la reparación.
- `Campo.leer/3` nuevo, con advertencias; `extraer/3` sigue igual. El
  parser suma las advertencias de los campos a las de la línea.
- `Transcodificacion.multibyte_utf8?/1` y el motivo `:continuacion_suelta`
  con su causa ("el campo anterior lo cortó; pruebe unidad: :caracteres").
- Detector: `encoding_probable: :mixto`, `unidad_probable`, la sugerencia
  en la observación, y `contrastar/2` por encoding mezclado y por unidad.
- Fixture `respuesta_mixta.txt` (latin-1 en el nombre, UTF-8 en el
  mensaje, 56 bytes por línea) con `Fixtures.layout_respuesta_mixta/1`:
  parsea legible, se escribe byte a byte, y la tarea lo sugiere.

## Decisiones tomadas

1. **La doble codificación se prueba, no se adivina.** Una lista de pares
   sospechosos (`Ã©`, `Ã±`) da falsos positivos y se queda corta; la
   prueba exacta es reinterpretar el texto como bytes latin-1 y ver si es
   UTF-8 válido con al menos un carácter multibyte. `JOSÉ` no lo es.
2. **Es una advertencia, no un error, y el valor queda como vino.** El
   registro se lee; la reparación es una decisión del formato
   (`reparar_doble_codificacion: true`) o, mejor, `encoding: :utf8` en el
   campo, que es la causa de fondo.
3. **`Campo.leer/3` en vez de cambiar `extraer/3`.** `extraer/3` es
   público y tiene doctests; agregar advertencias a su resultado rompía a
   quien lo usa. `leer/3` las trae y `extraer/3` las descarta.
4. **`unidad_probable` y `:mixto` son campos nuevos del reporte**, no
   valores escondidos en una observación: quien lee el reporte como JSON
   los necesita como datos.
5. **El texto reparado de un campo sensible no va en `esperado`.** Es el
   dato; va en `contenido`, que la redacción oculta.
