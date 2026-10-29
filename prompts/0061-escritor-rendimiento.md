---
prompt: 0061
fecha: 2026-10-29T12:08:45-03:00
autor: Agustín Bereciartúa <bereciartua.agustin@gmail.com>
modelo: claude-fable-5-1
issue: 125
---

# 0061 — El escritor deja de pagar por campo lo que no usa (issue #125)

**Contexto:** la issue la abrió el loop al cerrar #95: la lectura había
vuelto a la par de la 0.3.1 pero `Escritor.escribir_linea/4` seguía en 3,58
µs contra 2,71. Las causas estaban anotadas en `bench/README.md`: el valor
canónico de #92 se calculaba antes de las reglas aunque no hubiera reglas,
y los diagnósticos sensibles de #91.

## Prompt

> revisa si hay pr que mergear y luego issues por cerrar arma un /loop
> merge y sigu y luego otro, si salen issues crealas, y luego otro
> verification loop pr revie merge y asi sucesivo senior level

## Resultado

- `Campo.formatear/3` calcula el valor canónico solo si el campo tiene
  reglas (`reglas_del_valor/3`): para un `:decimal` era llevar el valor a
  unidades y volver, en cada campo de cada línea, para nada.
- `con_signo/5` mide los dígitos en bytes (son ASCII), completa con
  `:binary.copy/2` y recibe la descripción de lo esperado como función: se
  arma solo cuando el valor no cabe, que es cuando se lee.
- `Patron.escribir/3` completa los dígitos por bytes, y la fecha escrita se
  completa a su largo por bytes cuando el patrón es ASCII (`largo ==
  largo_bytes`), con `String.pad_trailing/2` si no.
- Medido con el arnés de `bench/README.md`: `Campo.formatear` decimal de
  0,91 a 0,26 µs, fecha de 1,08 a 0,65, texto de 0,43 a 0,27;
  `escribir_linea/4` de 3,58 a 1,91 µs (0.3.1: 2,71); `escribir/3` de
  300.000 registros de 5,2 s a 3,2 s (0.3.1: 4,75). La tabla y la lista de
  causas del bench quedan actualizadas. Sin cambios de comportamiento: la
  suite completa sigue verde.

## Decisiones tomadas

1. `sensibilizar_escritura/3` no se tocó: para un campo no sensible es una
   cláusula de paso, y lo que cuesta en un sensible es la forma del valor,
   que es lo que #91 compra.
2. La descripción perezosa es una función anónima y no un átomo que se
   resuelva después: hay tres descripciones distintas y la función captura
   lo que cada una necesita sin otro despacho.
