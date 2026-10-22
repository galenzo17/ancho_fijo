---
prompt: 0041
fecha: 2026-10-21T21:50:00-03:00
autor: Agustín Bereciartúa <bereciartua.agustin@gmail.com>
modelo: claude-fable-5-1
issue: 62
---

# 0041 — Bytes frente a grafemas al escribir (issue #62)

**Contexto:** decimonovena iteración del loop sobre las issues abiertas; la
rama parte de la de #61 (prompt 0040). La lectura mide en la unidad del
layout desde el principio y la escritura también, pero no estaba probado de
forma sistemática ni dicho en el README, y al revisarlo apareció un caso
real que sí corría columnas: un relleno de dos bytes en un layout medido en
bytes.

## Prompt

> anda a main y revisa luego las issues, arma un /loop cada issue un pr si
> es necesario, senior level ultra mega pro ultrathink

## Resultado

- Suite `escritura_en_bytes_test.exs`: caracteres de uno, dos, tres y
  cuatro bytes en `:bytes` con UTF-8, en `:caracteres` y en latin-1, con y
  sin `truncar:`, con `trim: false`, con encoding por campo y con signo al
  final; cada test mide la línea en la unidad del layout. Una propiedad
  escribe textos al azar con tildes, ñ, `·`, `€` y emojis en las tres
  configuraciones y verifica el largo exacto, que la línea sea válida en su
  encoding y que se vuelva a leer.
- Corregido: un `:relleno` de más de un byte (`"·"`) en un layout en bytes
  UTF-8 se repetía tantas veces como bytes faltaban y el campo quedaba más
  ancho. Ahora `Campo.completar` mide el relleno en la unidad y, si no mide
  una posición, es un error de tipo `:layout` al escribir (texto, constante
  y relleno); `Layout.nuevo/1` lo deja en `advertencias`, que es cuando
  todavía se puede cambiar.
- Los diagnósticos de "no cabe" y de `truncar: true` dicen las dos medidas
  cuando difieren: "5 posiciones en 4 (5 bytes, 4 caracteres)". Con solo
  ASCII el mensaje no cambia.
- Sección "Bytes o caracteres, también al escribir" en el README, al lado de
  la de escritura, con los tres casos y el del relleno.

## Decisiones tomadas

- El relleno ancho es una advertencia del layout y un error al escribir, no
  un error del layout: hay layouts de solo lectura que hoy funcionan con un
  relleno así (el parser ya sabe que no lo repone) y romperlos al construir
  el layout sería castigar a quien no escribe.
- El error se reporta en el campo y en el momento en que de verdad no se
  puede cumplir el largo: si el valor ocupa todo el campo, no hay nada que
  completar y se escribe igual.
- Las dos medidas se agregan al mensaje existente entre paréntesis en vez de
  cambiarlo: los mensajes con ASCII, que son los que la gente ya tiene en
  tests, quedan iguales.
