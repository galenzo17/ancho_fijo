---
prompt: 0039
fecha: 2026-10-21T21:06:12-03:00
autor: Agustín Bereciartúa <bereciartua.agustin@gmail.com>
modelo: claude-fable-5-1
issue: 60
---

# 0039 — Validaciones declarativas por campo (issue #60)

**Contexto:** decimoséptima iteración del loop sobre las issues abiertas; la
rama parte de la de #59 (prompt 0038). Las reglas del dominio (catálogo de
códigos, importe no negativo, forma de un identificador, obligatoriedad
condicionada a otro campo) vivían después de `parsear/3`, en el consumidor,
y sus errores perdían la línea y la posición que los diagnósticos ya saben
dar.

## Prompt

> anda a main y revisa luego las issues, arma un /loop cada issue un pr si
> es necesario, senior level ultra mega pro ultrathink

## Resultado

- Opciones comunes a todos los tipos: `en:` (lista o función de un
  argumento), `rango: {min, max}` con `nil` en el extremo abierto, `patron:`
  (`Regex`, solo en `:texto`), `requerido_si:` y `prohibido_si:` con la forma
  `[campo: :otro]` o `[campo: :otro, en: [...]]`. `Campo.nuevo/1` valida la
  forma de cada una; `Layout.nuevo/1` verifica que las condiciones nombren
  un campo del layout.
- `AnchoFijo.Reglas` (sin doc): las reglas del valor se aplican en
  `Campo.leer/3` y `Campo.formatear/3`, sobre el valor ya convertido, así
  que un rango compara tuplas, `Monto`, `Decimal` y fechas sin mirar cómo
  vienen escritos; las cruzadas se aplican en `Parser`, `Multiregistro` y
  `Escritor` cuando el registro está completo. `nil` no se valida: la
  obligatoriedad es de `requerido_si:`.
- Diagnóstico de tipo `:regla`, nuevo, con línea, campo, posiciones y la
  regla en `esperado`; sensible cuando el campo lo es. En estricto corta
  (también en multiregistro); en tolerante el registro se entrega y el
  diagnóstico queda como error, y la telemetría lo cuenta como tal.
- `documentar/2` suma la columna "Reglas" en los tres formatos y los dos
  idiomas; la tabla del README se regeneró.
- Serialización: `patron` como `{"patron", "opciones"}`, extremos de rango
  en la forma del tipo (enteros, `[u, p]`, ISO 8601, string decimal),
  condiciones como mapa; `en:` con función levanta `ArgumentError`.
- Generadores: `en:` lista → `member_of`, `rango:` → generador acotado por
  tipo, condiciones cruzadas satisfechas después de generar, iterando hasta
  que no quede ninguna (arreglar una puede disparar otra). `generador:`
  acepta un `StreamData` propio y es obligatorio con `patron:` o `en:` con
  función, con un error que lo dice.
- Suite `reglas_test.exs`: lectura, escritura, tolerante y estricto,
  multiregistro, sensibles, validación del layout, serialización de ida y
  vuelta, documentación y propiedades de los generadores.

## Decisiones tomadas

- Las reglas se evalúan sobre el valor convertido, no sobre el texto: un
  `rango:` de decimal se escribe en la misma forma en que el campo lo
  devuelve (`{0, 0}`, un `Decimal`, un `Monto`), y `patron:` solo tiene
  sentido en `:texto`. Mezclar los dos planos habría obligado a reescribir
  cada regla por formato.
- Una regla que falla al escribir es `{:error, _}` como un valor que no
  cabe: el archivo no sale con un registro que el mismo layout rechazaría
  al leerlo.
- Lo incomparable en un rango se considera igual y no produce diagnóstico:
  mejor silencio que un error inventado por un tipo propio.
- `en:` con función no se serializa ni se genera; la alternativa (guardar el
  nombre de la función) habría sido un dato que no se puede validar.
