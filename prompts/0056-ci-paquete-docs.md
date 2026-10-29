---
prompt: 0056
fecha: 2026-10-29T22:00:00-03:00
autor: Agustín Bereciartúa <bereciartua.agustin@gmail.com>
modelo: claude-fable-5-1
issue: 102
---

# 0056 — CI arma y verifica el paquete de Hex y las docs; timeouts en los jobs (issue #102)

**Contexto:** decimocuarta iteración del segundo loop. Al publicar la 0.4.0
se descubrieron dos cosas al empujar el tag: el tarball arrastraba
`priv/plts` y pasaba el tope de 16 MB, y las docs enlazaban módulos
ocultos. Ninguna se probaba en CI. Y los jobs no tenían `timeout-minutes`.

## Prompt

> revisa si hay pr que mergear y luego issues por cerrar arma un /loop
> merge y sigu y luego otro, si salen issues crealas, y luego otro
> verification loop pr revie merge y asi sucesivo senior level

## Resultado

- Job `paquete` en `ci.yml`, en paralelo con los demás: `mix compile
  --warnings-as-errors` en dev (el entorno en que `release.yml` publica),
  `mix docs --warnings-as-errors`, `mix hex.build` y
  `.github/scripts/verificar_paquete.sh`, que lista el contenido del
  tarball en el log y falla si pesa más de 1 MB o si incluye algo de
  `priv/plts/`, `prompts`, `test/`, `bench/`, `.github/` o `CONTRIBUTING`.
  `release.yml` corre los mismos cuatro pasos antes de `hex.publish`.
- `timeout-minutes` en los cinco jobs de CI (20 para la matriz y
  `dependencia`, 30 para `calidad`, 10 para `paquete` y `prompts`) y 20
  en `release.yml`.
- El chequeo ya encontró uno: la entrada del CHANGELOG de #89 enlazaba
  `AnchoFijo.Json.decodificar/1`, un módulo oculto, y `mix docs
  --warnings-as-errors` fallaba. Se reescribió sin el autoenlace.

## Decisiones tomadas

1. Un job aparte y no pasos en `calidad`: corre en paralelo, no espera al
   dialyzer, y su cache no se mezcla con el de credo.
2. El script vive en `.github/scripts/` y lo comparten los dos workflows,
   para que `release.yml` no pueda divergir de lo que CI verificó.
3. El directorio vacío `priv/plts/` viaja en el tarball porque `priv/`
   está en `:files` y Hex incluye la entrada del directorio aunque
   `:exclude_patterns` saque sus archivos; no pesa, y el patrón del script
   busca archivos adentro, no la entrada.
