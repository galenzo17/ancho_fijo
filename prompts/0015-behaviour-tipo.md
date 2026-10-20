---
prompt: 0015
fecha: 2026-10-20T12:40:04-03:00
autor: Agustín Bereciartúa <bereciartua.agustin@gmail.com>
modelo: claude-fable-5-1
issue: 12
---

# 0015 — Behaviour `AnchoFijo.Tipo` (issue #12)

**Contexto:** los tipos de campo eran un `case` cerrado en `Campo.convertir/3`
sobre cinco átomos, con la validación de opciones por tipo en el mismo
módulo. Cada tipo nuevo era un cambio en el core y una release, y un tipo
que solo tiene sentido para un usuario no tenía dónde vivir. La issue decía
que `:rut` debía implementarse sobre este mecanismo; llegó antes (#5), así
que el test de diseño fue al revés: reescribirlo sobre el behaviour sin que
un solo test cambiara.

## Prompt

El `/loop` que gobierna la serie de issues, sin prompt propio para esta:

> y arma un /loop de cada issue que necesita un pr armalo y que sea senior
> level planifica monitorewa senio senior

## Resultado

- `AnchoFijo.Tipo`: behaviour con `opciones/0`, `validar/1`, `leer/3` y el
  opcional `escribir/2`; `resolver/1`; helpers `diagnostico/3`, `vacio/2`,
  `falla/4`, `solo_digitos?/1`. El `@moduledoc` trae un tipo completo.
- `AnchoFijo.Tipo.Texto`, `.Entero`, `.Decimal`, `.Fecha`, `.Rut`, con la
  lógica movida tal cual desde `Campo`; `Tipo.Signo` (interno) compartido
  por los dos numéricos.
- `Campo` gana `:modulo` (el tipo resuelto) y `:opciones` (las propias de un
  tipo externo); `Campo.texto?/1`. `convertir/3` es una línea:
  `modulo.leer/3`.
- `AnchoFijo.TipoHora` en `test/support/`: HHMM o HHMMSS con `segundos: true`,
  leído como `Time`. 14 tests en `tipo_test.exs`.
- Sección "Tipos propios" en el README.

## Decisiones tomadas

1. **Tres callbacks, no uno.** La issue proponía `leer/3` y
   `validar_opciones/1`. Hizo falta un tercero, `opciones/0`, al reescribir
   los internos: sin saber qué opciones son de quién no se puede decir que
   `precision: 2` en un `:texto` es ajena, ni que `precison: 2` no es de
   nadie. Con él, la validación de opciones ajenas y desconocidas es
   genérica y los tipos propios la heredan. `validar/1` recibe el campo
   entero (no solo las opciones) porque `:fecha` necesita el `:largo`.

2. **Las opciones de los internos siguen en el struct; las propias van en
   `:opciones`.** `campo.precision` y `campo.formato` tienen tests, doctests
   y usuarios; moverlas a un mapa habría roto `Campo` por una pureza que no
   compra nada. Un tipo propio no puede agregar campos al struct, así que sus
   opciones viven en `campo.opciones`. Es asimétrico y está dicho en la doc.

3. **`campo.tipo` conserva lo declarado; `campo.modulo` es lo resuelto.**
   `tipo: :entero` sigue siendo `:entero` en el struct (hay un doctest que
   lo muestra y mensajes que lo nombran), y `modulo` es `Tipo.Entero`. Un
   módulo declarado directamente queda en los dos.

4. **Se verifica al construir el layout, con `Code.ensure_loaded?/1`.** Era
   la decisión abierta. En runtime, línea por línea, sería tarde y caro. Y
   `function_exported?/3` a secas miente en un release: los módulos se
   cargan cuando se usan, y un tipo válido que nadie llamó todavía daría
   `false`. Los tres mensajes son distintos: el átomo que no es tipo lista
   los tipos; el módulo que no existe lo dice; el que existe pero no
   implementa, nombra los tres callbacks.

5. **El blanco con `:opcional` se resuelve antes del tipo.** Para todos los
   tipos, un campo en blanco con `opcional: true` es `nil`; eso no es del
   tipo, es del campo. Sin `:opcional`, el `""` llega a `leer/3` y el tipo
   decide: `:texto` devuelve `""` (una glosa vacía es una glosa), los demás
   usan `Tipo.vacio/2`. `:fecha` además trata los ceros como blanco, y eso
   sí es del tipo.

6. **El recorte no es un callback.** `:texto` tiene `:trim` y `:relleno`;
   los demás reciben `String.trim/1`. Un callback `limpiar/2` habría sido un
   cuarto punto de extensión para un caso que no apareció. Si aparece, se
   agrega como opcional sin romper nada.

7. **Los tests pasan sin cambios.** Era el criterio de la issue y el test
   real del refactor. Hubo que conservar hasta el texto de los diagnósticos
   de opciones ajenas (`:signo solo en campos :entero o :decimal`), que ahora
   se arma preguntándole a cada tipo interno sus opciones, en el orden de la
   documentación.

8. **`escribir/2` queda declarado y opcional.** Para #2. Declararlo ahora
   cuesta una línea y evita que el behaviour cambie cuando llegue la
   escritura.
