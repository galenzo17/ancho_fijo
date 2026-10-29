---
prompt: 0043
fecha: 2026-10-27T18:20:00-03:00
autor: Agustín Bereciartúa <bereciartua.agustin@gmail.com>
modelo: claude-fable-5-1
issue: 89
---

# 0043 — JSON: un escape `\u` inválido es un error, no un throw (issue #89)

**Contexto:** primera iteración del segundo loop. Con la 0.4.0 publicada y
una sola issue abierta (#42, el blob de 100 MB), el pedido fue revisar la
librería con criterio senior, abrir las issues que faltaban y resolverlas
una por PR. La revisión midió 0.4.0 contra 0.3.1 y probó cada sospecha con
un script en docker antes de abrir las diecisiete issues (#89 a #105). Esta
es la primera: `AnchoFijo.Json.decodificar/1` lanzaba un `throw` con un
escape `\u` que no fuera hexadecimal, y nadie lo atrapaba.

## Prompt

> arma un /loop crea las issues y los pr, senior level ultrathink todas las
> issues y todos los pr

## Resultado

- `escape_u/3` y `hex4/1` en `AnchoFijo.Json`: un `\u` con cuatro dígitos
  que no son hexadecimales o un *surrogate* sin su par es `{:error, motivo}`,
  como el resto de los errores del decodificador. `Integer.parse/2` dejó de
  usarse porque acepta un signo (`\u-001` daba `<<-1::utf8>>`, un
  `ArgumentError`).
- Un número con un exponente que no cabe en un float (`1e999`) también es
  `{:error, _}`: `String.to_float/1` levantaba.
- Tests: los casos puntuales, `Layout.desde_json/1` y
  `Multiregistro.desde_json/1` con esos JSON, la tarea
  `mix ancho_fijo.detectar --layout x.json` con código 2 y el motivo, y una
  propiedad que le pasa binarios arbitrarios y strings JSON con escapes al
  azar al decodificador y afirma que nunca levanta ni lanza.
- Sección `## [No publicado]` del CHANGELOG, que la 0.4.0 no tenía.

## Decisiones tomadas

1. El mensaje nombra el escape (`\uZZZZ`) y la causa (hexadecimales o
   surrogate), en vez de un "escape inválido" genérico: un JSON editado a
   mano se corrige buscando ese texto.
2. No se cambió nada más del decodificador: la propiedad es la que sostiene
   que no quedan otras salidas que no sean `{:ok, _}` o `{:error, _}`.
