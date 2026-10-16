---
prompt: 0008
fecha: 2026-10-16T21:10:00-03:00
autor: Agustin Bereciartua <bereciartua.agustin@gmail.com>
modelo: claude-fable-5-1
issue: 14
---

# 0008 — CI en GitHub Actions y publicación por tag (issue #14)

**Fecha:** 2026-10-16
**Contexto:** la `0.2.0` se acababa de publicar a mano, desde la máquina, con
la API key de Hex en un `.env`. El repo no tenía `.github/`: credo,
dialyzer, doctests y propiedades corrían solo cuando alguien se acordaba, y
el `elixir: "~> 1.14"` de `mix.exs` era una afirmación sin evidencia.

## Prompt

El `/loop` que gobierna la serie de issues, sin prompt propio para esta:

> y arma un /loop de cada issue que necesita un pr armalo y que sea senior
> level planifica monitorewa senio senior

## Resultado

- `.github/workflows/ci.yml`: job `pruebas` con matriz de cuatro pares
  Elixir/OTP (1.14.5/25, 1.16.3/26, 1.18.4/27, 1.20/28), compilación con
  warnings como errores en todas; job `calidad` solo en 1.20/28 con formato,
  credo estricto, dialyzer con el PLT en caché y cobertura con umbral.
- `.github/workflows/release.yml`: en tag `v*`, verifica que el tag
  coincide con `@version` y con una sección del CHANGELOG, corre la suite y
  publica con `HEX_API_KEY` como secret del repositorio.
- `test_coverage` en `mix.exs`: umbral del 90 %, sin contar
  `test/support`.
- Badge de CI en el README y entrada en el CHANGELOG.
- Antes de escribir la matriz se verificó localmente, en contenedores
  aislados, que la suite pasa en 1.14.5/OTP 26 y en 1.18.4/OTP 28.

## Decisiones tomadas

1. **El mínimo declarado se mantiene en 1.14.** La suite pasa en 1.14.5 sin
   tocar nada. El único warning que aparece es de credo (`Map.intersect/2`),
   que es una dependencia de desarrollo y no afecta al paquete publicado.
   Las dependencias se compilan en un paso aparte justamente para que
   `--warnings-as-errors` aplique solo a `lib/`.

2. **Los checks lentos corren una sola vez, en la versión más nueva.** El
   criterio: la matriz responde "¿compila y pasa en cada versión?"; formato,
   credo, dialyzer y cobertura responden "¿el código está bien?", y esa
   respuesta no depende de la versión del lenguaje. Correrlos cuatro veces
   sería cuatro veces el costo por la misma respuesta. La versión más nueva
   es la que tiene el dialyzer más preciso y los warnings más actuales.

3. **Dos cachés con claves distintas.** `deps` y `_build` cambian con cada
   `mix.lock` y con las versiones exactas que `setup-beam` resolvió (la
   clave usa `steps.beam.outputs.*`, no `matrix.*`, porque `"1.20"` puede
   resolver a otro patch mañana). El PLT cambia con OTP y con las
   dependencias, y se restaura y guarda en pasos separados con
   `if: always()` en el guardado: si dialyzer falla por un error real, el
   PLT igual queda cacheado. Con `actions/cache` a secas un job rojo no guarda
   nada, y el tiempo de construcción se paga en cada intento de arreglo.

4. **Cobertura: umbral, sin badge ni servicio.** `mix test --cover` falla si
   el total cae del 90 % (hoy está en 94 %). No se publica a Codecov ni
   similar y no hay badge: un número visible invita a escribir tests para el
   número. Los módulos de `test/support` no cuentan, no son código del
   paquete.

5. **La publicación verifica antes de obedecer.** El tag es la orden, pero
   un tag `v0.3.0` con `@version "0.2.0"` publicaría la versión equivocada
   o fallaría a mitad. Se comprueba que coincidan y que el CHANGELOG tenga
   la sección, con `sed` y `grep` sobre los archivos, sin arrancar Mix.
   La `0.2.0` ya estaba publicada a mano; el workflow aplica desde la
   siguiente.

6. **El secret se carga a mano, una vez.** `HEX_API_KEY` va en Settings →
   Secrets del repositorio, generada en hex.pm con permiso `api:write`. La
   copia del `.env` local sobra después de eso.

7. **Runner 22.04 para el par más viejo.** Los builds precompilados de OTP 25
   que usa `setup-beam` existen para Ubuntu 22.04; para 24.04 no está
   garantizado. El resto corre en 24.04.

8. **`concurrency` con cancelación.** Dos pushes seguidos a la misma rama
   cancelan la corrida anterior. En un PR solo importa el último commit.
