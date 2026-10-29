# Cómo contribuir

El README dice qué hace la librería y por qué; esto dice cómo trabajar en
ella: cómo correr la suite en toda la matriz sin instalar Elixir, qué exige
CI, qué lleva un PR y cómo se publica una versión. Son los comandos que el
mantenedor usa; copiarlos alcanza.

## La suite en toda la matriz, con docker

CI corre en Elixir 1.14 / OTP 25 (el mínimo que declara `mix.exs`) y en
1.20 / OTP 28 (el más nuevo), además de 1.16 y 1.18. Cada versión nueva de
Elixir trae deprecaciones (1.20 marcó `binary-size(var)` sin pin y cambió
el formateador), y conviene verlas en local antes que en CI. No hace falta
instalar nada: las imágenes oficiales de docker traen cada versión.

Esta función corre `mix` adentro de la imagen que se le pida, con el
`_build`, las dependencias, el `HOME` y los PLT de dialyzer **fuera del
repositorio** y con el usuario de la máquina, para que docker no deje
archivos de root ni directorios que un `git add -A` metería en un commit:

```sh
# mixd IMAGEN TAREA...   por ejemplo: mixd 1.20-otp-28 test
mixd() {
  imagen="elixir:$1"; shift
  dir="${TMPDIR:-/tmp}/ancho_fijo-docker/$imagen"
  mkdir -p "$dir/build" "$dir/deps" "$dir/home" "$dir/plts"
  docker run --rm --user "$(id -u)" -v "$PWD":/app -w /app \
    -v "$dir/build":/build -v "$dir/deps":/deps -v "$dir/home":/home/u \
    -v "$dir/plts":/app/priv/plts \
    -e MIX_BUILD_PATH=/build -e MIX_DEPS_PATH=/deps -e HOME=/home/u \
    -e MIX_ENV="${MIX_ENV:-test}" \
    "$imagen" sh -c 'mix local.hex --force >/dev/null && mix local.rebar --force >/dev/null \
      && git config --global --add safe.directory /app && mix "$@"' -- "$@"
}
```

Con eso, lo que CI corre, en el orden en que conviene correrlo en local
(de lo barato a lo lento):

```sh
mixd 1.20-otp-28 deps.get
mixd 1.20-otp-28 format --check-formatted
mixd 1.20-otp-28 compile --force --warnings-as-errors
mixd 1.20-otp-28 test
mixd 1.20-otp-28 credo --strict
MIX_ENV=dev mixd 1.20-otp-28 deps.get
MIX_ENV=dev mixd 1.20-otp-28 dialyzer          # la primera vez construye el PLT: minutos
MIX_ENV=dev mixd 1.20-otp-28 docs --warnings-as-errors
MIX_ENV=dev mixd 1.20-otp-28 hex.build && sh .github/scripts/verificar_paquete.sh
mixd 1.20-otp-28 prompts.verificar

mixd 1.14 deps.get
mixd 1.14 test                                  # el mínimo: lo que compila en 1.20 puede no compilar acá
```

Tres cosas que cuestan descubrir:

- `MIX_BUILD_PATH` es un solo directorio para todos los entornos: después
  de un `MIX_ENV=dev`, el siguiente `test` recompila, y `MIX_ENV=prod` deja
  sin las dependencias de test. No es un error.
- El formateador de CI ("1.20" resuelve al último parche) parte algunas
  líneas largas que la imagen `1.20-otp-28` acepta: si CI reclama el
  formato, partir la línea a mano.
- La prueba "Como dependencia" de CI compila la librería desde un `mix new`
  vacío, sin `:decimal` ni `:telemetry`, y falla con un solo warning. Para
  reproducirla, un proyecto en otro directorio con
  `{:ancho_fijo, path: "../ancho_fijo"}` y `mix deps.compile`; **nunca**
  `mix deps.clean` con `MIX_BUILD_PATH` en la raíz del contenedor, que borra
  `lib/ancho_fijo` del repo montado.

## Los prompts, en dos commits

Cada cambio significativo tiene su archivo en [`prompts/`](prompts/README.md):
el pedido literal, el resultado y las decisiones que el pedido no traía.
`mix prompts.verificar` contrasta cada archivo con git (numeración,
frontmatter, fecha y autor del commit que lo agregó) y CI lo exige.

El flujo es en dos commits porque la fecha del frontmatter es la del
commit que agrega el archivo, y esa fecha no existe hasta commitear:

```sh
git add lib test prompts CHANGELOG.md README.md README.en.md   # por rutas, nunca -A
git commit -m "Lo que cambia, en una frase"
mixd 1.20-otp-28 prompts.verificar --corregir                  # escribe fecha y autor
git add prompts/NNNN-titulo.md
git commit -m "Corregir fecha y autor del prompt NNNN con lo que git registró"
```

Por lo mismo, los PRs se mergean con **merge commit**, nunca con squash ni
rebase: un squash reescribe el commit de alta del prompt y
`mix prompts.verificar` lo detecta como un archivo sin commit.

## Qué exige CI

Cinco jobs, en paralelo, sobre cada PR y sobre `main`:

| Job | Qué corre |
| --- | --- |
| Elixir X / OTP Y (×4) | `compile --warnings-as-errors` y la suite en cada par de la matriz; en 1.20, con cobertura ≥ 90 % |
| Formato, credo y dialyzer | `format --check-formatted`, `credo --strict`, `hex.audit`, `deps.audit`, `dialyzer` |
| Paquete de Hex y documentación | `compile --warnings-as-errors` en dev, `docs --warnings-as-errors`, `hex.build` y `verificar_paquete.sh` |
| Registro de prompts | `prompts.verificar` |
| Como dependencia (×2) | la librería desde un `mix new` vacío, sin warnings, en 1.14 y 1.20 |

Todo lo que CI corre está en la lista de comandos de arriba.

## Qué lleva un PR

- Un issue (`Closes #N` en la descripción; GitHub no entiende "Cierra").
- Una entrada en `## [No publicado]` del `CHANGELOG.md`, en español y con
  la convención de [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/):
  `### Agregado`, `### Cambiado`, `### Cambiado — rompe compatibilidad`
  (con qué hay que tocar), `### Corregido`, `### Seguridad`,
  `### Infraestructura`.
- `README.md` y `README.en.md` a la par cuando el cambio toca la guía: un
  test compara los glosarios y cuenta las secciones de los dos.
- El prompt, con su fila en `prompts/README.md`.
- Tests. La suite tiene propiedades (StreamData) para lo que se puede
  enunciar como invariante; un bug corregido lleva el caso que lo reproduce.

## Cómo se publica una versión

Solo desde CI, al empujar un tag. En una rama `version-X.Y.Z`:

1. `@version` en `mix.exs`.
2. `CHANGELOG.md`: `## [No publicado]` pasa a `## [X.Y.Z] — AAAA-MM-DD`.
3. `README.md` y `README.en.md`: la dependencia `{:ancho_fijo, "~> X.Y.Z"}`.
4. `SECURITY.md`: la tabla de versiones con soporte (la serie nueva con
   correcciones y seguridad; la anterior solo seguridad durante seis
   meses). Un test y `release.yml` lo verifican.
5. PR, merge con merge commit, y el tag anotado `vX.Y.Z` **sobre el commit
   de la rama**, no sobre el merge: `release.yml` verifica que el tag
   coincida con `mix.exs`, el CHANGELOG y `SECURITY.md`, corre la suite,
   arma y verifica el paquete y las docs, y publica en Hex con el secret
   `HEX_API_KEY` del repositorio.

Este archivo no viaja en el paquete de Hex: es del repositorio, no del
usuario de la librería.
