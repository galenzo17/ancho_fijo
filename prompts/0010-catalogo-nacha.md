---
prompt: 0010
fecha: 2026-10-16T19:52:04-03:00
autor: Agustín Bereciartúa <bereciartua.agustin@gmail.com>
modelo: claude-fable-5-1
issue: 10
---

# 0010 — Catálogo de formatos reales: NACHA primero (issue #10)

**Contexto:** la librería lee cualquier formato, pero cada usuario
transcribe el anexo desde cero. Los formatos de verdad son públicos y
estables. La issue pedía empezar por uno solo y completo, con su fuente
citada y una decisión sobre cómo se versionan.

## Prompt

El `/loop` que gobierna la serie de issues, sin prompt propio para esta:

> y arma un /loop de cada issue que necesita un pr armalo y que sea senior
> level planifica monitorewa senio senior

## Resultado

- `AnchoFijo.Formatos` con `catalogo/0` y `nacha/1` con la opción
  `vigencia:`.
- `AnchoFijo.Formatos.Nacha`: los seis layouts más el relleno, el
  multiregistro, `validar/1` con los controles propios del formato y
  `lotes/1` con la estructura anidada. Fuente en el módulo.
- Dos extensiones genéricas en `Multiregistro`: varios valores de
  discriminador por tipo y `orden: :libre`.
- Fixture `nacha_ppd.txt` generado por `generar.exs`, con routing numbers
  de dígito verificador válido que no son de ningún banco, cuentas y
  nombres inventados, dos lotes, una addenda y relleno de nueves.
- 13 tests; sección "Formatos incluidos" en el README.

## Decisiones tomadas

1. **NACHA primero, no Previred.** La issue dejaba elegir según el foco:
   Previred si el mercado chileno, NACHA si mostrar multiregistro. NACHA es
   multiregistro de verdad, con lotes anidados y totales de control, y su
   especificación es pública, estable desde hace décadas y verificable
   línea por línea en la guía de Nacha; se verificó cada posición contra
   ella antes de transcribir. Previred tiene 105 campos cuya fuente
   oficial hay que leer con cuidado, y transcribirla "de memoria" sería
   exactamente el layout desactualizado en silencio que la issue advierte.
   Queda como el siguiente, con el mecanismo de vigencias ya listo.

2. **Vigencia explícita, con un default.** `nacha()` da la vigencia más
   nueva del catálogo; `nacha(vigencia: "2021")` fija una que no cambia
   cuando el catálogo se actualiza. En producción corresponde fijarla,
   para que una actualización de la librería no cambie qué se lee sin que
   nadie lo decida. Una vigencia desconocida es `ArgumentError`, y
   `catalogo/0` lista las disponibles con fuente y fecha de consulta.

3. **Los nombres de los campos son los de la especificación.** En inglés y
   `snake_case`: `immediate_destination`, `entry_hash`. La librería es en
   español, pero el valor de un formato incluido es que se pueda verificar
   campo por campo contra el Apéndice Tres sin traducir. Los tipos de
   registro sí están en español, porque son de la librería.

4. **Lo propio del formato va en el módulo del formato.** NACHA necesita
   controles que el `Multiregistro` genérico no expresa: sumas
   condicionadas por el código de transacción (débitos y créditos), el
   entry hash con sus diez dígitos de la derecha, y controles por lote
   además de por archivo. Meter eso en el genérico lo habría complicado
   para todos; `Nacha.validar/1` lo hace sobre la lista ordenada de
   registros, que es justamente lo que la representación de #1 permite.

5. **Dos extensiones genéricas, mínimas.** El discriminador de dos
   posiciones (tipo más el primer dígito del campo siguiente) es lo que
   distingue el control de archivo (`90`) del relleno (`99`), y hace que
   las entradas tengan varios valores (`62`, `63`...): `valor:` acepta una
   lista. Y los lotes se repiten, así que el orden lineal del genérico no
   aplica: `orden: :libre` deja las cantidades y delega la estructura
   anidada a `validar/1`.

6. **El relleno es un tipo de registro.** Las líneas de nueves que
   completan el bloque de diez no están en la guía pública pero sí en los
   archivos reales (por eso existe el *block count*). Tratarlas como un
   tipo `:relleno` de cantidad `:varios` evita que un archivo real falle
   por "control de archivo repetido". La cuenta de bloques las excluye.

7. **Fechas `YYMMDD` como texto.** El tipo `:fecha` lee ocho dígitos, y
   adivinar el siglo no es cosa del parser. Un formato `:aammdd` es un
   agregado razonable para después.

8. **El fixture lo genera código, no un archivo pegado.** Routing numbers
   con dígito verificador ABA válido pero en rangos que no existen,
   totales y hash calculados por el generador con la misma fórmula que el
   validador. Como con el RUT, el round-trip solo prueba consistencia; los
   tests que alteran un monto, un routing number o una addenda y esperan
   el diagnóstico exacto son los que anclan la corrección.
