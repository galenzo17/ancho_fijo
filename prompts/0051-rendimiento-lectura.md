---
prompt: 0051
fecha: 2026-10-29T10:57:24-03:00
autor: Agustín Bereciartúa <bereciartua.agustin@gmail.com>
modelo: claude-fable-5-1
issue: 95
---

# 0051 — La 0.4.0 leía la mitad que la 0.3.1: patrón compilado una vez y menos costo por campo (issue #95)

**Contexto:** novena iteración del segundo loop. La revisión de la 0.4.0
midió `stream/3` a 210 líneas/ms contra 385 de la 0.3.1, con el campo de
fecha como principal culpable: `Tipo.Fecha.leer/3` compilaba el patrón en
cada lectura, `Patron.leer/3` contaba grafemas dos veces y `nulo?/2`
cortaba el texto antes de `leer/3`. El resto eran costos chicos por campo
y por línea que no existían: reglas que se evaluaban sin que el layout
declarara ninguna, validación UTF-8 por campo, dos `String.trim_trailing/2`
por línea y dos despachos por campo.

## Prompt

> revisa si hay pr que mergear y luego issues por cerrar arma un /loop
> merge y sigu y luego otro, si salen issues crealas, y luego otro
> verification loop pr revie merge y asi sucesivo senior level

## Resultado

- `Campo.nuevo/1` compila el patrón de `:fecha`, `:hora` y `:fecha_hora`
  una vez y lo guarda en `:formato_compilado` (dato derivado, 31 claves
  con `__struct__`: sigue siendo un flatmap). `Patron.de/1` lo toma del
  campo, o compila si el campo se armó sin `nuevo/1`. La serialización no
  lo emite y `Map.from_struct/1` de un campo lo tolera.
- `Patron.leer/3` y el nuevo `Patron.leer_o_nulo/3`: con un patrón ASCII y
  un texto que mide en bytes lo que el patrón, los tokens se cortan con
  `binary_part/3` en un solo recorrido que decide "sin dato" y lee; ante
  cualquier discrepancia, el camino por grafemas de siempre decide y
  redacta el mensaje. `Fecha` y `FechaHora` usan `leer_o_nulo/3`; `Hora`
  no (para una hora, `0000` es medianoche, no "sin dato").
- `Reglas.del_valor/3` sale en la primera cláusula para un campo sin
  reglas; `Layout.nuevo/1` precalcula `:con_condiciones` y el parser y el
  escritor no llaman a `Reglas.cruzadas/3` (ni arman el registro
  canónico) cuando ningún campo declara `requerido_si:` ni
  `prohibido_si:`.
- Si la línea entera es ASCII imprimible (`Transcodificacion.ascii_limpio?/1`,
  un recorrido por línea), el parser marca `linea_ascii: true` en el
  contexto y `Campo.leer/3` no transcodifica ni revisa cada tramo: el
  resultado es el mismo que daría `a_utf8/2` tramo por tramo.
- `Entrada.sin_terminador/1` recorta byte a byte en vez de dos
  `String.trim_trailing/2` (misma semántica: todos los `\n` del final y
  después todos los `\r`). `Parser.extraer_campo/4` despacha una vez por
  el módulo del campo (relleno, anidado o plano) sin tupla intermedia.
- `bench/README.md`: tabla 0.3.1 / 0.4.0 / después en la misma máquina y
  la lista de lo que se encontró. `parsear_linea/3`: 3,08 → 2,53 µs
  (0.3.1: 2,40); `stream/3`: 256–273 → 303–315 líneas/ms (0.3.1:
  323–331); `Campo.leer` fecha: 2,23 → 0,80 µs (0.3.1: 0,78).
- Ningún cambio de comportamiento: la suite completa, incluidas las
  propiedades de round-trip, sigue verde con tres semillas, en 1.14 y 1.20.

## Decisiones tomadas

1. El camino rápido de `Patron` solo decide éxitos: cualquier fallo vuelve
   al camino por grafemas, que es el que distingue "mide distinto" de "no
   es numérico" y redacta el mensaje. Así los diagnósticos son
   byte a byte los de antes sin duplicar la lógica de mensajes.
2. `linea_ascii` se decide por línea y no por campo porque un tramo de una
   línea con multibyte puede cortar un carácter por la mitad, y ese tramo
   sí tiene que validarse solo. Con la línea ASCII entera no hay tramo que
   pueda fallar.
3. El escritor queda un 30 % sobre la 0.3.1 y `Campo.leer` de un `:texto`
   un 25 %: son los costos de #91 (diagnósticos sensibles), #92 (valor
   canónico) y la doble codificación, que compran garantías. La issue era
   la lectura; el escritor no se tocó más allá del patrón compilado y la
   bandera de condiciones.
4. La propiedad de rellenos de #94 dejó de exigir cero advertencias: con
   `"ñ···"` en latin-1 la heurística de doble codificación da un falso
   positivo (issue #114).
