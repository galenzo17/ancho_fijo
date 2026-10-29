---
prompt: 0048
fecha: 2026-10-29T14:00:00-03:00
autor: Agustín Bereciartúa <bereciartua.agustin@gmail.com>
modelo: claude-fable-5-1
issue: 94
---

# 0048 — `relleno_final: :tolerar` repone un relleno latin-1 no ASCII (issue #94)

**Contexto:** sexta iteración del segundo loop. Con `encoding: :latin1`,
`relleno_final: :tolerar` y un `:relleno` como `"·"`, el escritor completaba
bien (un byte `0xB7`, porque `Campo.completar/4` mide en el encoding del
layout y después transcodifica) pero el lector no reponía: `Parser.reponible?/2`
medía `byte_size("·")` sobre el string Elixir, dos bytes en UTF-8, sin mirar
el encoding, y `completar_relleno/4` habría pegado esos bytes UTF-8 a una
línea todavía en latin-1. El round-trip se rompía y el layout no avisaba.

## Prompt

> revisa si hay pr que mergear y luego issues por cerrar arma un /loop
> merge y sigu y luego otro, si salen issues crealas, y luego otro
> verification loop pr revie merge y asi sucesivo senior level

## Resultado

- `Parser.relleno_reponible/3` reemplaza a `reponible?/2`: con
  `unidad: :bytes` transcodifica el relleno al encoding del campo (o del
  layout) y lo da por reponible si queda en un byte (en latin-1, cualquier
  carácter hasta U+00FF; en UTF-8, solo ASCII), y ese byte es el que se pega
  a la línea; con `:caracteres` cualquier carácter sirve. La zona tolerable
  compara los rellenos ya codificados.
- `Layout.rellenos_anchos/2` avisa también cuando un campo en latin-1 tiene
  un relleno que no existe en latin-1 (`"€"`): al escribir es un
  diagnóstico `:encoding` y al leer no se repone.
- Tests en `escritura_en_bytes_test.exs`: el snippet de la issue (round-trip
  y línea corta con `:relleno_completado`), el encoding por campo, el mismo
  relleno en UTF-8 midiendo bytes (advertencia y no se repone), `"€"` en
  latin-1 (advertencia, diagnóstico al escribir, no se repone), y una
  propiedad: en las tres configuraciones (UTF-8 bytes, caracteres, latin-1)
  y con rellenos ASCII y no ASCII, lo que el escritor completa el lector lo
  lee igual con la línea entera y con el relleno final recortado.

## Decisiones tomadas

1. La transcodificación del relleno se hace con
   `:unicode.characters_to_binary/3` en el parser, no con un helper nuevo
   de `Transcodificacion`: es una llamada y el módulo solo convierte hacia
   UTF-8.
2. Se mantiene el criterio de "un byte" para UTF-8 midiendo bytes: un
   relleno de dos bytes no puede dar un ancho exacto, y eso ya lo avisa el
   layout.
