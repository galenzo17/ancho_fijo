---
prompt: 0005
fecha: 2026-09-15T17:36:41-03:00
autor: Agustin Bereciartua <bereciartua.agustin@gmail.com>
modelo: claude-fable-5-1
issue: 3
---

# 0005 — Relleno final tolerado (issue #3)

**Fecha:** 2026-09-15
**Contexto:** primera de las 17 issues abiertas el 2026-09-01 como plan de
práctica. La rama `relleno-final-tolerado` ya traía, de una sesión anterior
cuyo prompt no quedó registrado, la opción de layout, la rama del parser, los
diagnósticos y los tests, con un `TODO(human)` en `zona_tolerable/1`: la
política de cuánto del final de la línea es relleno reponible.

## Prompt

Primero, al abrir la sesión:

> anda a main y pull, revisa las issues, cuantas son pr code?

Y después, como `/loop` sin intervalo, el prompt que gobierna esta issue y las
que siguen:

> y cada una un pr, bien explicado, bien paso a paso, la meta es entender
> aprender a full, respeta guardar los promp de cada issues, senior level

## Resultado

- `relleno_final: :estricto | :tolerar` en `AnchoFijo.Layout`, validado como
  las demás opciones globales. Default `:estricto`: sin la opción nada cambia.
- En `AnchoFijo.Parser`, `ajustar_largo/3` gana una tercera rama: línea corta
  con la opción activa pasa a `completar_relleno/4`, que consulta
  `zona_tolerable/1` y o completa la línea con una advertencia
  `:relleno_completado`, o falla con un `:largo_de_linea` cuya causa dice
  cuántas unidades faltaban y cuántas eran reponibles.
- `zona_tolerable/1`: relleno no declarado más campos `:texto` de atrás hacia
  adelante, mientras compartan el carácter de relleno. Ver decisiones.
- Fixture `test/fixtures/nomina_glosa_recortada.txt`, reproducible con
  `mix run test/fixtures/generar.exs`. Layout `layout_glosa/1` en
  `test/support/fixtures.ex`.
- Sección "Líneas cortas por relleno recortado" en el README, con el caso
  `unidad: :caracteres`. Entrada en el CHANGELOG y salida de la lista de
  candidatos a 0.2.
- Suite: 234 verdes, credo estricto y dialyzer limpios.

## Decisiones tomadas

1. **La política la escribió el modelo, no la persona.** El `TODO(human)` en
   `zona_tolerable/1` estaba pensado como ejercicio y quedó sin respuesta
   durante la ventana del loop. Se resolvió para no frenar el resto de las
   issues, y se deja constancia acá para que no pase por decisión revisada.

2. **Solo campos `:texto`, y sin mirar su `:trim`.** El argumento no es que el
   relleno "no sea dato": es probabilístico. Un emisor que recorta espacios
   finales produce una línea corta exactamente cuando el original terminaba en
   relleno, y reponerlo reconstruye el original byte a byte, cualquiera sea el
   `:trim`. En un `:entero`, `:decimal` o `:fecha`, en cambio, el final de la
   línea son dígitos: si faltan, la explicación más probable es un dato
   truncado, y completar con espacios lo taparía. La opción tolera relleno
   faltante, no bytes faltantes.

3. **Un `:texto` que queda entero en blanco sí cuenta como relleno.** Con
   `:opcional` se lee `nil`, sin él `""`; es lo mismo que habría dado la línea
   completa. Excluirlo obligaría al emisor a mandar al menos un carácter en un
   campo vacío, que es justo lo que no hace.

4. **La zona es un solo carácter repetido.** Se detiene cuando el `:relleno`
   del campo cambia, porque `String.duplicate/2` no puede reponer un tramo con
   dos rellenos distintos. El relleno no declarado al final del layout se
   repone con espacio y fija el carácter para los campos que vengan detrás.

5. **Con `unidad: :bytes`, solo relleno ASCII.** En ese modo la línea todavía
   está en su encoding original y el faltante se mide en bytes: un `"·"` de dos
   bytes en UTF-8 y uno en latin-1 repetido `faltan` veces no reconstruye nada
   que se pueda contar. El campo con ese relleno corta la zona. Con
   `:caracteres` la línea ya es UTF-8 y cualquier carácter sirve.

6. **`unidad: :caracteres` cuenta caracteres.** La medida y el faltante usan
   `String.length/1` porque la línea se completa después de transcodificar.
   `"JOSÉ MUÑOZ"` en una glosa de 12 se completa con 2 caracteres; contar bytes
   habría dicho que no faltaba nada.

7. **El error conserva el tipo `:largo_de_linea`.** Cuando la opción está
   activa pero el faltante no es reponible, cambia la causa probable, no el
   tipo: código llamador que ya distingue por `tipo` no se rompe. La
   advertencia sí es un tipo nuevo, `:relleno_completado`, porque es una
   situación nueva.

8. **El fixture entra al generador.** `generar.exs` lo reproduce byte a byte:
   el `.gitattributes` protege los fixtures de la normalización de git, pero
   el generador es la única forma de saber cómo se construyeron.

9. **Los huecos entre campos también son reponibles.** Lo señaló la revisión
   automática del PR y es correcto: un layout con posiciones explícitas puede
   dejar posiciones sin declarar entre dos campos, y nadie las lee, igual que
   el relleno después del último campo. La zona los suma al pasar de un campo
   al anterior, y solo un campo con dato la cierra. Un hueco no fija el
   carácter de relleno: se completa con el que tenga la zona.

10. **Lo que la revisión pidió y no se hizo.** El mismo revisor pidió completar
    solo cuando haya "evidencia" de que el sufijo faltante es relleno y no
    dato. Esa evidencia no existe: una línea corta no trae los bytes que le
    faltan, y `"PA"` recortado de `"PA    "` es indistinguible de `"PA"`
    truncado de `"PABCDE"`. Por eso la opción es opt-in, por eso solo aplica a
    `:texto`, y por eso cada línea completada deja una advertencia. Es el
    trade-off que la issue pedía y está escrito en el README.
