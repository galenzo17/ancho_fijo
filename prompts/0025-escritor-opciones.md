---
prompt: 0025
fecha: 2026-10-21T19:00:00-03:00
autor: Agustín Bereciartúa <bereciartua.agustin@gmail.com>
modelo: claude-fable-5-1
issue: 39
---

# 0025 — Escritor: opciones validadas y telemetría (issue #39)

**Contexto:** tercera iteración del loop sobre las issues abiertas; la rama
parte de la de #38 (prompt 0024). `escribir/3` quedó fuera del contrato de
opciones de #16: `terminador: :lf2` era un `KeyError` desde adentro de
`Map.fetch!/2` y `truncarr: true` pasaba en silencio sin truncar nada.

## Prompt

> anda a main y revisa luego las issues, arma un /loop cada issue un pr si
> es necesario, senior level ultra mega pro ultrathink

## Resultado

- `Opciones.validar!/3` en `escribir/3` (`"AnchoFijo.escribir/3"`) y en
  `Escritor.stream/3` (`"AnchoFijo.Escritor.stream/3"`), con `:terminador`
  validado contra el mapa de terminadores y `:truncar` booleano.
- `[:ancho_fijo, :escribir, :start | :stop | :exception]` con
  `Telemetria.span/3`, las mismas cinco medidas que `parsear`, y
  `:terminador` y `:truncar` en la metadata; `[:ancho_fijo,
  :escribir_stream, :start | :stop]` en la versión lazy, con
  `instrumentar_stream/3` parametrizado por nombre de evento.
- Tests en `escritor_test`, `superficie_test` y `telemetria_test`.

## Decisiones tomadas

1. **La versión lazy también emite, con su propio nombre.** La issue pedía
   eventos para `escribir/3`. `Parser` distingue `parsear` de `stream`
   porque un stream no tiene función que envolver y se cuenta al cortarse;
   `escribir_stream` sigue la misma convención en vez de reutilizar
   `escribir` con una bandera en la metadata.
2. **Las medidas de la escritura tienen su propia función y no reutilizan
   `medir_parseo/2`.** La forma del resultado es otra (`{:ok, binario,
   advertencias}`, no una lista de registros), y en `{:error, _}` los
   registros escritos son cero por diseño: todo o nada.
3. **`lineas` cuenta los registros que se intentaron escribir**, incluidos
   los que no eran un mapa. Es el equivalente de las líneas leídas en
   `parsear`: lo que entró, no lo que salió.
