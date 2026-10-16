---
prompt: 0009
fecha: 2026-10-16T18:35:15-03:00
autor: Agustín Bereciartúa <bereciartua.agustin@gmail.com>
modelo: claude-fable-5-1
issue: 8
---

# 0009 — Datos personales en los diagnósticos (issue #8)

**Contexto:** `Diagnostico.mensaje/1` interpola el contenido recibido
(`recibido: "12345678-9"`, `recibido: "JOSÉ MUÑOZ"`) porque está diseñado
para pegarse en un correo. Ese mismo mensaje termina en `Logger.error`, en
Sentry y en el ticket. Y `inspect(diagnostico)`, que es lo que la mayoría
loguea, traía además `:contenido` con los bytes crudos del campo.

## Prompt

El `/loop` que gobierna la serie de issues, sin prompt propio para esta:

> y arma un /loop de cada issue que necesita un pr armalo y que sea senior
> level planifica monitorewa senio senior

## Resultado

- Opción `sensible: true` en `AnchoFijo.Campo`, booleana, con default
  `false` salvo en `:rut`, donde es `true`.
- `AnchoFijo.Diagnostico` gana `:sensible` y `:redactado`.
  `marcar_sensible/2` marca un diagnóstico y guarda la forma del valor;
  `forma/1` describe un valor sin revelarlo.
- `mensaje/2` y `reporte/2` aceptan `revelar: true`; sin eso, y en
  `to_string/1` e `inspect/1`, un diagnóstico sensible muestra la forma.
  `inspect/1` además oculta `:contenido`.
- `Campo.extraer/3` marca todo diagnóstico de un campo sensible en sus tres
  etapas: línea corta, byte inválido, valor que no convierte.
- Las entradas que no son binarios se describen por tipo en vez de
  inspeccionarse (`Entrada.describir/1`), en `parsear/3` y `stream/3`.
- `test/ancho_fijo/sensibles_test.exs`: una tabla con cada tipo de campo y
  cada falla posible verifica la ausencia del valor en cinco
  representaciones, más una propiedad sobre valores generados.
- Sección propia en el README.

## Decisiones tomadas

1. **La forma, no una máscara ni la supresión.** Era la decisión de la issue.
   Una máscara parcial (`1234****-*`) deja ver lo suficiente para
   reidentificar —cuatro dígitos de un RUT dejan diez mil candidatos— y oculta
   justo lo que hace falta para depurar. La supresión total (`<10 bytes>`) no
   dice nada. La forma (`<10 caracteres: 4 dígitos, 1 letra, 3 dígitos, "-",
   1 dígito>`) dice que hay una letra donde debía haber un dígito y en qué
   posición, sin decir cuál. La puntuación se muestra literal porque es
   estructura, no identidad.

2. **El largo no se oculta.** Es el ancho del campo, que el layout ya
   declara; ocultarlo no protege nada y quita información. La issue lo
   preguntaba.

3. **`:rut` es sensible por default.** Un RUT es siempre un dato personal; el
   tipo existe para identificadores de personas. El default general sigue
   siendo `false` para no empeorar el debugging del día uno, que es lo que la
   librería promete. `sensible: false` explícito apaga el default del RUT.

4. **`inspect/1` también redacta.** La issue hablaba de `mensaje/1`, pero el
   camino más común al log es `Logger.error(inspect(diagnostico))`, y el
   struct traía `:contenido` con los bytes crudos. El `Inspect` propio muestra
   `:recibido` con la forma y `:contenido` como `**redactado**`, con el prefijo
   `#AnchoFijo.Diagnostico` para que se note que no es el struct literal. Es
   el patrón de `redact: true` en Ecto. El struct sigue entero: la redacción
   es de las representaciones, y `d.recibido` lo lee quien quiere a
   propósito.

5. **Qué no se redacta.** Un byte inválido y su posición no son un dato
   personal y son el diagnóstico entero de un problema de encoding; la medida
   de una línea corta es un número. En esos dos casos el diagnóstico sensible
   mantiene `:recibido` y solo oculta `:contenido`. Las observaciones del
   detector citan a lo sumo un byte y un delimitador: la auditoría no
   encontró contenido de campos ahí.

6. **Las entradas que no son binarios se describen por tipo.** `inspect/1`
   sobre una lista de líneas o un mapa con datos habría metido el archivo
   entero en el mensaje. Fuga indirecta que la issue pedía auditar y que no
   estaba en la lista.

7. **El test verifica una ausencia.** Una tabla con diez combinaciones de
   tipo y falla, un centinela que no aparece por casualidad (`QZX7`), y cinco
   representaciones por caso. Más una propiedad con StreamData sobre valores
   generados. Un test de ausencia solo vale si cubre todos los caminos, por
   eso es una tabla y no tres ejemplos.
