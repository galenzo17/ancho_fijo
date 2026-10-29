---
prompt: 0047
fecha: 2026-10-29T10:19:58-03:00
autor: Agustín Bereciartúa <bereciartua.agustin@gmail.com>
modelo: claude-fable-5-1
issue: 93
---

# 0047 — Una ruta que no existe es un diagnóstico, no el contenido de una línea (issue #93)

**Contexto:** quinta iteración del segundo loop. Con `desde: :auto`,
`Entrada.ruta?/2` exigía `File.regular?/1`: `"nomina_enero.txt"` sin el
archivo se trataba como contenido y el diagnóstico culpaba al largo de la
línea; `huella/2` devolvía la huella del nombre del archivo. Es el error
número uno del día uno (directorio de trabajo equivocado, fecha mal
escrita en el nombre, archivo que no llegó) y la librería decía otra cosa.

## Prompt

> revisa si hay pr que mergear y luego issues por cerrar arma un /loop
> merge y sigu y luego otro, si salen issues crealas, y luego otro
> verification loop pr revie merge y asi sucesivo senior level

## Resultado

- `Entrada.ruta?/2` en `:auto`: un binario plausible es ruta si existe
  como archivo **o si parece una ruta**: termina en una extensión
  (`\.[A-Za-z][A-Za-z0-9]{0,4}\z`) o empieza con `/`, `./`, `../`, `~/`,
  una unidad de Windows (`C:\`, `D:/`) o `\\`. Una que parece ruta y no
  existe sigue el camino del archivo y sale como diagnóstico `:entrada`
  `:enoent` en `parsear/3`, `parsear!/3`, `stream/3`, `detectar/2`,
  `huella/2` e `identidad/3`, con `Layout` y con `Multiregistro`; un
  directorio con prefijo de ruta sale como `:eisdir`.
- La causa del `:enoent` agrega "si quiso pasar el contenido y no una ruta,
  declare `desde: :contenido`" solo cuando no se pasó `desde:`.
- `entrada_test.exs` nuevo: los seis puntos de entrada, el multiregistro,
  `desde: :archivo` sin la pista, el directorio, y lo que sigue siendo
  contenido (`desde: :contenido`, sin extensión ni prefijo, `"01/01/1950"`,
  `"datos/nomina"`, `"TOTAL 12.50"`, con terminador, una ruta que sí
  existe). Doc de `parsear/3` y CHANGELOG bajo "rompe compatibilidad".

## Decisiones tomadas

1. La issue proponía "contiene un separador de directorio" como criterio.
   Con eso, ocho propiedades de la suite fallaron con una línea sola
   `"01/01/1950"`: una fecha con barras, sin terminador, se tomaba por
   ruta. Se acotó a extensión al final o prefijo de ruta al principio; un
   `datos/nomina` sin extensión queda como contenido, y `desde: :archivo`
   lo zanja.
2. La pista sobre `desde: :contenido` no aparece con `desde: :archivo`: si
   el llamador dijo que es un archivo, la pista es ruido.
