---
prompt: 0046
fecha: 2026-10-29T10:14:42-03:00
autor: Agustín Bereciartúa <bereciartua.agustin@gmail.com>
modelo: claude-fable-5-1
issue: 92
---

# 0046 — Las reglas miran el valor canónico y el layout exige reglas del tipo del campo (issue #92)

**Contexto:** cuarta iteración del segundo loop. Dos problemas con el
mismo origen, comparar valores sin normalizarlos al tipo del campo: al
escribir, las reglas `en:` y `rango:` miraban el valor crudo del mapa (un
`Decimal.new("1.00")` no pasaba el catálogo `[{100, 2}]`, y un `"99.00"`
esquivaba el rango porque `Reglas.comparar/2` contestaba `:eq` para lo que
no sabía comparar); y el layout aceptaba un rango de fechas en un `:entero`
o un catálogo de textos en un `:entero`, reglas que no pueden fallar nunca
o que fallan siempre.

## Prompt

> revisa si hay pr que mergear y luego issues por cerrar arma un /loop
> merge y sigu y luego otro, si salen issues crealas, y luego otro
> verification loop pr revie merge y asi sucesivo senior level

## Resultado

- `Campo.canonico/2` (`@doc false`): el valor como lo devolvería `leer/3`.
  Un `%Decimal{}`, un entero, un string o la tupla de un `:decimal` pasan a
  la tupla, el `Monto` o el `Decimal` del campo (con `Tipo.Decimal.valor/2`,
  ahora público y `@doc false`); un `:texto` se recorta como al leer. Lo que
  no se puede llevar queda como vino y `representar/3` lo reclama.
  `Campo.formatear/3` evalúa `Reglas.del_valor/3` sobre ese valor, y
  `Escritor.escribir_linea/4` evalúa las condiciones cruzadas sobre el
  registro canónico.
- `Reglas.en/3` compara con `igual?/2`: igualdad estructural, y entre
  formas numéricas (entero, tupla, `Monto`, `Decimal`) la de `comparar/2`,
  así `en: [{100, 2}]` acepta `Decimal.new("1.00")` con `como: :decimal`.
- `Reglas.validar/1` exige que los valores de `en:` y los extremos de
  `rango:` sean del tipo del campo: enteros en `:entero`; entero, tupla,
  `Monto` de la moneda del campo o `Decimal` en `:decimal`; `Date`, `Time`
  y `NaiveDateTime` en los de fecha y hora; binarios en `:texto`, `:rut` y
  `:constante`. Un diagnóstico `:layout` por cada valor; un tipo propio no
  se valida. La comparación mínimo-máximo del rango solo corre si los
  extremos son del tipo.
- `Reglas.comparar/2` levanta `ArgumentError` para lo incomparable, con el
  mensaje de que el layout lo reclama al construirse. Dos `Monto` de
  distinta moneda también son incomparables.
- Tests: los snippets de la issue, moneda y `como: :decimal`, texto
  recortado, condición cruzada con `Decimal`, una propiedad con las cinco
  formas equivalentes de un decimal (`{n·100, 2}`, `n`, `Decimal.new(n)`,
  `"n.00"`, `"n"`) que afirma que reciben la misma respuesta, y una con
  `Generadores.registro/1` sobre un layout con reglas de cada tipo que se
  escribe sin diagnósticos. Doc de `Campo` y README (es y en).

## Decisiones tomadas

1. El valor canónico se calcula solo para las reglas; `representar/3` sigue
   recibiendo el valor original, para que sus diagnósticos digan lo que
   llegó.
2. `igual?/2` en vez de `in`: con `como: :decimal` el valor canónico es un
   `%Decimal{}` y el catálogo suele estar escrito con tuplas; exigir una
   forma única en el layout habría roto layouts existentes.
3. Un `Monto` en una regla de un `:decimal` sin moneda se acepta (es
   comparable con la tupla); con moneda, tiene que ser la del campo.
4. `comparar/2` levanta en vez de devolver `:eq`: después de validar el
   layout no debería ocurrir, y una regla que nunca falla es peor que una
   excepción.
