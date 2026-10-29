---
prompt: 0045
fecha: 2026-10-29T10:05:34-03:00
autor: Agustín Bereciartúa <bereciartua.agustin@gmail.com>
modelo: claude-fable-5-1
issue: 91
---

# 0045 — Los diagnósticos de escritura de un campo sensible no muestran el valor (issue #91)

**Contexto:** tercera iteración del segundo loop. `Campo.leer/3` pasa cada
diagnóstico de un campo `sensible: true` por `sensibilizar/3`, que lo marca
con la forma del valor; `Campo.formatear/3` no hacía nada parecido, y el
RUT con el dígito verificador malo que el sistema de nómina le entregaba al
escritor viajaba entero al log. El README prometía un test que recorre
"cada tipo de campo y cada falla posible", y `sensibles_test.exs` no tenía
un solo `escribir`.

## Prompt

> revisa si hay pr que mergear y luego issues por cerrar arma un /loop
> merge y sigu y luego otro, si salen issues crealas, y luego otro
> verification loop pr revie merge y asi sucesivo senior level

## Resultado

- `Campo.formatear/3` pasa su resultado por `sensibilizar_escritura/3`: el
  diagnóstico de error y las advertencias (`:campo_truncado`) de un campo
  sensible salen con `sensible: true` y `redactado` con la forma del valor,
  como al leer. Cubre reglas, `representar/3`, `codificar/3` y, a través de
  `Anidados.escribir/4`, los campos internos sensibles de un grupo o una
  variante.
- `Diagnostico.texto_de/1` (`@doc false`): el texto de un valor para
  describir su forma cuando el valor viene en el tipo del mapa (un entero,
  un `%Date{}`, un `{unidades, precision}`, un `%Monto{}`). `Reglas.regla/5`
  lo usa en vez de su `to_string/1` propio, que levantaba
  `Protocol.UndefinedError` con la tupla de un decimal sensible fuera de
  rango.
- `sensibles_test.exs` suma la matriz de escritura: trece fallas (no cabe,
  tipo incorrecto en entero y fecha, otra precisión, otra moneda, DV malo,
  latin-1 no representable, relleno con valor, constante con otro literal,
  rango, catálogo y patrón) más el truncado, el `nil` sin `opcional`, el
  snippet de la issue y un grupo y una variante por `AnchoFijo.escribir/3`.
  Las representaciones que se verifican, al leer y al escribir, ahora
  incluyen `a_mapa/1` y `Jason.encode!/1`.
- README (es y en): la garantía cubre también la escritura.

## Decisiones tomadas

1. El valor sigue en `:recibido` del struct, también en la advertencia de
   truncado: la política de la librería es redactar las representaciones,
   no el dato, y `revelar: true` lo muestra a propósito. La issue proponía
   sacarlo del struct en ese caso; se mantuvo la política única para no
   tener un diagnóstico que `revelar: true` no pueda revelar.
2. Los campos internos de un grupo o variante se marcan por su propio
   `sensible`, no por el del contenedor: es lo que hace la lectura, y un
   `:rut` adentro de un grupo ya es sensible por default.
3. Un carácter que latin-1 no tiene se reporta con la forma del valor
   completo, no del carácter: el carácter es parte del dato.
