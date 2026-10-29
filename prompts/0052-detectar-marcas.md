---
prompt: 0052
fecha: 2026-10-29T18:00:00-03:00
autor: Agustín Bereciartúa <bereciartua.agustin@gmail.com>
modelo: claude-fable-5-1
issue: 98
---

# 0052 — `detectar/2` reconoce el BOM, UTF-16, EBCDIC y el 0x1A final (issue #98)

**Contexto:** décima iteración del segundo loop. Los archivos que exporta
Windows y los que bajan de un mainframe traen marcas que `detectar/2` no
reconocía y que `parsear/3` diagnosticaba con la causa equivocada: el BOM
UTF-8 hacía que la línea 1 "midiera 3 bytes más", UTF-16 salía como
`:latin1` con el consejo de declarar `encoding: :latin1`, EBCDIC como
latin-1 "sin terminadores", y el `0x1A` final como una línea corta.

## Prompt

> revisa si hay pr que mergear y luego issues por cerrar arma un /loop
> merge y sigu y luego otro, si salen issues crealas, y luego otro
> verification loop pr revie merge y asi sucesivo senior level

## Resultado

- `Detector`: claves nuevas `:bom` (`:utf8 | :utf16le | :utf16be | nil`) y
  `:marca_final_dos?`; `encoding_probable` puede ser `:utf16` (con BOM, o
  sin BOM por un byte nulo cada dos) o `:ebcdic` (casi ningún byte donde
  ASCII pone letras y dígitos, el espacio EBCDIC `0x40` entre los tres
  bytes más frecuentes, y no es UTF-8 válido). El BOM y la marca final se
  sacan antes de partir las líneas: los largos salen sin ellos. Las
  observaciones van primero y dicen qué hacer (`bom: :ignorar`, `iconv -f
  UTF-16LE -t UTF-8`, `iconv -f IBM037 -t UTF-8`, "no es un registro").
  `probablemente_ancho_fijo?` es `false` para UTF-16 y EBCDIC.
- `parsear/3` y `stream/3` (con `Layout` y con `Multiregistro`): opción
  `bom: :rechazar | :ignorar`. Con `:rechazar`, `causa_de_largo/4` nombra
  el BOM en la línea 1; con `:ignorar`, `Parser.sin_bom/2` lo saca de la
  primera línea (la traza sigue midiendo los bytes del archivo) y
  `parsear/3` deja una advertencia `:encoding`. Una última línea que es
  solo `0x1A` se omite con `omitir_vacias: true` y `parsear/3` deja una
  advertencia `:entrada` con el número de línea (los terminadores se
  cuentan en C solo cuando hay marca); sin `omitir_vacias`, el diagnóstico
  de largo dice qué es, y pegada a la última línea el diagnóstico de
  encoding del `0x1A` también. `Parser.preparar_numeradas/2` y
  `con_iniciales/2` son el camino común de los dos parsers.
- Fixtures: `nomina_con_bom.txt`, `nomina_utf16le.txt`, `nomina_ebcdic.txt`
  (cp037) y `nomina_con_fin_dos.txt`, con datos inventados. Tests en
  `detector_test.exs` y `parser_test.exs`; README (es y en), doc de las
  opciones y de `huella/2` (el BOM y la marca cambian la huella).

## Decisiones tomadas

1. La heurística de EBCDIC de la issue ("ningún byte en 0x20..0x7E") no
   sirve: el espacio EBCDIC es `0x40` (`@` en ASCII) y la puntuación cae en
   `0x4B..0x7F`. Se mide la proporción de letras y dígitos ASCII, que en
   EBCDIC son punctuación rara.
2. `stream/3` salta las dos marcas sin advertencia: sus advertencias son
   por línea y no hay a qué línea pegarlas. Está documentado en la opción.
3. Con `bom: :ignorar` y `saltar: 1` no hay advertencia: la línea del BOM
   se saltó por otra razón.
4. `huella/2` no cambia, a propósito: los bytes son el dato.
