---
prompt: 0019
fecha: 2026-10-16T19:38:38-03:00
autor: Agustín Bereciartúa <bereciartua.agustin@gmail.com>
modelo: claude-fable-5-1
issue: 1
---

# 0019 — Header, detalle y trailer (issue #1)

**Contexto:** era el primer candidato a 0.2 del CHANGELOG y lo que más
piden las cartolas y nóminas reales: un layout por tipo de registro,
discriminado por el contenido de un campo, con el trailer cuadrando contra
los detalles.

## Prompt

El `/loop` que gobierna la serie de issues, sin prompt propio para esta:

> y arma un /loop de cada issue que necesita un pr armalo y que sea senior
> level planifica monitorewa senio senior

## Resultado

- `AnchoFijo.Multiregistro` con `nuevo/1`, `nuevo!/1`, `parsear/3`,
  `stream/3` y `agrupar/2`. Discriminador por posición y largo, registros
  en el orden esperado con `:valor`, `:layout` y `:cantidad`, y controles
  `cuenta:` y `suma:`.
- `AnchoFijo.parsear/3` y `stream/3` aceptan un `%Multiregistro{}` en lugar
  del layout.
- Diagnósticos `:estructura` y `:control`.
- Fixture `nomina_multiregistro.txt` (header de 40, detalles de 50 y
  trailer de 24, con RUT válidos) generado por `generar.exs`.
- 18 tests en `multiregistro_test.exs`. Sección en el README.

## Decisiones tomadas

1. **Lista ordenada de `{tipo, mapa}`, no mapa por tipo.** El orden es
   parte del dato: hay formatos que intercalan tipos (NACHA agrupa detalles
   por lote), y un mapa por tipo lo pierde. Además es lo único que
   `stream/3` puede emitir de a uno. `agrupar/2` arma el mapa por tipo para
   la nómina común, con los de cantidad `:uno` u `:opcional` como mapa o
   `nil` y el resto como lista.

2. **El orden es el de `:registros`, y las cantidades son cuatro.** Un
   tipo puede aparecer en su lugar o más adelante; uno anterior está fuera
   de orden. `:uno` y `:opcional` admiten una aparición; `:uno` y
   `:al_menos_uno` tienen que aparecer, y eso se verifica al final. No hay
   una opción `:orden` aparte: la keyword list ya es una secuencia, y
   declararla dos veces es pedir que se desincronice.

3. **Estructura al pasar, controles al final.** Era lo que la issue pedía
   decidir para `stream/3`. Los controles necesitan todos los detalles, así
   que se comparan cuando se acaba el archivo; en el stream, como un último
   elemento `{:error, diagnosticos}` que sale con `Stream.transform/5` (el
   `last_fun`, Elixir 1.14) solo si algo no cuadra. El acumulador lleva en
   qué tipo va el orden, cuántos de cada tipo, las sumas y lo que el
   trailer declaró. Nunca los registros.

4. **En tolerante, los controles se calculan sobre lo que se leyó.** Un
   detalle ilegible produce dos diagnósticos: el suyo y el del total que ya
   no cuadra. Se consideró descontar el error para no "duplicar", y se
   descartó: los dos son ciertos, el segundo es el que el banco va a
   reportar, y el mensaje del control dice "si hubo líneas ilegibles, la
   cuenta las excluye" para que nadie se confunda.

5. **Sumas sobre enteros o `{unidades, precision}`, nunca floats.** Con
   precisiones distintas se escala a la mayor y se compara. Un acumulador
   vacío (ningún detalle) es `nil`, y el trailer tiene que declarar cero en
   la forma que sea (`0` o `{0, p}`).

6. **El discriminador se lee en bytes de la línea cruda.** Antes de saber
   qué layout aplica no hay encoding ni unidad; las primeras posiciones son
   ASCII en todo formato real. Una línea más corta que el discriminador es
   un diagnóstico `:estructura` propio.

7. **Cada tipo tiene su largo.** El header mide 40, el detalle 50 y el
   trailer 24, como en la vida real; `Parser.parsear_linea/3` valida el
   largo del layout que corresponde a cada línea.

8. **Escribir multiregistro queda para después.** La escritura (#2) llegó
   en paralelo; combinarlas es un `Escritor.escribir/3` que acepte
   `{tipo, mapa}` y elija el layout por tipo, y vale un PR propio cuando las
   dos estén en `main`.
