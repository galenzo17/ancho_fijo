---
prompt: 0030
fecha: 2026-10-21T22:30:00-03:00
autor: Agustín Bereciartúa <bereciartua.agustin@gmail.com>
modelo: claude-fable-5-1
issue: 50
---

# 0030 — Discriminar sin código de tipo (issue #50)

**Contexto:** octava iteración del loop sobre las issues abiertas; la rama
parte de la de #49 (prompt 0029). `Multiregistro` solo sabía discriminar
por un código en posiciones fijas; los formatos cuyo header y trailer se
reconocen por el largo o por ser la primera y la última línea se parseaban
a mano.

## Prompt

> anda a main y revisa luego las issues, arma un /loop cada issue un pr si
> es necesario, senior level ultra mega pro ultrathink

## Resultado

- Tres formas nuevas de `:discriminador`: `[por: :largo]`, `[por:
  :posicion_en_archivo]` (con `ubicacion:` en cada tipo) y `[por: fun]`.
  Cada una con su validación en `nuevo/1` (largos repetidos, ubicaciones
  inválidas o repetidas, mezclas de formas) y sus diagnósticos
  `:estructura` al leer (ningún tipo mide eso, ningún tipo en esa
  ubicación, la función devolvió `nil` o un tipo que no existe).
- Las líneas viajan con una pista de ubicación: `con_ubicacion/2` retiene
  una línea para saber cuál es la última, en `parsear/3` y en `stream/3`.
- `detectar/2` acepta un `Multiregistro` en `layout:` y la tarea Mix
  también: una observación con el criterio, las líneas por tipo, las sin
  tipo y las que no miden lo de su tipo; y el veredicto de ancho fijo deja
  de depender de que todas las líneas midan lo mismo.
- Fixture `nomina_sin_codigo.txt` (header de 32, detalles de 40, trailer de
  20) y `multiregistro_sin_codigo.exs`; tests de las tres formas, del
  stream lazy con anticipación, de la identidad y del detector.

## Decisiones tomadas

1. **La última línea se reconoce con una línea de anticipación.** Un
   stream no sabe que una línea es la última hasta que no llega otra. La
   alternativa era leer todo o exigir una ruta; retener una línea cuesta
   una línea de memoria y mantiene `stream/3` lazy.
2. **Un archivo de una sola línea es la primera, no la última.** Si hay
   tipo `:primera`, esa línea lo es, y `:ultima` queda faltante al cierre;
   un header solo es un archivo truncado, no un trailer solo.
3. **El veredicto del detector cambia con un multiregistro.** "Tres largos
   distintos" era la señal de archivo sospechoso; con un multiregistro que
   le da tipo a cada línea, es la definición del formato. El veredicto pasa
   a ser "cada línea tiene tipo y mide lo que su tipo declara", y la
   observación de largos deja de hablar de filas sospechosas.
4. **La función es el último recurso, y la doc lo dice.** No se puede
   serializar (lo que importa para #57) ni contrastar: el detector cuenta
   lo que devuelve y lo advierte en la observación.
