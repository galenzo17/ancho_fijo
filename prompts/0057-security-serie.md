---
prompt: 0057
fecha: 2026-10-29T22:30:00-03:00
autor: Agustín Bereciartúa <bereciartua.agustin@gmail.com>
modelo: claude-fable-5-1
issue: 103
---

# 0057 — La tabla de `SECURITY.md` sigue a `@version` (issue #103)

**Contexto:** decimoquinta iteración del segundo loop. `SECURITY.md` decía
que la serie con soporte era 0.3.x: la 0.4.0 se publicó el 2026-10-23 y la
tabla no se tocó, y nada lo verificaba.

## Prompt

> revisa si hay pr que mergear y luego issues por cerrar arma un /loop
> merge y sigu y luego otro, si salen issues crealas, y luego otro
> verification loop pr revie merge y asi sucesivo senior level

## Resultado

- La tabla dice 0.4.x con correcciones y seguridad, 0.3.x solo seguridad
  hasta el 2027-04-23 (seis meses después de 0.4.0, la política del README)
  y < 0.3 sin soporte, y explica que se actualiza en el PR de versión.
- `release.yml` verifica que la tabla nombre la serie `X.Y.x` del tag, con
  el mismo patrón de error que usa para `mix.exs` y el CHANGELOG.
- `seguridad_test.exs`: la fila de la serie de `@version` existe y dice
  "Correcciones y seguridad"; la anterior dice "Solo seguridad" con fecha;
  las más viejas "Sin soporte". Falla en el PR de versión, antes del tag.

## Decisiones tomadas

1. La fecha de fin de soporte de la serie anterior se escribe a mano en la
   tabla (el test solo exige que haya una): calcularla desde el CHANGELOG
   ataría el test a un formato de fecha que no tiene por qué ser estable.
