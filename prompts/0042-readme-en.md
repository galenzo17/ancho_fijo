---
prompt: 0042
fecha: 2026-10-21T22:10:00-03:00
autor: Agustín Bereciartúa <bereciartua.agustin@gmail.com>
modelo: claude-fable-5-1
issue: 53
---

# 0042 — Guía en inglés, glosario y la decisión sobre el idioma de la API (issue #53)

**Contexto:** vigésima y última iteración del loop sobre las issues abiertas;
la rama parte de la de #62 (prompt 0041). La API, las opciones y los
diagnósticos son en español por decisión; la objeción de quien evalúa el
paquete desde una base de código en inglés no es "no entiendo español" sino
"no quiero mezclar `Layout.nuevo!` con el resto de mi código". El issue pide
la opción 2 de su análisis (documentación bilingüe) ahora, y dejar escrito el
criterio para la opción 4 (un paquete hermano en inglés).

## Prompt

> anda a main y revisa luego las issues, arma un /loop cada issue un pr si
> es necesario, senior level ultra mega pro ultrathink

## Resultado

- `README.en.md`: la guía completa en inglés, sección por sección la misma
  que la española (detectar, parsear, los dos modos, `!`, archivos grandes,
  escribir, bytes y caracteres, relleno recortado, multiregistro, layout como
  datos, documentar, formatos incluidos, tipos, Decimal, tipos propios,
  reglas, pruebas, validación del layout, grupos y variantes, encodings por
  campo, diagnósticos para el usuario, datos personales, trazabilidad,
  observabilidad, idempotencia, decisiones). El código es el mismo; las
  salidas en español se citan tal cual con su traducción al lado. La tabla de
  `documentar/2` va en inglés (`--idioma en`), generada.
- Glosario español → inglés de funciones, opciones, tipos, valores de las
  opciones y diagnósticos, el mismo bloque en los dos README.
- "Decisiones y trade-offs" explica por qué la API es en español, las cuatro
  opciones que se pesaron y el criterio escrito para el paquete hermano: la
  fachada existe cuando hay un proyecto que la necesita, no antes.
- `mix docs` publica la guía como "English guide" y el paquete de Hex la
  incluye.
- Test `readme_en_test.exs`: los dos glosarios son el mismo, la tabla en
  inglés es la que genera `documentar/2`, y las dos guías tienen la misma
  cantidad de secciones principales y la inglesa nombra las funciones
  centrales.

## Decisiones tomadas

- La guía en inglés traduce la prosa y conserva las salidas de la librería
  en español, con la traducción entre paréntesis cuando hace falta: lo que
  el lector va a ver en su terminal es lo que está en el README, no una
  versión que no existe.
- El glosario vive una vez por README y un test los compara línea a línea:
  dos tablas mantenidas a mano divergen igual que la especificación y el
  layout.
- No se agregó una fachada ni alias en inglés: el issue lo descarta con
  razones y el README las repite para que no vuelva como pedido.
