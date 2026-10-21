---
prompt: 0036
fecha: 2026-10-22T01:30:00-03:00
autor: Agustín Bereciartúa <bereciartua.agustin@gmail.com>
modelo: claude-fable-5-1
issue: 57
---

# 0036 — Layouts como datos (issue #57)

**Contexto:** decimocuarta iteración del loop sobre las issues abiertas; la
rama parte de la de #56 (prompt 0035). Un layout era código Elixir: no se
podía compartir con otro lenguaje, guardar como dato ni dejar que lo edite
alguien que no programa.

## Prompt

> anda a main y revisa luego las issues, arma un /loop cada issue un pr si
> es necesario, senior level ultra mega pro ultrathink

## Resultado

- `AnchoFijo.Serializacion` (sin doc) con la conversión en los dos
  sentidos, y las públicas `Layout.a_mapa/1`, `desde_mapa/1`, `a_json/1`,
  `desde_json/1` y las mismas en `Multiregistro`. El mapa lleva
  `"version" => 1`, solo lo declarado (lo que difiere del default del
  struct), los tipos internos por nombre y los propios por módulo, los
  formatos de fecha con nombre como string y los patrones tal cual.
- `AnchoFijo.Json.decodificar/1`: un decodificador JSON completo y chico,
  para no sumar una dependencia; probado contra lo que Jason codifica.
- `Mix.Tasks.AnchoFijo.Carga` lee `.json` además de `.exs`.
- `priv/layout.schema.json` (draft-07) en el paquete; un test verifica que
  cubra todas las claves que `a_mapa/1` produce.
- Round-trip para todos los layouts de los fixtures, NACHA, el
  multiregistro sin código y uno por posición con controles agrupados.

## Decisiones tomadas

1. **El mapa lleva lo declarado, no el struct entero.** La posición va
   siempre (explícita, para que un lector sin el encadenamiento lo lea
   igual); el módulo resuelto y las opciones derivadas no. Lo que difiere
   del default del struct es el criterio, y el round-trip lo prueba.
2. **Los nombres de campo y de tipo crean átomos; los tipos propios no.**
   Un layout es configuración, no datos del archivo: crear el átomo de un
   campo es lo correcto. Un módulo se resuelve con `String.to_existing_atom/1`:
   un JSON ajeno no debería poder crear módulos fantasma, y uno que no
   existe queda como string para que `Campo.nuevo/1` lo reclame.
3. **JSON en el núcleo, YAML afuera.** El decodificador son cien líneas y
   evita la primera dependencia de runtime; YAML necesita una librería y el
   README dice cómo enchufarla, porque el mapa es el mismo.
4. **Una función no se serializa, y `a_mapa/1` lo dice con `ArgumentError`.**
   Guardar `"por" => "funcion"` sería un dato que nadie puede volver a leer.
