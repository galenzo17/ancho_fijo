---
prompt: 0037
fecha: 2026-10-21T20:13:41-03:00
autor: Agustín Bereciartúa <bereciartua.agustin@gmail.com>
modelo: claude-fable-5-1
issue: 58
---

# 0037 — `AnchoFijo.Test`: aserciones y generadores para los consumidores (issue #58)

**Contexto:** decimoquinta iteración del loop sobre las issues abiertas; la
rama parte de la de #57 (prompt 0036). Quien adopta la librería escribía
siempre los mismos tests, y la propiedad que importa (escribir y volver a
leer) nadie la probaba porque armar generadores por tipo es trabajo.

## Prompt

> anda a main y revisa luego las issues, arma un /loop cada issue un pr si
> es necesario, senior level ultra mega pro ultrathink

## Resultado

- `AnchoFijo.Test` (en `lib/`, solo depende de ExUnit): `assert_parsea/4`,
  `assert_diagnostico/2` con filtros por tipo, gravedad, campo, línea y
  texto (string o regex) en causa, esperado o recibido, `assert_round_trip/3`
  para layouts y multiregistros, y `assert_escribe/4`. Los fallos levantan
  `ExUnit.AssertionError` con los diagnósticos ya redactados.
- `AnchoFijo.Test.Generadores`, definido solo con `StreamData` cargado:
  `registro/1` por campo (texto solo con letras, enteros y decimales en el
  rango del largo y del signo, fechas en la ventana del pivote, RUT con
  dígito verificador, opcionales con `nil`, constantes, sin rellenos),
  `linea/1` y `linea_invalida/1`. Para un multiregistro, la lista por
  cantidad de cada tipo, sin los campos de control, y cada registro vuelto
  a leer después de ponerle el código de tipo.
- Callback opcional `generador/1` en `AnchoFijo.Tipo`; `TipoHora` lo
  implementa en los tests.
- Propiedades en la suite: round-trip para los layouts de los fixtures, un
  layout con todas las opciones, NACHA, el multiregistro sin código y uno
  por posición; y la línea rota diagnosticada en su campo.

## Decisiones tomadas

1. **Funciones y no macros.** `assert_parsea/4` es una función que levanta
   `ExUnit.AssertionError`: se importa, se lee y se depura como cualquier
   otra, y no necesita que la librería dependa de ExUnit en tiempo de
   compilación más de lo que ya hace Elixir.
2. **El registro de un multiregistro se genera releyendo la línea.** Los
   campos que cubre el discriminador (en NACHA, el tipo de registro y el
   primer carácter del campo siguiente) no se pueden generar al azar; se
   escribe la línea, se le pone el código y se vuelve a leer, así el
   registro generado es exactamente lo que el archivo diría.
3. **Un tipo propio sin `generador/1` es un `ArgumentError` con el campo**,
   no un valor inventado: inventar un valor para un tipo desconocido es
   justo lo que la librería no hace.
4. **Texto solo con letras.** Un dígito o un espacio en un texto chocan
   con el relleno o con el trim y rompen el round-trip sin que sea un bug;
   el generador evita el falso positivo en vez de documentarlo.
