---
prompt: 0050
fecha: 2026-10-29T10:32:29-03:00
autor: Agustín Bereciartúa <bereciartua.agustin@gmail.com>
modelo: claude-fable-5-1
issue: 97
---

# 0050 — La tabla ISO 4217 de `Monto` cumple lo que promete (issue #97)

**Contexto:** octava iteración del segundo loop. `AnchoFijo.Monto`
prometía "todas las monedas con escala distinta de dos" y faltaban cuatro:
CLF y UYW (4 decimales), BIF y UYI (0). CLF es la unidad de cuenta de los
créditos hipotecarios, los seguros y los fondos en Chile, el dominio de
origen de la librería: `moneda: :clf` sin `precision:` era un layout
inválido. De la región faltaban VES, CUP, BZD, SVC, HTG, JMD, TTD, BSD,
BBD, XCD, GYD, SRD, AWG, ANG, COU, MXV y BOV.

## Prompt

> revisa si hay pr que mergear y luego issues por cerrar arma un /loop
> merge y sigu y luego otro, si salen issues crealas, y luego otro
> verification loop pr revie merge y asi sucesivo senior level

## Resultado

- La tabla trae las 17 monedas de escala 0, las 7 de escala 3 y las 2 de
  escala 4 de la lista uno de ISO 4217 (consultada el 2026-10-29), más las
  de la región (incluidas VED y XCG, las que reemplazan a VES y ANG) y las
  de reserva. El comentario de la tabla dice de dónde sale y qué test la
  contrasta.
- `monto_test.exs`: la lista de exponentes distintos de dos escrita en el
  test con la fecha, y tres tests: toda moneda de esa lista está en la
  tabla con esa escala; ninguna moneda de la tabla la contradice (lo que no
  está en la lista tiene escala 2); las monedas de la región están. Y
  `moneda: :clf` lee y escribe un `Monto` de cuatro decimales sin
  advertencias, con `inspect` `#AnchoFijo.Monto<1.234,5678 CLF>`;
  `formatear/2` con 4 decimales.
- Doctests de `escala/1` con CLF y del moduledoc leyendo una UF. README
  (es y en): "KWD tres, CLF (la UF) cuatro".

## Decisiones tomadas

1. Las monedas con escala "N.A." en ISO 4217 (metales, XDR, XTS, XXX) no
   entran: no son montos.
2. VED y XCG se agregan junto a VES y ANG: los archivos viejos traen el
   código viejo y los nuevos el nuevo, y la escala es la misma.
