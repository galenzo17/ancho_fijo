# 0002 — Mantener un directorio de prompts

**Fecha:** 2026-08-06
**Contexto:** llegó a mitad de la implementación de `0.1.0`, mientras se
escribían los módulos de la librería.

## Prompt

> asegura que en este repoo mantengamos u ndir para promps, con la historia .md
> de cada prompt

## Resultado

Se creó `prompts/` con:

- `README.md` — la convención de nombres, el formato de cada archivo y el
  índice.
- `0001-creacion-inicial-libreria.md` — el prompt de origen de la librería,
  transcrito literal, con las decisiones de diseño que no venían en él.
- `0002-directorio-de-prompts.md` — este archivo.

`prompts/` queda fuera de la lista `files` de `mix.exs`: es historia del
repositorio, no del paquete publicado en Hex.

## Decisiones tomadas

- **Numeración de cuatro dígitos** en vez de fecha en el nombre. La fecha va
  dentro del archivo; el número da orden estable aunque dos prompts caigan el
  mismo día.
- **Transcripción literal**, incluyendo los typos. Un prompt reescrito en prosa
  limpia pierde la ambigüedad que después explica por qué el código quedó como
  quedó.
- **Sección "decisiones tomadas"** obligatoria: es la parte que el prompt no
  contiene y la que realmente se busca meses después.
