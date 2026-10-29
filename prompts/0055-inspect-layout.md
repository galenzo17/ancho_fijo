---
prompt: 0055
fecha: 2026-10-29T21:00:00-03:00
autor: Agustín Bereciartúa <bereciartua.agustin@gmail.com>
modelo: claude-fable-5-1
issue: 101
---

# 0055 — `Inspect` para `Layout`, `Campo` y `Multiregistro` (issue #101)

**Contexto:** decimotercera iteración del segundo loop. `inspect/1` de un
layout imprimía cada campo con sus 30 claves, casi todas en su default: un
layout de 40 campos en un `IO.inspect`, en un mensaje de `AnchoFijo.Test`
o en una excepción eran páginas que nadie lee. `Diagnostico` y `Monto` ya
tenían su `Inspect`.

## Prompt

> revisa si hay pr que mergear y luego issues por cerrar arma un /loop
> merge y sigu y luego otro, si salen issues crealas, y luego otro
> verification loop pr revie merge y asi sucesivo senior level

## Resultado

- `#AnchoFijo.Campo<:monto 11-20 :decimal precision: 2, moneda: :usd>`:
  nombre, posiciones (o `largo N` si no está posicionado), tipo y solo las
  opciones que difieren del default, con el mismo criterio que
  `Serializacion.campo_a_mapa/1` (y `:sensible` según el tipo), las reglas
  que hay y las opciones de un tipo externo, en un orden fijo (lo que
  define el campo primero, lo cosmético después, los campos internos al
  final). Un grupo o una variante lleva sus campos adentro, con
  `container_doc` para que el pretty printer los parta bien.
- `#AnchoFijo.Layout<"nómina banco X", 4 campos, 48 bytes, latin1,
  relleno_final: :tolerar, identidad: [:rut], 1 advertencia>`: el nombre si
  lo hay, cuántos campos, el largo en su unidad, el encoding si no es
  UTF-8, y lo que un lector querría saber antes de abrir el archivo.
- `#AnchoFijo.Multiregistro<"NACHA", 3 tipos, por código en 1-2, orden
  libre, 1 control>`, con el discriminador en prosa.
- `inspect(x, structs: false)` sigue mostrando el mapa entero y
  `custom_options: [completo: true]` el struct entero. Ni `==`, ni
  `Map.from_struct/1`, ni la serialización cambian.
- Doctests en los tres módulos y `inspect_test.exs`: los ejemplos, el
  grupo anidado, las dos formas de ver todo, y que lo que se ve de cada
  campo coincide con su nombre y sus posiciones.

## Decisiones tomadas

1. Los campos no se listan dentro del `Layout`: un layout de 40 campos
   volvería a ser una página; se ven con `layout.campos`, y cada uno es
   una línea.
2. Un doctest no puede reutilizar una variable de otro bloque separado por
   prosa: en Elixir 1.14 son tests distintos y la variable no existe.
