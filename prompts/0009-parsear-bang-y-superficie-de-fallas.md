---
prompt: 0009
fecha: 2026-10-16T21:50:00-03:00
autor: Agustin Bereciartua <bereciartua.agustin@gmail.com>
modelo: claude-fable-5-1
issue: 16
---

# 0009 — `parsear!/3`, `AnchoFijo.Error` y la superficie de fallas (issue #16)

**Fecha:** 2026-10-16
**Contexto:** la API devuelve tuplas, que es lo correcto para el modo
tolerante, pero obliga a un `case` con `raise` adentro en cada script que
tiene que morir si el archivo está mal. `AnchoFijo.Error` ya existía, metido
al final de `diagnostico.ex` y usado solo por `Layout.nuevo!/1`,
`Campo.nuevo!/1` y `stream/3`.

## Prompt

El `/loop` que gobierna la serie de issues, sin prompt propio para esta:

> y arma un /loop de cada issue que necesita un pr armalo y que sea senior
> level planifica monitorewa senio senior

## Resultado

- `AnchoFijo.parsear!/3` y `AnchoFijo.detectar!/2` (delegadas a `Parser` y
  `Detector`), con `@doc` que enlaza a la versión con tupla y doctests.
- `AnchoFijo.Error` en `lib/ancho_fijo/error.ex`, con el contrato de las dos
  formas de fallar documentado, y en el grupo "Diagnóstico" de hexdocs.
- `AnchoFijo.Opciones` (interno): valida las opciones de `parsear/3`,
  `stream/3` y `detectar/2` y levanta `ArgumentError` con el nombre de la
  función, la opción y lo que esperaba.
- `stream/3` reporta un elemento no binario como diagnóstico en su posición.
- `Layout.nuevo/1` y `Campo.nuevo/1` rechazan claves desconocidas, argumentos
  que no son definiciones, `:nombre` no binario y `:opcional` no booleano.
- `detectar/2` con `:layout` inválido devuelve `{:error, diagnosticos}`.
- `test/ancho_fijo/superficie_test.exs`: le pasa basura a cada punto de
  entrada y sostiene el contrato. `test/ancho_fijo/error_test.exs`: la
  excepción y los bangs. Suite: 334 verdes (85 doctests, 16 propiedades, 233
  tests), credo estricto y dialyzer limpios.

## Decisiones tomadas

1. **Bang + tolerante: levanta con todos los errores.** Era la decisión de
   diseño de la issue. Las dos opciones eran levantar (y entonces ¿para qué
   el modo tolerante?) o devolver las filas buenas descartando los
   diagnósticos (y entonces el `!` pierde información en silencio). La
   respuesta es que el modo tolerante sí cambia algo con el bang: **qué trae
   la excepción**. En estricto, el primer error; en tolerante, todos. Es la
   combinación para el script que tiene que morir, pero cuyo operador quiere
   la lista completa para corregir el archivo de una vez. Un `!` no es un
   atajo: es otro contrato.

2. **Las advertencias no se devuelven desde el bang.** La función devuelve
   un solo valor, y una advertencia es una fila que se leyó bien bajo un
   supuesto que el layout declaró. Devolver `{registros, advertencias}`
   habría roto la convención (el bang devuelve el valor, no una tupla).
   Levantar por una advertencia habría hecho inútil `relleno_final: :tolerar`
   con el bang. Se documenta: si las advertencias importan, `parsear/3`.

3. **Opciones mal formadas: `ArgumentError`, no diagnóstico.** La auditoría
   mostró que `modo: :otro` devolvía un diagnóstico `:entrada` (mezclando un
   bug del llamador con un dato sucio) y que `saltar: :x` o `desde: :x`
   reventaban con `FunctionClauseError` en `Enum.drop/2` o `CaseClauseError`,
   sin decir qué opción fue. La stdlib levanta `ArgumentError` por mal uso;
   se hace lo mismo, con un mensaje que nombra la función, la opción, lo que
   esperaba y lo que llegó. Rompe compatibilidad para quien dependía del
   diagnóstico de `:modo`; anotado en el CHANGELOG.

4. **Claves desconocidas en el layout son error.** No estaba en la issue, pero
   la auditoría de "¿qué puede escapar que yo no decidí?" encontró el caso
   inverso: lo que **no** escapa y debería. `precison: 2` dejaba un `:decimal`
   sin precisión, con un diagnóstico que decía que faltaba `:precision`,
   cierto pero inútil; `enconding: :latin1` dejaba un layout en UTF-8 sin
   ninguna señal. Es el error silencioso que la librería existe para impedir,
   en su propia definición. `:advertencias` y `:__struct__` se admiten porque
   vienen en un `Map.from_struct/1`.

5. **Los módulos de apoyo conservan sus guardas.** `Rut.normalizar(42)`,
   `Transcodificacion.a_utf8(42, :latin1)` y `Campo.extraer/3` con un no
   binario levantan `FunctionClauseError`. Convertir cada guarda en un
   `ArgumentError` explícito habría sido churn sin beneficio: es exactamente lo
   que hace `String.upcase(42)`. El contrato de las dos formas de fallar es de
   los puntos de entrada —`parsear`, `stream`, `detectar`, `Layout.nuevo`— y
   el README lo dice así.

6. **Sin `Exception.blame/3`.** El mensaje de `AnchoFijo.Error` ya es el
   reporte completo de los diagnósticos, con línea, campo, posición y causa.
   `blame` sirve para enriquecer excepciones cuyo mensaje es pobre
   (`FunctionClauseError` mostrando qué cláusulas se intentaron); acá no hay
   nada que agregar que no esté en el mensaje. Sobreingeniería.

7. **El script de basura quedó como test, no como script.** La auditoría se
   hizo con un `.exs` temporal que le tira 70 llamadas malas a la API y
   clasifica la respuesta. Lo que importa de ese script es que siga siendo
   cierto, así que la parte de los puntos de entrada quedó en
   `superficie_test.exs`. El script en sí no se versiona.
