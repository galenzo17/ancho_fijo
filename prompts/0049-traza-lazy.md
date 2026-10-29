---
prompt: 0049
fecha: 2026-10-29T10:27:28-03:00
autor: Agustín Bereciartúa <bereciartua.agustin@gmail.com>
modelo: claude-fable-5-1
issue: 96
---

# 0049 — `traza: true` ya no materializa todas las líneas en `parsear/3` (issue #96)

**Contexto:** séptima iteración del segundo loop. `Parser.numerar/2` con
traza usaba `Entrada.dividir_con_terminador/1` (`Regex.split/3` con
capturas, `Enum.chunk_every/2`, `Enum.map_reduce/3`): una lista con todas
las líneas y sus trazas antes de leer la primera. La 0.3.0 había vendido
el camino lazy en el CHANGELOG (estricto con la primera fila mala: de
0,46 s y 390 MB a 0,02 s y nada medible), y con `traza: true` se perdía.
`Multiregistro.parsear/3` numera con la misma función.

## Prompt

> revisa si hay pr que mergear y luego issues por cerrar arma un /loop
> merge y sigu y luego otro, si salen issues crealas, y luego otro
> verification loop pr revie merge y asi sucesivo senior level

## Resultado

- `Entrada.dividir_lazy_con_offset/1`: el mismo `Stream.unfold/2` sobre
  `:binary.match/3` que `dividir_lazy/1`, entregando `{linea, offset}`;
  `dividir_lazy/1` es ese stream sin el offset. Cada pieza sigue siendo un
  sub-binario sin copia, y la pieza final después del último terminador es
  `""`, como en `dividir/1`.
- `Parser.numerar/2` con traza: ese stream, `Stream.with_index/2` y la
  traza con número, offset y `byte_size/1` de la línea. Sin traza, igual
  que antes. `dividir_con_terminador/1` queda para `partir_completas/1`,
  que trabaja sobre bloques, y para `lineas_con_terminador/2`.
- Tests en `traza_test.exs`: `numerar/2` con traza no es una lista y da
  exactamente las mismas trazas que la versión materializada (reescrita en
  el test como referencia) para LF, CRLF, CR, sin terminador final,
  mezclados, vacío, solo terminadores y líneas vacías; y en estricto con la
  primera línea mala sobre 100.000 líneas, las reducciones del proceso son
  menos del 1 % de las de leerlas todas.
- `bench/README.md`: medición antes y después sobre 500.000 líneas (24 MB)
  con la primera fila mala: de 700–820 ms y 210–280 MB de heap a menos de
  10 ms y ~5 KB.

## Decisiones tomadas

1. La laziness se verifica con reducciones del proceso, no con tiempo ni
   con `heap_size`: las reducciones cuentan trabajo y no dependen de la
   máquina ni de cuándo corra el GC.
2. El offset viaja en el acumulador del `unfold` que ya existía, en vez de
   duplicar el recorrido en el parser: `dividir_lazy/1` y la traza no
   pueden discrepar sobre dónde empieza una línea.
