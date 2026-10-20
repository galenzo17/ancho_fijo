---
prompt: 0022
fecha: 2026-10-20T18:19:55-03:00
autor: Agustín Bereciartúa <bereciartua.agustin@gmail.com>
modelo: claude-fable-5-1
issue: 45
---

# 0022 — Lo que ve un proyecto que agrega la librería (issue #45)

**Contexto:** los once PRs de la serie de issues entraron a `main` el mismo
día, encadenados, y había que sacar la 0.3.0. Al verificar la publicación
se instaló el paquete desde Hex en un proyecto vacío con Elixir 1.14, y esa
prueba de humo mostró dos warnings que CI nunca vio.

## Prompt

Dos mensajes. El que pidió la versión y la revisión:

> listo no quedan mas? todos merge? sacste version nueva a hex? hazlo, como
> probar revisar si todo ok? hazlo, revisa monitorea crea issues si
> encuantras algo, senior level ulktrathink

Y, con la 0.3.0 ya publicada y los hallazgos sobre la mesa, el que decidió
cómo seguir:

> mejor mergeo el 44y armas una issue y un fix nuevo, asi detallamos promp e
> historia

## Resultado

- Publicada la 0.3.0 en Hex con docs, con el tag `v0.3.0` sobre el commit
  de #44. El workflow de publicación falló porque el repo no tiene el secret
  `HEX_API_KEY`; se publicó desde la máquina con la clave local, como la
  0.1.0.
- La prueba de humo (`mix new` + `{:ancho_fijo, "~> 0.3.0"}`, Elixir 1.14):
  parsea, detecta y escribe; compila con dos warnings.
- Issues #37 a #43 con lo que la revisión del código integrado encontró, y
  #45 con lo de la prueba de humo.
- Este fix: `:crypto` en `extra_applications` con un test que lo fija,
  `@prefijo` adentro de la rama que lo usa, el mensaje de `a_decimal/1`
  con el requisito real, y el job de CI "Como dependencia" que repite la
  prueba de humo en dos versiones de Elixir y falla ante cualquier warning.

## Decisiones tomadas

1. **El job de CI compila la librería desde un proyecto vacío, no desde el
   repo.** Los dos warnings solo existen cuando no hay nada que los tape:
   `:crypto` llega al path a través de las deps de dev y test, y `@prefijo`
   se usa en la rama que compila cuando `:telemetry` está. Un
   `--warnings-as-errors` en el repo no los puede ver nunca. El job usa
   `path:` y no Hex para probar el commit, no la última publicación.
2. **`:crypto` es un bug, no un warning.** Sin la declaración, `mix release`
   de una app que no arrastre `:ssl` deja afuera la aplicación, y
   `huella/2` e `identidad/3` fallan con `UndefinedFunctionError` en
   producción. El test fija la declaración para que no se pierda en una
   limpieza de `mix.exs`.
3. **`decimal` no sube su mínimo a 3.1.2**, como sugería la revisión
   automática del #44. Es opcional y solo la usa `a_decimal/1`; exigir 3.x
   rompería la resolución de deps a cualquier app en `decimal` 2.x por Ecto.
   Quien la agrega elige la versión y recibe su propio aviso de
   `mix hex.audit`; lo que esta librería garantiza es no impedir la serie
   corregida (#43).
4. **El fix va en un PR aparte y no dentro de #44**, para que el commit del
   tag `v0.3.0` quede intacto en la historia de `main` y la 0.3.1 tenga su
   propio prompt, su issue y su sección en el CHANGELOG.
