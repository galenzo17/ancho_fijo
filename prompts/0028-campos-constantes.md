---
prompt: 0028
fecha: 2026-10-21T18:42:02-03:00
autor: Agustín Bereciartúa <bereciartua.agustin@gmail.com>
modelo: claude-fable-5-1
issue: 48
---

# 0028 — Campos constantes y de relleno (issue #48)

**Contexto:** sexta iteración del loop sobre las issues abiertas, la primera
de las features; la rama parte de la de #41 (prompt 0027). Todo layout
bancario tiene posiciones cuyo valor lo pone el formato: el código de tipo
de registro, literales fijos, fillers. Hasta acá se declaraban como `:texto`,
sin validar al leer y repetidos en cada mapa al escribir.

## Prompt

> anda a main y revisa luego las issues, arma un /loop cada issue un pr si
> es necesario, senior level ultra mega pro ultrathink

## Resultado

- `AnchoFijo.Tipo.Constante` (`tipo: :constante, valor: "01"`): al leer, el
  texto tiene que ser el literal (sin contar el relleno final de ninguno de
  los dos) o es un diagnóstico con `esperado` y `recibido`; al escribir se
  emite solo, o con el mismo literal en el mapa; otro valor es un
  diagnóstico. `esperado/1` y `coincide?/3` son públicas para el
  discriminador y el detector.
- `AnchoFijo.Tipo.Relleno` (`tipo: :relleno`): no se lee ni va al registro;
  se escribe con su carácter; un valor en el mapa es un diagnóstico; al
  final de la línea es reponible con `relleno_final: :tolerar`.
- `Multiregistro`: `discriminador: [campo: :tipo]` resuelve posición, largo
  y valores desde el campo `:constante` de cada layout, que tiene que estar
  igual en todos; con `[posicion:, largo:]`, `:valor` se omite si hay una
  constante justo ahí.
- `detectar/2` con `layout:` cuenta en cuántas líneas aparece cada literal.
- Tests por tipo en `campo_test`, en `parser_test`, round-trip byte a byte
  de un header/detalle/trailer con literales y fillers en `escritor_test`,
  la definición del discriminador en `multiregistro_test`, la observación en
  `detector_test`, y los dos tipos en los generadores de propiedades.

## Decisiones tomadas

1. **Dos tipos y no una opción `default:` por campo.** Un `default:` en un
   `:texto` seguiría sin validar al leer, y la semántica de "no va al
   registro" del relleno no cabe en una opción de otro tipo. Como tipos,
   entran por el behaviour que ya existe y `Campo.formatear/3` los escribe
   como a cualquier interno.
2. **El relleno no se valida al leer.** Un filler es lo que el emisor no se
   compromete a llenar con nada; validarlo rompería archivos reales por
   basura que nadie lee. Las propiedades de mutación se ajustaron para no
   mutar bytes dentro de un relleno.
3. **Un literal distinto es un error, no una advertencia.** En tolerante la
   línea se reporta y el archivo sigue, que es lo que pedía la issue; una
   advertencia habría dejado pasar una línea que no es del formato.
4. **El discriminador por campo exige la misma posición y largo en todos
   los layouts**, con un diagnóstico que lista dónde está en cada tipo. Un
   discriminador que se lee distinto por tipo no es un discriminador.
5. **La comparación del literal recorta el relleno final de los dos lados**,
   así `"HEADER"` en un campo de 10 calza con `"HEADER    "` y un literal
   de ceros con `relleno: "0"` también. Al escribir se completa a la
   derecha, midiendo en la unidad del layout.
