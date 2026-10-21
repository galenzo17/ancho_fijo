---
prompt: 0027
fecha: 2026-10-21T18:12:35-03:00
autor: Agustín Bereciartúa <bereciartua.agustin@gmail.com>
modelo: claude-fable-5-1
issue: 41
---

# 0027 — Tests de escritura para tipos propios y `Monto` (issue #41)

**Contexto:** quinta iteración del loop sobre las issues abiertas; la rama
parte de la de #40 (prompt 0026). Al integrar la escritura (#2) con el
behaviour `Tipo` (#12) y la moneda (#9), `Campo.formatear/3` quedó con dos
caminos verificados a mano y sin test.

## Prompt

> anda a main y revisa luego las issues, arma un /loop cada issue un pr si
> es necesario, senior level ultra mega pro ultrathink

## Resultado

- `AnchoFijo.TipoHora` implementa `escribir/2`; dos módulos de prueba más
  en `test/support/tipo_hora.ex`: `TipoSoloLectura` (sin `escribir/2`) y
  `TipoAnchoEquivocado` (devuelve un texto de otro ancho).
- `escritor_test`: round-trip de un tipo propio (HHMM, HHMMSS y opcional
  con `nil`), el tipo que solo sabe leer, `escribir/2` que devuelve
  `{:error, causa}`, el ancho equivocado en bytes y en caracteres; y para
  `moneda:`: round-trip con CLP y USD con signo final, la tupla con la
  precisión de la moneda y con otra, un `Monto` de otra moneda, de otra
  precisión, y un `Monto` en un campo sin moneda.
- `Generadores.decimal_con_moneda/0` entra en `layout_con_registro/1`, así
  que las propiedades de round-trip existentes generan campos con moneda;
  una propiedad más, solo de montos, con unidades negativas.
- Los módulos de `test/support` en `ignore_modules` de la cobertura:
  medían el paquete con código que no es del paquete. Total: 92,75 %.

## Decisiones tomadas

1. **Los tipos de prueba viven junto a `TipoHora`, no en un archivo por
   módulo.** Son tres módulos de diez líneas que existen para los mismos
   tests; dispersarlos en `test/support` obliga a abrir cuatro archivos
   para leer un describe.
2. **El generador con moneda es uno nuevo y no una opción del existente.**
   `decimal/0` elige la precisión libremente; con moneda la precisión la
   pone la tabla y la definición no puede llevar `precision:`. Dos
   generadores chicos son más claros que uno con dos modos.
3. **`TipoHora` queda fuera de la cobertura, aunque antes contaba.** Es
   código de test; que sumara al total era un accidente de cuando se
   agregó, y con tres módulos de prueba más el accidente pesaba.
