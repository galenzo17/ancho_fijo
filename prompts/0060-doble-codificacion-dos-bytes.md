---
prompt: 0060
fecha: 2026-10-30T00:00:00-03:00
autor: Agustín Bereciartúa <bereciartua.agustin@gmail.com>
modelo: claude-fable-5-1
issue: 114
---

# 0060 — La doble codificación exige secuencias de dos bytes (issue #114)

**Contexto:** la issue la abrió el propio loop, en la iteración de #95: la
propiedad de round-trip de rellenos de #94 falló en CI con `"é··"` y en
local con `"ñ···"`, porque `doble_codificacion/1` daba por doble codificado
cualquier texto que, reinterpretado como latin-1, fuera UTF-8 válido con
algún multibyte. `ñ` es `0xF1`, un inicio de cuatro bytes, y `·` es `0xB7`,
una continuación: `F1 B7 B7 B7` es un ideograma válido. La propiedad se
había aflojado mientras tanto.

## Prompt

> revisa si hay pr que mergear y luego issues por cerrar arma un /loop
> merge y sigu y luego otro, si salen issues crealas, y luego otro
> verification loop pr revie merge y asi sucesivo senior level

## Resultado

- `reinterpretar/1` exige además que los bytes reinterpretados no tengan
  ningún inicio de tres o cuatro bytes (`>= 0xE0`): un texto latino
  decodificado como latin-1 y vuelto a codificar es siempre `Ã`/`Â`/`Ä`…
  seguido de una continuación, secuencias de dos bytes. La doc lo explica
  con el ejemplo y hay doctest.
- Tests: `"Ã±andÃº"` se repara; `"ñ···"`, `"é··"` y `"Año·2024"` son `:no`.
  La propiedad de rellenos de #94 vuelve a exigir cero advertencias.

## Decisiones tomadas

1. Se restringe por forma de la secuencia y no por una lista de pares
   (`Ã©`, `Ã±`): la lista sería incompleta y la forma es exacta. Lo que se
   pierde es la doble codificación de caracteres de tres bytes (`€`, `—`),
   que de todos modos no se detectaba: su reinterpretación trae un byte de
   control que el campo rechaza antes.
