---
prompt: 0029
fecha: 2026-10-21T18:52:15-03:00
autor: Agustín Bereciartúa <bereciartua.agustin@gmail.com>
modelo: claude-fable-5-1
issue: 49
---

# 0029 — Fechas y horas: más formatos, `:hora` y `:fecha_hora` (issue #49)

**Contexto:** séptima iteración del loop sobre las issues abiertas; la rama
parte de la de #48 (prompt 0028). `:fecha` aceptaba solo `:aaaammdd` y
`:ddmmaaaa`; cada otro formato bancario (año de dos dígitos, orden
estadounidense, juliano, con hora, con separadores) obligaba a un tipo
propio.

## Prompt

> anda a main y revisa luego las issues, arma un /loop cada issue un pr si
> es necesario, senior level ultra mega pro ultrathink

## Resultado

- `AnchoFijo.Tipo.Patron` (sin doc): compila un formato con nombre o un
  patrón de tokens (`AAAA`, `AA`, `MM`, `DD`, `DDD`, `HH`, `SS`, literales)
  a piezas, y lee y escribe las partes. `MM` después de `HH` es minuto.
- `:fecha` con ocho formatos con nombre y patrones explícitos; `:pivote`
  para años de dos dígitos. `:hora` (`Time`) y `:fecha_hora`
  (`NaiveDateTime`) nuevos, con `escribir/2` implementado en los tres
  módulos y `Campo.formatear/3` delegando en ellos.
- La validación compartida (`Tipo.Patron.Validacion`): patrón válido,
  tokens del tipo correcto, largo suficiente, pivote entero.
- Tests por formato en `campo_test` (round-trip de cada uno, valores
  imposibles con causa, definición inválida), y los tres tipos con todos
  sus formatos en los generadores de propiedades, serializados con
  `Calendar.strftime` como oráculo.

## Decisiones tomadas

1. **Un motor de patrones y no tres tablas de formatos.** Los nombres son
   azúcar sobre patrones (`:aammdd` es `"AAMMDD"`); así el patrón explícito
   y el nombrado son el mismo camino y los diagnósticos son los mismos.
2. **`MM` es mes o minuto según venga después de `HH`.** La alternativa era
   un token distinto para minutos (`MI`), que no es lo que la gente escribe
   ni lo que la issue nombra (`AAAAMMDDHHMMSS`). La regla es determinista y
   está documentada.
3. **`:pivote` es el primer año de la ventana**, no el año de corte: con
   `2000` todo es 20xx, con `1970` lo que va de `70` a `99` es 19xx. Cubre
   las dos convenciones con un solo número, y al escribir un año fuera de
   la ventana es un diagnóstico y no un `00`.
4. **`:fecha_hora` es `NaiveDateTime`.** Un archivo de ancho fijo no trae
   zona horaria; ponerle UTC sería inventar un dato.
5. **El relleno no se valida en el patrón, sí los separadores.** Un
   `31-01-2024` en un campo `"DD/MM/AAAA"` es un diagnóstico que nombra
   el patrón, no "caracteres no numéricos".
