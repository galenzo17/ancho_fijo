# 0003 — Crear el repositorio

**Fecha:** 2026-08-06
**Contexto:** la librería `0.1.0` estaba terminada en un directorio local que no
era un repositorio git.

## Prompt

> el repo es mio personal, y debe ser creado, es solo para entender esto del
> ancho fijo y porque, solo por entender, crea el repo, privado por ahora

## Resultado

- `git init -b main` y commit inicial con los 36 archivos.
- Repositorio privado en `https://github.com/galenzo17/ancho_fijo`.
- `@source_url` en `mix.exs` apuntando al repo real (antes era un placeholder
  inventado), y `maintainers` con el nombre de la config de git.
- `.gitattributes` marcando `test/fixtures/*` como `-text -diff`.

## Decisiones tomadas

1. **`.gitattributes` para los fixtures.** Su encoding y sus terminadores de
   línea *son* el caso de prueba. Sin `-text`, git normaliza los finales de línea
   según la plataforma: el fixture sin terminador final ganaría uno y el de
   latin-1 podría corromperse. Es la única parte del repo donde el contenido
   byte a byte importa más que su legibilidad.

2. **Verificación por clone, no por API.** Al revisar que el fixture latin-1
   hubiera llegado intacto, la Contents API de GitHub lo devolvió con `c3 89`
   —el UTF-8 de `É`— en vez de `c9`, el byte latin-1. Parecía corrupción del
   repositorio. No lo era: el objeto git local y el clonado tienen `c9`, y la
   suite completa corre verde desde un clone limpio. La API reencoda el
   contenido no-UTF8 al serializarlo a JSON. Anotado porque cualquiera que
   vuelva a revisar esto por la API va a llegar al mismo susto.

3. **Privado, y "por ahora".** El paquete está escrito como si fuera a
   publicarse en Hex —bloque `package` completo, portada de hexdocs, CHANGELOG
   con candidatos a 0.2— pero el repositorio es privado y exploratorio. Las dos
   cosas no se contradicen: el rigor de publicación era parte del ejercicio, no
   un compromiso de publicar.
