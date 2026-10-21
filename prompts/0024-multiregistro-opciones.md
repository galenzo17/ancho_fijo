---
prompt: 0024
fecha: 2026-10-21T18:03:48-03:00
autor: Agustín Bereciartúa <bereciartua.agustin@gmail.com>
modelo: claude-fable-5-1
issue: 38
---

# 0024 — Opciones, traza y telemetría del Multiregistro (issue #38)

**Contexto:** segunda iteración del loop sobre las issues abiertas; la rama
parte de la de #37 (prompt 0023). `Multiregistro.parsear/3` y `stream/3`
quedaron en la 0.3.0 por fuera del contrato de opciones de #16: una opción
desconocida se ignoraba, `modo: :otro` reventaba con `FunctionClauseError`
y `traza: true` se aceptaba sin hacer nada.

## Prompt

> anda a main y revisa luego las issues, arma un /loop cada issue un pr si
> es necesario, senior level ultra mega pro ultrathink

## Resultado

- `Opciones.validar!/3` al entrar a `parsear/3` y `stream/3`, con el
  esquema de `Parser`, que pasó a exponer sus helpers sin doc
  (`opciones_de_parsear/0`, `numerar/2`, `numerar_stream/2`, `fuente/2`,
  `seleccionar/2`, `numero_de/1`) para que los dos módulos numeren y
  validen igual.
- `traza: true` soportado: `{tipo, mapa}` con `:__traza__` en el mapa y el
  offset calculado como en `Parser`.
- `parsear/3` con `Parser.numerar/2`, que parte lazy, y una cuenta de
  líneas leídas para la telemetría.
- Eventos `parsear` y `stream` para multiregistro. `Telemetria` expone las
  piezas de `instrumentar_stream/2` (`iniciar_cuentas/1`, `contar/2`,
  `contar_cierre/2`, `cerrar_cuentas/2`) porque el stream del
  multiregistro ya tiene acumulador propio y emite un elemento de cierre
  que no es una línea.
- `:nombre` en la definición, `"NACHA"` en el catálogo, y las claves
  desconocidas rechazadas en `nuevo/1`.
- Tests en `multiregistro_test`, `superficie_test` y `telemetria_test`.

## Decisiones tomadas

1. **`:layout` en la metadata es el nombre del multiregistro, y para eso
   hubo que agregarle `:nombre`.** La issue pedía "el nombre del
   multiregistro o `nil`" y el struct no tenía nombre. Es la misma opción
   que `Layout`, opcional, y el único formato del catálogo la usa.
2. **`:encoding` y `:unidad` son `nil`.** Cada tipo de registro tiene su
   layout; inventar un valor global sería mentir, y el contrato documentado
   es que las claves existen siempre, no que tengan valor.
3. **El cierre cuenta como errores pero no como línea.** La alternativa era
   envolver el stream con `instrumentar_stream/2` por fuera y aceptar una
   línea de más en las medidas. Una medida que se sabe incorrecta no es una
   medida, así que las cuentas van en el acumulador del propio
   `Stream.transform/5` del multiregistro.
4. **Claves desconocidas en `nuevo/1`.** No estaba en la issue, pero es la
   misma clase de bug (`controls:` dejaría el trailer sin verificar) y la
   función para detectarlas ya existía en `Opciones`.
