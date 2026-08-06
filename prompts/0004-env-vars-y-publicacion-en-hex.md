# 0004 — Variables de entorno y publicación en Hex

**Fecha:** 2026-08-06
**Contexto:** el repo existía privado y con la `0.1.0` terminada. Agustín creó un
`.env` con la API key de Hex y notó que el `.gitignore` no lo cubría.

## Prompt

> cree un .env pero no esta en el gitignore, porque? elixir como maneja env
> vars? es la apikey para subirlo a hex, cuales son los pasos? debo hacerl
> oopensource creo, no es un problema para mi en todo caso

Seguido, a mitad de la verificación:

> no  se filtro, recien la cree y no hemossubido nada

## Resultado

- `.env` y `.env.*` agregados al `.gitignore`. Se verificó que el archivo nunca
  estuvo en el índice ni en ningún commit.
- Repositorio cambiado a **público**.
- `ancho_fijo 0.1.0` **publicado en Hex**: https://hex.pm/packages/ancho_fijo
- Documentación en https://hexdocs.pm/ancho_fijo
- Verificado instalando el paquete desde Hex en un proyecto nuevo.

## Decisiones tomadas

1. **Por qué el `.gitignore` no tenía `.env`.** El original era el que genera
   `mix new` más los PLTs de dialyzer. Elixir no lee `.env` por convención —no
   hay nada en el stack que lo cargue—, así que el gitignore idiomático no lo
   contempla. Fue una omisión de todos modos: un gitignore defensivo lo incluye,
   porque el día que el archivo aparece ya es tarde para acordarse.

2. **La API key de Hex no debería vivir en el `.env` del proyecto.** El flujo
   normal es `mix hex.user auth`, que guarda la key encriptada con passphrase en
   `~/.hex/hex.config`, fuera del árbol del repo y compartida entre todos los
   paquetes. `HEX_API_KEY` existe para CI, donde nadie puede escribir una
   passphrase. Tener la key en `<proyecto>/.env` es el peor de los dos mundos:
   nadie la usa automáticamente y está a un `git add -A` de filtrarse.

3. **El nombre de la variable estaba mal.** El `.env` decía `HEX_APIKEY`; Hex lee
   `HEX_API_KEY`. Se publicó leyendo ambos nombres desde el script.

4. **Público y Hex son la misma decisión.** El `mix.exs` declara
   `links: %{"GitHub" => ...}`. Publicar en Hex con el repo privado deja un link
   que da 404 a todo el que llegue al paquete. Por eso se hizo público antes de
   publicar, no después.

5. **Escaneo de secretos antes de hacerlo público.** Es el momento en que un
   descuido deja de ser reversible: una vez público, el contenido puede ser
   clonado e indexado aunque se revierta la visibilidad. El escaneo sobre los
   archivos trackeados no encontró nada.

6. **`prompts/` queda público.** Contiene los prompts literales, que ahora son
   parte del repo abierto. Se decidió mantenerlos: son la explicación de por qué
   el código quedó como quedó, que es el punto del repositorio.

## Nota sobre la ventana de reversión

Hex permite `mix hex.publish --revert 0.1.0` dentro de **una hora** de la
publicación. Pasada esa hora la versión es permanente: solo se puede
`mix hex.retire`, nunca borrar. La `0.1.0` de `ancho_fijo` queda ocupada para
siempre.
