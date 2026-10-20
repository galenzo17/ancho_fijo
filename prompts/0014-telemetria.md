---
prompt: 0014
fecha: 2026-10-20T12:38:30-03:00
autor: Agustín Bereciartúa <bereciartua.agustin@gmail.com>
modelo: claude-fable-5-1
issue: 13
---

# 0014 — Instrumentación con `:telemetry` (issue #13)

**Contexto:** la librería no emitía un solo evento. Cuando el proceso
nocturno se demora el triple no hay forma de saber si fue el I/O, la
transcodificación o el volumen. Y el README promete cero dependencias de
runtime, que es justo lo que `:telemetry` pondría en duda.

## Prompt

El `/loop` que gobierna la serie de issues, sin prompt propio para esta:

> y arma un /loop de cada issue que necesita un pr armalo y que sea senior
> level planifica monitorewa senio senior

## Resultado

- `AnchoFijo.Telemetria`: `span/3` sobre `:telemetry.span/3`, `emitir/3`,
  `instrumentar_stream/2` y `disponible?/0`, con el contrato de todos los
  eventos en el `@moduledoc`.
- `parsear/3` y `detectar/2` envueltos en `span`; `stream/3` instrumentado
  con `Stream.transform/4`, que emite `start` al empezar la enumeración y
  `stop` al terminar o cortarse, con las cuentas en el acumulador.
- `{:telemetry, "~> 1.3", optional: true}` en `mix.exs`; la decisión de
  emitir o no se toma al compilar.
- `Entrada.origen/2` para la metadata `:desde`.
- 15 tests con `:telemetry_test.attach_event_handlers/2`.
- Sección "Observabilidad" y la decisión en "Decisiones y trade-offs" del
  README; grupo "Observabilidad" en hexdocs.

## Decisiones tomadas

1. **Dependencia opcional, con la decisión en tiempo de compilación.** Las
   dos opciones de la issue eran obligatoria (30 KB, ya está en cualquier app
   Phoenix) u `optional: true` con guardas. Se eligió opcional porque la
   promesa de cero dependencias vale sobre todo fuera de Phoenix: scripts,
   `Mix.Task`, `escript`, donde nadie mira un dashboard y cada dependencia es
   fricción. Pero no con `Code.ensure_loaded?/1` en cada llamada: con un `if`
   en el cuerpo del módulo, que corre al compilar, las dos versiones de
   `span/3` y `emitir/3` existen alternativamente y en runtime no hay ningún
   chequeo. El precio es que agregar `:telemetry` después exige recompilar
   `ancho_fijo`, y se dice en la doc.

2. **`:telemetry.span/3` y no el par a mano.** Garantiza el `stop` o el
   `exception` pase lo que pase adentro, mide con el reloj monotónico y
   agrega `telemetry_span_context` para correlacionar. Se usa la forma de
   tres elementos (`{resultado, medidas, metadata}`), que existe desde 1.3,
   para poner `registros`, `errores` y `advertencias` como medidas y no como
   metadata: son números para graficar.

3. **`stream/3` emite por su cuenta, sin `span`.** Un stream no tiene una
   función que envolver: `span` cerraría el `stop` cuando se devuelve el
   stream, antes de leer una sola línea. `Stream.transform/4` con
   `start_fun` y `after_fun` emite `start` cuando empieza la enumeración y
   `stop` cuando termina o se corta (`Enum.take/2`), y las cuentas viajan en
   el acumulador: cuatro enteros y el instante de inicio. No se acumula
   ningún registro y la laziness queda intacta; hay un test con
   `Stream.cycle/1` infinito y `Enum.take/2`. No hay `exception` para el
   stream: lo que puede fallar adentro ya es un diagnóstico, y una excepción
   ahí sería un bug que el llamador ve igual.

4. **Sin evento por línea.** La issue lo dejaba abierto. En un archivo con
   10.000 filas malas serían 10.000 eventos en el handler, y cada uno
   llevaría el diagnóstico, que puede traer datos personales (#8). El
   volumen va en las medidas de `stop`; el detalle de cada error ya está en
   los diagnósticos que la función devuelve, que son datos y no eventos.

5. **Metadata sin datos del archivo.** `layout` es el `:nombre` del layout,
   `desde` es `:archivo`, `:contenido` o `:enumerable`, `modo`, `encoding`,
   `unidad`, `resultado`. Ni la ruta, ni el contenido, ni los diagnósticos
   viajan en los eventos: un handler de telemetría manda a sistemas externos
   y no tiene por qué recibir lo que el log no debería recibir.

6. **`span` también cierra con `:error`.** Un layout inválido o un archivo
   ilegible no son excepciones, son `{:error, diagnosticos}`, y el `stop`
   sale con `resultado: :error` y las cuentas que haya. `exception` queda
   para lo que de verdad levanta, que no debería pasar.
