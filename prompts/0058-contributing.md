---
prompt: 0058
fecha: 2026-10-29T23:00:00-03:00
autor: Agustín Bereciartúa <bereciartua.agustin@gmail.com>
modelo: claude-fable-5-1
issue: 104
---

# 0058 — `CONTRIBUTING.md`: la suite en toda la matriz con docker, los prompts, CI, el PR y la versión (issue #104)

**Contexto:** decimosexta iteración del segundo loop. El "cómo" de trabajar
en la librería vivía en la memoria de quien lo armó: la receta docker con
`MIX_BUILD_PATH` y `MIX_DEPS_PATH` fuera del repo, el flujo de prompts en
dos commits y por qué se mergea con merge commit, qué exige CI y en qué
orden correrlo, qué lleva un PR y cómo se publica una versión.

## Prompt

> revisa si hay pr que mergear y luego issues por cerrar arma un /loop
> merge y sigu y luego otro, si salen issues crealas, y luego otro
> verification loop pr revie merge y asi sucesivo senior level

## Resultado

- `CONTRIBUTING.md` con las cinco secciones y comandos copiables: una
  función `mixd IMAGEN TAREA` que corre `mix` en la imagen oficial de
  docker con `_build`, deps, `HOME` y los PLT fuera del repo y con el
  usuario de la máquina; la lista de lo que CI corre en el orden de lo
  barato a lo lento, en 1.20 y en 1.14; las tres cosas que cuestan
  descubrir (el build dir compartido entre entornos, el formateador de CI
  más nuevo, el `deps.clean` que borra el repo montado); los prompts en
  dos commits y el merge commit; la tabla de los cinco jobs; qué lleva un
  PR; los cinco pasos de una versión.
- Enlazado desde `README.md`, `README.en.md` ("Mantenimiento") y
  `SECURITY.md`. Un test en `seguridad_test.exs` verifica el archivo, los
  tres enlaces y que no esté en `:files` del paquete (y
  `verificar_paquete.sh` lo rechaza si entrara).

## Decisiones tomadas

1. Los directorios de docker van en `${TMPDIR:-/tmp}/ancho_fijo-docker/`,
   no en el repo ni en volúmenes con nombre: dentro del repo un `git add
   -A` los commitea (pasó en #69), y un volumen con nombre queda de root y
   `--user` no puede escribir.
2. Los enlaces a `CONTRIBUTING.md` son absolutos a GitHub porque el README
   también se lee en hexdocs, donde el archivo no existe.
