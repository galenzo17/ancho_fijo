---
prompt: 0044
fecha: 2026-10-29T09:59:15-03:00
autor: Agustín Bereciartúa <bereciartua.agustin@gmail.com>
modelo: claude-fable-5-1
issue: 90
---

# 0044 — `desde_mapa/1`: un valor mal formado es un diagnóstico, no una excepción (issue #90)

**Contexto:** segunda iteración del segundo loop, con el PR de #89 ya
mergeado. `Layout.desde_mapa/1` y `Multiregistro.desde_mapa/1` prometen "los
mismos diagnósticos que `nuevo/1`", pero la conversión de valores en
`AnchoFijo.Serializacion` usaba las variantes con `!`: una fecha que no
existe en un `"rango"`, un `"patron"` que no compila o un decimal que no es
número salían como `ArgumentError`, `Regex.CompileError` o `Decimal.Error`.
El layout como datos existe para que lo edite alguien que no programa, y
esa persona va a escribir `2024-13-01`.

## Prompt

> revisa si hay pr que mergear y luego issues por cerrar arma un /loop
> merge y sigu y luego otro, si salen issues crealas, y luego otro
> verification loop pr revie merge y asi sucesivo senior level

## Resultado

- `Serializacion` convierte con `Date.from_iso8601/1`, `Time.from_iso8601/1`,
  `NaiveDateTime.from_iso8601/1`, `Regex.compile/2` y `Decimal.parse/1`. Lo
  que no se puede convertir es un diagnóstico `:layout` con el campo, la
  clave entre comillas tal como la escribió quien editó el mapa
  (`"rango": una fecha ISO 8601 (AAAA-MM-DD)`) y lo recibido; esa clave se
  saca de la definición y el resto sigue a `nuevo/1`, para que todos los
  problemas salgan en la misma lista.
- Los extremos de un `"rango"` se exigen del tipo del campo: texto ISO en
  `:fecha`, `:hora` y `:fecha_hora`, entero en `:entero`, y entero,
  `[unidades, precision]`, `[unidades, precision, "moneda"]` o texto en
  `:decimal`. Un tipo propio sigue recibiendo el extremo como vino.
- Un extremo decimal como texto en un proyecto sin `Decimal` dice qué
  agregar o cómo escribirlo como `[unidades, precision]`.
- Lo mismo anidado: grupos, variantes y el layout de cada tipo de un
  multiregistro (con el tipo como campo si el campo no tiene nombre).
- Dos propiedades: un layout y un multiregistro válidos con basura
  (`term/0`, mapas, listas, patrones rotos, fechas imposibles) en cualquier
  clave a cualquier profundidad responden `{:ok, _}` o
  `{:error, [%Diagnostico{}]}`. Las propiedades encontraron cuatro
  excepciones más, fuera de la conversión, que también se corrigieron:
  un nombre de campo que no es átomo rompía la ruta de los diagnósticos de
  un grupo o variante; un `:variantes` cuyo valor no es una lista dejaba un
  campo de largo 0 que tumbaba `Layout.nuevo/1` al posicionar; un control
  con `:en` que no es átomo tumbaba `Multiregistro.nuevo/1`; y un nombre
  con bytes que no son UTF-8 o de más de 255 caracteres rompía
  `String.to_atom/1`.

## Decisiones tomadas

1. La clave invalida se saca de la definición antes de `nuevo/1`, en vez de
   dejarla cruda: con el valor crudo adentro, `nuevo/1` agregaba un segundo
   diagnóstico menos claro sobre lo mismo (o, con un rango de texto en una
   fecha, no agregaba ninguno, porque `Reglas.comparar/2` responde `:eq`
   entre tipos distintos; eso es la issue #92).
2. Un `"variantes"` con un valor que no es lista no se convierte en
   `Serializacion`: se deja como vino y lo reclama `Tipo.Variante.validar/1`,
   que es donde se reclaman las otras formas inválidas de la opción.
3. Las propiedades mutan un mapa válido en una sola ruta por corrida, en vez
   de generar mapas enteros al azar: así cada corrida ejercita una
   validación concreta y el encogimiento señala la clave exacta.
