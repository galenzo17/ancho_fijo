---
prompt: 0038
fecha: 2026-10-21T20:29:47-03:00
autor: Agustín Bereciartúa <bereciartua.agustin@gmail.com>
modelo: claude-fable-5-1
issue: 59
---

# 0038 — OCCURS y REDEFINES: grupos repetidos y variantes (issue #59)

**Contexto:** decimosexta iteración del loop sobre las issues abiertas; la
rama parte de la de #58 (prompt 0037). Un grupo de campos que se repite N
veces y un tramo del registro que cambia según un campo anterior se
declaraban a mano (`total_1`, `total_2`) o no se podían declarar.

## Prompt

> anda a main y revisa luego las issues, arma un /loop cada issue un pr si
> es necesario, senior level ultra mega pro ultrathink

## Resultado

- Tipos `:grupo` (`campos:`, `repetir:`) y `:variante` (`segun:`,
  `variantes:`), con los campos internos construidos en `Campo.nuevo/1`
  como un layout chico (posiciones encadenadas desde 1, sin solapamientos
  ni repetidos) y el largo calculado o verificado contra el declarado.
- `AnchoFijo.Anidados` (sin doc): lee y escribe los internos llevando sus
  posiciones a absolutas y usando `Campo.leer/3` y `Campo.formatear/3`, así
  que el encoding por campo, los sensibles y todo lo demás funcionan igual;
  los diagnósticos llevan la ruta (`totales[2].importe`, `destino.cuenta`),
  que `Diagnostico` muestra tal cual. El parser y el escritor despachan por
  `Campo.anidado?/1`; el layout verifica que `segun` exista y venga antes.
- Serialización, documentación (filas internas con posiciones relativas) y
  generadores (la lista por `repetir`; la variante según el valor
  generado, y el campo que elige solo toma valores con variante).
- Fixture `nomina_anidada.txt` con `Fixtures.layout_anidado/0`, round-trip
  completo y diagnósticos con ruta.

## Decisiones tomadas

1. **Campos de primera clase, no expansión a campos planos.** Expandir
   `totales` a `totales_1_moneda` daría nombres sintéticos y un registro
   plano; la issue pide una lista de mapas y el mapa de la variante, y eso
   obliga a que el parser los arme. El costo es un módulo nuevo.
2. **El valor de `segun` se resuelve en el parser, no en el campo.** Un
   campo solo ve su tramo; la variante necesita el registro leído hasta
   ahí. Por eso `Anidados.leer/4` recibe los valores ya extraídos, y el
   layout exige que `segun` venga antes.
3. **La ruta del campo es un string en `Diagnostico.campo`.** Es el único
   lugar donde un nombre de campo no es un átomo, y lo que la issue pide
   literalmente; `desde_mapa/1` lo deja como string.
4. **Las claves de las variantes se buscan tal cual y por su forma de
   texto.** Un layout leído de JSON tiene las claves como strings aunque el
   campo que elige sea un entero; mejor resolverlo al leer que prohibir
   enteros como clave.
5. **Las variantes más cortas se completan con blanco solo si el campo
   declara el largo.** Sin `largo:`, todas miden lo mismo o el layout es
   inválido: el tamaño del registro es parte del formato.
