---
prompt: 0033
fecha: 2026-10-21T19:33:10-03:00
autor: Agustín Bereciartúa <bereciartua.agustin@gmail.com>
modelo: claude-fable-5-1
issue: 54
---

# 0033 — Escribir un Multiregistro con los controles calculados (issue #54)

**Contexto:** undécima iteración del loop sobre las issues abiertas; la
rama parte de la de #52 (prompt 0032). `escribir/3` recibía solo un
`Layout`: para un archivo con header, detalles y trailer había que escribir
cada tipo por separado y armar el trailer a mano, y la librería recién
validaba los totales si uno volvía a parsear lo escrito.

## Prompt

> anda a main y revisa luego las issues, arma un /loop cada issue un pr si
> es necesario, senior level ultra mega pro ultrathink

## Resultado

- `Multiregistro.escribir/3` y el despacho en `AnchoFijo.escribir/3`: dos
  pasadas, la primera tipa cada registro, verifica la estructura con el
  mismo `avanzar/5` de la lectura y acumula cuentas y sumas; la segunda
  escribe cada línea con `Escritor.escribir_linea/4`, con los controles
  puestos en los registros que los declaran, o verificados si vienen.
- `agrupar_por:` en los controles, en lectura y escritura: las sumas se
  llevan por `{clave, grupo}` y el registro de control se compara con su
  grupo.
- Sumas e igualdad sobre `Monto` y `Decimal`, además de enteros y tuplas.
- `Escritor.stream/3` con un multiregistro levanta `ArgumentError` con la
  razón. Telemetría `escribir` con el nombre del multiregistro.
- Tests: round-trip byte a byte de la fixture, controles calculados y
  declarados mal, estructura, mapas por literal, un trailer por moneda,
  sumas sobre `Monto` y sobre `Decimal`.

## Decisiones tomadas

1. **Sin versión lazy, y dicho con un `ArgumentError`.** Una
   implementación que acumule "lo visto hasta ahora" daría trailers
   correctos solo cuando el trailer es el último registro, y silenciosa
   cuando no; es preferible no ofrecerla.
2. **El control declarado distinto es error, el ausente se calcula.** Es
   lo que pidió la issue y lo que evita el bug silencioso: quien manda el
   trailer armado a mano se entera si no cuadra.
3. **La estructura se verifica al escribir con el mismo código que al
   leer.** Un archivo sin trailer obligatorio no se escribe, para que lo
   escrito siempre se pueda leer sin diagnósticos.
4. **`agrupar_por` cambió la forma del acumulador también en la lectura**
   (sumas por `{clave, grupo}`, creadas al aparecer el primer registro).
   Antes un control sobre un campo con `moneda:` tampoco cuadraba nunca,
   porque `sumar/2` no sabía de `Monto`; quedó resuelto de paso y con test.
