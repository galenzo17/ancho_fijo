---
prompt: 0062
fecha: 2026-10-30T02:00:00-03:00
autor: Agustín Bereciartúa <bereciartua.agustin@gmail.com>
modelo: claude-fable-5-1
issue: 126
---

# 0062 — `stream/3` advierte el BOM y la marca de DOS como `parsear/3` (issue #126)

**Contexto:** la issue la abrió el loop al cerrar #98: `parsear/3` dejaba
las advertencias del BOM saltado y del `0x1A` omitido, y `stream/3` las
saltaba en silencio, con la excusa documentada de que "sus advertencias son
por línea y no hay a qué línea pegarlas". El pipeline que consume
`stream/3` sobre un archivo grande es justamente el que no mira
`detectar/2` antes.

## Prompt

> revisa si hay pr que mergear y luego issues por cerrar arma un /loop
> merge y sigu y luego otro, si salen issues crealas, y luego otro
> verification loop pr revie merge y asi sucesivo senior level

## Resultado

- `Parser.advertencias_de_marcas_de_entrada/2`: con un binario, las
  mismas advertencias que `parsear/3` (con número de línea); con una ruta,
  se leen los tres primeros bytes y los dos últimos del archivo con
  `:file.pread/3` (sin recorrerlo) y la advertencia del `0x1A` va sin
  número de línea; con un enumerable del llamador, nada.
- `Parser.con_iniciales_en_stream/2` las pega al primer elemento del
  stream (`{:ok, registro, iniciales ++ advertencias}` o
  `{:error, iniciales ++ diagnosticos}`), y sin marcas no agrega ninguna
  capa. Lo usan `Parser.stream/3` (antes de la telemetría, que así las
  cuenta) y `Multiregistro.stream/3`.
- Tests: binario con BOM y marca (líneas 1 y 3), ruta (la marca sin línea),
  sin marcas, enumerable, rechazo del BOM, y el multiregistro. La doc de
  `:bom` y el CHANGELOG de #98 dicen lo nuevo.

## Decisiones tomadas

1. Las dos advertencias van en el primer elemento, no la del `0x1A` en el
   último: pegarla al último exige retener un elemento en cada línea para
   saber cuál es el último, y eso se paga en todo stream; mirar el último
   byte del archivo una vez no se paga en ninguna línea.
2. Con una ruta, la marca va sin número de línea a propósito: contar las
   líneas es recorrer el archivo, que es lo que `stream/3` existe para no
   hacer dos veces.
