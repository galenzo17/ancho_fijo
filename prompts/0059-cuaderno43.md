---
prompt: 0059
fecha: 2026-10-29T11:55:33-03:00
autor: Agustín Bereciartúa <bereciartua.agustin@gmail.com>
modelo: claude-fable-5-1
issue: 105
---

# 0059 — Cuaderno 43 de la AEB en el catálogo; Previred es delimitado (issue #105)

**Contexto:** decimoséptima y última iteración del segundo loop. El
catálogo prometía "Previred (Chile) es el siguiente", pero el archivo
vigente de Previred es delimitado por punto y coma: la promesa no se podía
cumplir. La issue proponía el segundo formato con el criterio de NACHA
(público, estable, con fuente citable, y que ejercite lo que NACHA no): la
Norma 43 de la AEB, el extracto bancario de España.

## Prompt

> revisa si hay pr que mergear y luego issues por cerrar arma un /loop
> merge y sigu y luego otro, si salen issues crealas, y luego otro
> verification loop pr revie merge y asi sucesivo senior level

## Resultado

- `AnchoFijo.Formatos.Cuaderno43`: el multiregistro (`orden: :libre`,
  discriminador en 1-2) con un layout de 80 posiciones por tipo (11, 22,
  23, 24, 33, 88) con los nombres de la norma en `snake_case`; fechas
  `:aammdd` con pivote 2000; importes `{céntimos, 2}` con la clave
  debe/haber aparte y `saldo/2` que los junta con signo; `libre` como
  `:relleno`; `identidad:` en la cabecera (entidad, oficina, cuenta,
  fechas). `cuentas/1` arma cuenta → movimientos → conceptos y
  equivalencias. `validar/1`: por cuenta, apuntes y totales al debe y al
  haber, saldo final = inicial + haber − debe, y entidad, oficina y cuenta
  iguales a la cabecera; en el archivo, el número de registros del 88; y
  la estructura (movimiento, complementario o final fuera de lugar, cuenta
  sin cerrar).
- `Formatos.cuaderno43/1` con la vigencia `"2012"` en el catálogo, fuente
  citada y fecha de consulta. Fixture `cuaderno43.txt` inventado: dos
  cuentas, una con tres movimientos (dos conceptos en uno, una equivalencia
  en otro) y un saldo inicial al haber, otra con saldo inicial al debe.
- Tests: lectura sin diagnósticos, `validar/1` vacío y `cuentas/1`, stream,
  identidad, 80 posiciones por línea y el viaje de ida y vuelta con
  `escribir/3` byte a byte; un saldo, un importe, una cuenta y el 88
  alterados; la estructura rota; el catálogo.
- `Formatos`, README (es y en): la promesa de Previred se reemplaza por lo
  que es y por el criterio del siguiente. CHANGELOG.

## Decisiones tomadas

1. El saldo final se verifica en céntimos con signo (`saldo/2`), no como
   tupla con clave: así "saldo inicial al debe de 100 más un haber de 500
   da 400 al haber" es una suma y no cuatro casos.
2. Los controles de cuenta se reportan en la línea del registro 33, como
   NACHA en el control de lote: es el registro que no cuadra.
3. El número de registros del 88 cuenta todos los anteriores al 88, que es
   la lectura de la norma; un archivo con otra convención lo ve como un
   diagnóstico `:control` que dice de qué se calculó.
