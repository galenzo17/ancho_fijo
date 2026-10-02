---
prompt: 0006
fecha: 2026-09-15T18:15:20-03:00
autor: Agustin Bereciartua <bereciartua.agustin@gmail.com>
modelo: claude-fable-5-1
issue: 4
---

# 0006 — Signo al final del campo (issue #4)

**Fecha:** 2026-09-15
**Contexto:** segunda issue del plan de práctica, la que sigue a `0005`. El
CHANGELOG la tenía como candidata a 0.2: los formatos heredados de mainframe
escriben el negativo con el signo después de los dígitos, `0125000-`.

## Prompt

El mismo `/loop` que gobierna toda la serie, sin prompt nuevo para esta issue:

> y cada una un pr, bien explicado, bien paso a paso, la meta es entender
> aprender a full, respeta guardar los promp de cada issues, senior level

## Resultado

- Opción `signo: :inicial | :final` en `AnchoFijo.Campo`, válida solo en
  `:entero` y `:decimal`. Default `:inicial`: nada cambia sin declararla.
- `:entero` y `:decimal` pasan por la misma `separar_signo/2`. Antes `:entero`
  usaba `Integer.parse/1` y `:decimal` su propio `separar_signo/1`.
- Un signo en el extremo que el layout no declara produce un diagnóstico con
  `esperado` que muestra la forma correcta y una causa que dice qué declarar.
- Los generadores de los tests de propiedades producen enteros y decimales
  negativos, con el signo adelante o atrás, y el positivo de mainframe con
  espacio al final. El round-trip cubre las dos formas.
- Fila `:signo` en la tabla de tipos del README, párrafo con el ejemplo, y
  entrada en el CHANGELOG. La entrada sale de los candidatos a 0.2.
- Suite: 231 verdes, credo estricto y dialyzer limpios.

## Decisiones tomadas

1. **La cláusula `:final` la escribió el modelo.** Igual que en `0005`: el
   `TODO(human)` con la tabla de casos borde quedó sin respuesta en la ventana
   del loop y se resolvió para no frenar la serie.

2. **El criterio de aceptación de la issue estaba mal.** Pedía que `0001250-`
   con `precision: 2` diera `{-125000, 2}`. Con separador implícito el campo
   ya viene en unidades mínimas, y eso da `{-1250, 2}`, es decir -12,50.
   Escalar otra vez multiplicaría los montos por cien. Se mantuvo la semántica
   de la librería y el ejemplo pasó a ser `0125000-`.

3. **Sin signo es positivo.** El formato de mainframe escribe el positivo como
   `0125000 ` y `limpiar/2` ya se comió el espacio. Rechazar el campo sin
   signo rompería casi todos los archivos reales.

4. **El `+` explícito se acepta** en los dos extremos. Algunos emisores lo
   mandan y rechazarlo no protege de nada.

5. **El signo en el extremo equivocado es un diagnóstico propio**, no
   "caracteres no numéricos". Un archivo con `-0125000` cuando el layout dice
   `:final` no está corrupto: es de otro formato. La causa dice qué opción
   declarar, en las dos direcciones.

6. **Signo duplicado y signo sin dígitos** tienen causa propia. `-001250-` y
   `1250--` no son valor basura ni un `Integer.parse` a medias.

7. **`:entero` quedó más estricto.** `Integer.parse/1` aceptaba cosas que
   `solo_digitos?/1` no. Ningún test existente dependía de eso y la
   uniformidad entre `:entero` y `:decimal` vale más que la permisividad.

8. **`validar_opciones_ajenas/2` pasó de un dueño a una lista.** `:signo` es
   la primera opción con dos tipos dueños. La generalización se hizo recién
   cuando apareció el segundo caso.

9. **Overpunch EBCDIC queda fuera.** `12K` por -123 es otro alfabeto, no otra
   posición del signo, y la issue lo dejaba como bonus. Anotado en el README.
