---
prompt: 0032
fecha: 2026-10-21T19:19:00-03:00
autor: Agustín Bereciartúa <bereciartua.agustin@gmail.com>
modelo: claude-fable-5-1
issue: 52
---

# 0032 — Interoperar con `Decimal` sin tuplas (issue #52)

**Contexto:** décima iteración del loop sobre las issues abiertas; la rama
parte de la de #51 (prompt 0031). Los campos `:decimal` entregaban
`{unidades, precision}` o un `Monto`, y cada consumidor con Ecto terminaba
convirtiendo a `Decimal` en cada campo, ida y vuelta.

## Prompt

> anda a main y revisa luego las issues, arma un /loop cada issue un pr si
> es necesario, senior level ultra mega pro ultrathink

## Resultado

- `como: :decimal` en el campo y `decimales_como: :decimal` en el layout
  (que lo fija como default de los `:decimal` que no lo declaran, también
  para los que llegan como struct). Sin `Decimal` cargado, el layout es
  inválido con un diagnóstico que dice qué agregar.
- `Tipo.Decimal.a_unidades/2`: un `%Decimal{}`, un entero (unidades
  enteras) o un string numérico a unidades mínimas, sin redondear; NaN,
  infinito y un string que no es número son causas distintas.
  `Campo.formatear/3` lo usa para cualquier `:decimal`, con o sin moneda.
- `Monto.desde_decimal/2,3` y `Monto.nuevo/3` con un `Decimal`.
- El job de CI "Como dependencia" verifica el camino sin `Decimal`: el
  diagnóstico de layout, el string que no se puede leer, y la tupla y el
  entero que sí.
- README: sección "Si ya usas Decimal" y el trade-off actualizado.

## Decisiones tomadas

1. **El entero se interpreta en unidades enteras, no mínimas.** Quien
   escribe `1250` en un campo con dos decimales quiere 1.250,00; las
   unidades mínimas ya tienen su forma, la tupla. Está documentado.
2. **Con `:moneda` y `como: :decimal` el valor es el `Decimal`, no el
   `Monto`.** La moneda está en el layout; quien pide `Decimal` quiere
   `Decimal`.
3. **Sin `Decimal`, `como: :decimal` es un layout inválido, no una
   degradación a tuplas.** Degradar en silencio cambiaría el tipo del valor
   según qué dependencias tenga el proyecto, que es peor que fallar al
   construir el layout.
4. **La prueba sin `Decimal` va en el job "Como dependencia"** y no en la
   suite: en el repo `Decimal` está siempre, y descargarlo en un test es
   una mentira frágil.
