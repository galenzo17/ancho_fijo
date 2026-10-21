---
prompt: 0034
fecha: 2026-10-21T19:39:49-03:00
autor: Agustín Bereciartúa <bereciartua.agustin@gmail.com>
modelo: claude-fable-5-1
issue: 55
---

# 0034 — Diagnósticos para el usuario final (issue #55)

**Contexto:** duodécima iteración del loop sobre las issues abiertas; la
rama parte de la de #54 (prompt 0033). Los diagnósticos estaban pensados
para el desarrollador; una pantalla de carga y una API necesitaban otra
cosa, y cada consumidor escribía su traductor del struct.

## Prompt

> anda a main y revisa luego las issues, arma un /loop cada issue un pr si
> es necesario, senior level ultra mega pro ultrathink

## Resultado

- `mensaje/2` con `idioma: :es | :en` y `audiencia: :desarrollador |
  :usuario`: el marco (línea, campo, posiciones, "se esperaba/llegó") y la
  explicación por tipo (`explicacion/2`) traducidos; para el usuario, sin
  la causa probable y sin los dos puntos de los átomos.
- `a_mapa/2` y `desde_mapa/1`, con claves átomo o string, `posicion` como
  lista para JSON, y `String.to_existing_atom/1` para no crear átomos desde
  un JSON ajeno. `Jason.Encoder` opcional, decidido al compilar.
- `resumen/2` (y `AnchoFijo.resumen/2`): totales, líneas afectadas,
  veredicto y texto en el idioma pedido.
- Tests y doctests con el mismo diagnóstico en los dos idiomas y las dos
  audiencias, el round-trip del mapa y del JSON con un campo sensible.

## Decisiones tomadas

1. **El inglés traduce el marco y la explicación por tipo, no el detalle.**
   `esperado` y `recibido` los redacta cada tipo en español y son decenas
   de frases; traducirlas exigiría un catálogo paralelo que esta issue no
   pide y que #53 deja como pregunta abierta. Está documentado con el
   ejemplo mixto a la vista, para no prometer más de lo que hay.
2. **Para el usuario no va la causa probable.** Habla de opciones del
   layout ("declare opcional: true"): es para quien integra.
3. **`desde_mapa/1` no crea átomos.** Un campo que no existe como átomo
   queda como string: un JSON que llega de afuera no debería poder agotar
   la tabla de átomos.
4. **El veredicto es binario sobre los errores.** Un error rechaza; solo
   advertencias acepta con observaciones. Qué hacer después es del
   sistema que carga el archivo, no de la librería.
