---
prompt: 0053
fecha: 2026-10-29T11:17:25-03:00
autor: Agustín Bereciartúa <bereciartua.agustin@gmail.com>
modelo: claude-fable-5-1
issue: 99
---

# 0053 — `encoding: :cp1252`: lo que exportan Excel y Notepad (issue #99)

**Contexto:** undécima iteración del segundo loop. La librería reconocía
Windows-1252 en el diagnóstico ("0x93 es un carácter de control en latin-1
pero una comilla en Windows-1252") pero no podía leerlo ni escribirlo, y el
README lo descartaba junto con "otros encodings". La issue dejó escritos
los dos lados y pidió decidir: cp1252 no es un codepage más, es latin-1 más
27 caracteres, el default de Windows en toda la región y el archivo con el
que empieza el README.

## Prompt

> revisa si hay pr que mergear y luego issues por cerrar arma un /loop
> merge y sigu y luego otro, si salen issues crealas, y luego otro
> verification loop pr revie merge y asi sucesivo senior level

## Resultado

- `Transcodificacion`: tabla de los 27 bytes de 0x80–0x9F (`cp1252/0`),
  `a_utf8/2` con `:cp1252` (los cinco bytes sin definir, 0x81, 0x8D, 0x8F,
  0x90 y 0x9D, son `:byte_sin_definir`; los controles son los de ASCII y
  0x7F), `de_utf8/2` nuevo para los tres encodings (el primer carácter que
  no cabe, con su posición 1-based), `cp1252?/1` y `detectar/1` que lo
  distingue de latin-1, y las causas probables: un control de 0x80–0x9F en
  latin-1 y una continuación suelta de ese rango en UTF-8 dicen "declare
  encoding: :cp1252".
- `Campo` y `Layout` aceptan `:cp1252` (por campo y global); medir y
  recortar lo tratan como latin-1 (un byte por carácter);
  `Campo.codificar/3` usa `de_utf8/2` para latin-1 y cp1252; el relleno se
  repone y se valida con la misma tabla. `Serializacion` no cambia;
  `priv/layout.schema.json` y `Documentacion` ("Windows-1252") sí.
- `detectar/2`: `encoding_probable: :cp1252` cuando hay bytes de 0x80–0x9F
  definidos y nada UTF-8 multibyte, con el primer byte, posición y línea en
  la observación; `contrastar/2` lo reclama frente a un layout UTF-8 o
  latin-1.
- Tests: los 27 caracteres ida y vuelta, los cinco sin definir, el
  snippet de la issue (`JOSÉ “X”` se lee y se escribe byte a byte), `"→"`
  como diagnóstico, encoding por campo, relleno `•`, detección y
  contraste, y las dos propiedades de `escritura_en_bytes_test.exs` con la
  configuración cp1252. README (es y en): la decisión pasa a "tres
  encodings y nada más, y por qué".

## Decisiones tomadas

1. Se implementó en vez de cerrar con el "no": el costo es una tabla de 27
   entradas y su inversa, y el caso es el del ejemplo central del README.
   Para UTF-16, EBCDIC y el resto sigue valiendo el argumento del paquete
   chico: `detectar/2` los nombra (#98) y la conversión es un `iconv`.
2. Un byte suelto de 0x80–0x9F bajo un layout UTF-8 es ambiguo (la
   continuación de un multibyte cortado, o una comilla de Windows): la
   causa dice las dos cosas, salvo al principio del campo, donde el corte
   de un multibyte del campo anterior sigue siendo la explicación
   probable.
3. `:cp1252` en latin-1 o UTF-8 sigue siendo un diagnóstico de encoding,
   no una lectura "tolerante": la librería no adivina el encoding.
