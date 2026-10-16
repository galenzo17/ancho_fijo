---
prompt: 0009
fecha: 2026-10-16T19:00:00-03:00
autor: Agustin Bereciartua <bereciartua.agustin@gmail.com>
modelo: claude-fable-5-1
issue: 9
---

# 0009 — Moneda y escala (issue #9)

**Contexto:** un `:decimal` devolvía `{unidades, precision}` con la
precisión declarada a mano en el layout. Un monto en pesos chilenos leído
con `precision: 2` divide todo por cien y nadie se entera hasta la
conciliación; y `{unidades, precision}` sin moneda deja sumar CLP con USD
sin que nada se queje.

## Prompt

El `/loop` que gobierna la serie de issues, sin prompt propio para esta:

> y arma un /loop de cada issue que necesita un pr armalo y que sea senior
> level planifica monitorewa senio senior

## Resultado

- Opción `moneda:` en campos `:decimal`. Con ella, la `:precision` se toma de
  la escala ISO 4217 y declararla distinta es un layout inválido con un
  mensaje que nombra la escala y explica el daño.
- `AnchoFijo.Monto`: struct `{unidades, precision, moneda}` con `nuevo/2,3`,
  `cero/1`, `sumar/2`, `sumar!/2`, `restar/2`, `negar/1`, `total/1,2`,
  `formatear/2`, `a_decimal/1`, `escala/1`, `monedas/0`, `Inspect` y
  `String.Chars`. Tabla ISO 4217 acotada.
- Diagnóstico tipo `:moneda` para operaciones entre montos incompatibles.
- `Decimal` como dependencia opcional.
- `monto_test.exs` con 12 tests y 3 propiedades; fila en la tabla de tipos
  del README y párrafo en "Decisiones y trade-offs".

## Decisiones tomadas

1. **Struct solo con `moneda:`; sin ella, la tupla de siempre.** Era la
   decisión de la issue, con tres opciones. Seguir con la tupla y solo
   validar no resuelve el segundo problema (sumar monedas distintas). La
   tupla de tres rompe todo el pattern matching publicado en Hex. El struct
   siempre rompe igual. La salida: el struct aparece solo cuando el layout
   declara la moneda. Quien no la declara no cambia una línea; quien la
   declara pidió a propósito un valor que sabe de qué moneda es. No es una
   versión mayor.

2. **La escala la manda la moneda, y un desacuerdo es error, no
   advertencia.** La issue preguntaba. Una advertencia se ignora y el daño
   es exactamente el que la issue describe. Si un archivo trae USD con
   cuatro decimales de verdad, no es USD a efectos de la lectura: se lee sin
   `moneda:` y se convierte después. El mensaje lo dice.

3. **Moneda fuera de la tabla: con `:precision`, advertencia; sin ella,
   error.** La tabla es acotada a propósito (todas las de escala distinta de
   dos, más la región y las de reserva); una moneda que falta no debería
   impedir leer el archivo si el layout dice la escala. Lo que no se puede
   es inventarla. La advertencia va en `layout.advertencias`, junto a los
   huecos, que es donde viven las cosas que no impiden parsear.

4. **Sumar monedas distintas es un diagnóstico, no una excepción.** La issue
   pedía "diagnóstico, no excepción críptica". `sumar/2` devuelve
   `{:error, %Diagnostico{tipo: :moneda}}` con el mensaje "llegó CLP y USD";
   `sumar!/2` levanta `AnchoFijo.Error` para quien prefiera. La misma moneda
   con escalas distintas también es error: uno de los dos montos se
   construyó mal.

5. **`a_decimal/1` y la dependencia opcional.** `Decimal` entra como
   `optional: true` solo para esa función, con `@compile {:no_warn_undefined,
   Decimal}` y un chequeo en runtime que levanta `ArgumentError` si no está.
   La librería no suma con `Decimal` porque no lo necesita: unidades
   enteras más escala es aritmética exacta.

6. **`formatear/2` con separadores de la región por default.** Punto de
   miles, coma decimal, código ISO después del número: `1.250,00 USD`. Las
   tres cosas son opciones. No es `i18n`; es presentación razonable para
   quien lee una nómina chilena.

7. **Tres propiedades, no una.** La issue pedía "ninguna operación introduce
   un float". Se verifica que `sumar` y `restar` son exactas sobre enteros y
   coinciden con `Decimal`, que `formatear` es reversible dígito a dígito,
   y que un decimal con moneda parseado vuelve a sus unidades sin perder
   nada.
