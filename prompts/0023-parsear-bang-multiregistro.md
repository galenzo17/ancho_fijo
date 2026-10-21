---
prompt: 0023
fecha: 2026-10-21T10:00:00-03:00
autor: Agustín Bereciartúa <bereciartua.agustin@gmail.com>
modelo: claude-fable-5-1
issue: 37
---

# 0023 — `parsear!/3` con un Multiregistro (issue #37)

**Contexto:** con la 0.3.1 publicada quedaban 22 issues abiertas, las seis
primeras (#37 a #42) de la revisión del código integrado en la serie de
PRs encadenados. El prompt pidió recorrerlas en un loop, una por PR; este
es el primero de la cadena, y los que siguen parten de esta rama.

## Prompt

> anda a main y revisa luego las issues, arma un /loop cada issue un pr si
> es necesario, senior level ultra mega pro ultrathink

## Resultado

- `AnchoFijo.parsear!/3` despacha por `%Multiregistro{}` como ya hacían
  `parsear/3` y `stream/3`, con el `@spec` que lo admite.
- `AnchoFijo.Multiregistro.parsear!/3`, simétrico a `Parser.parsear!/3`:
  devuelve los `{tipo, mapa}` o levanta `AnchoFijo.Error` con los
  diagnósticos reales; en `:tolerante`, con todos los errores (de línea, de
  estructura y de control) y sin las advertencias.
- Tests con la fixture NACHA y con la nómina multiregistro: el camino feliz
  por las dos fachadas, un trailer que falta, un detalle roto en tolerante
  (que trae además los dos controles que dejan de cuadrar), y advertencias
  que no levantan.
- Un diagnóstico `:estructura` sin línea decía `entrada:` en su mensaje.

## Decisiones tomadas

1. **Una función nueva en `Multiregistro` y no un `case` en la fachada.**
   La fachada solo despacha; la lógica del `!` (separar errores de
   advertencias, levantar con los errores) vive junto a `parsear/3` para
   que `Multiregistro` sea usable sin pasar por `AnchoFijo`, como `Parser`.
2. **El prefijo `estructura:` en vez de `entrada:`.** Al escribir el doctest
   apareció que `Diagnostico.mensaje/2` pone `entrada:` a cualquier
   diagnóstico sin línea ni campo, y un `:estructura` de cierre (falta el
   trailer) no es un problema de entrada. Es un cambio de un mensaje, en el
   caso que este PR hace visible por primera vez desde una excepción, y va
   acá y no en una issue aparte por eso.
3. **Los PRs de este loop se encadenan.** Cada rama parte de la anterior,
   como en la serie #25 a #35: abrirlos todos desde `main` garantiza
   conflictos en `CHANGELOG.md`, `prompts/README.md` y la numeración.
