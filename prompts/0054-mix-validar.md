---
prompt: 0054
fecha: 2026-10-29T20:00:00-03:00
autor: Agustín Bereciartúa <bereciartua.agustin@gmail.com>
modelo: claude-fable-5-1
issue: 100
---

# 0054 — `mix ancho_fijo.validar`: ¿este archivo pasa con este layout, y qué tiene? (issue #100)

**Contexto:** duodécima iteración del segundo loop. El día uno tenía dos
comandos (`detectar`, `documentar`) y faltaba el del día a día: validar un
archivo real contra un layout y ver los diagnósticos sin abrir `iex`. Todo
existía en la librería (`stream/3`, `Diagnostico.resumen/2`, `mensaje/2`
con `audiencia:` e `idioma:`, `a_mapa/2`, la redacción de sensibles,
`Carga.cargar_layout/1`); faltaba la tarea.

## Prompt

> revisa si hay pr que mergear y luego issues por cerrar arma un /loop
> merge y sigu y luego otro, si salen issues crealas, y luego otro
> verification loop pr revie merge y asi sucesivo senior level

## Resultado

- `Mix.Tasks.AnchoFijo.Validar`: `mix ancho_fijo.validar RUTA --layout
  RUTA.exs|RUTA.json [--modo estricto|tolerante] [--lineas N] [--json]
  [--idioma es|en] [--usuario] [--revelar]`. Recorre el archivo con
  `stream/3` (`desde: :archivo`) acumulando solo las cuentas y los
  diagnósticos; en estricto corta en la primera línea con error. Un error
  de entrada antes de la primera línea (ruta inexistente) es un 2. La
  salida de texto es el `resumen.texto` como encabezado (verde, amarillo o
  rojo según el veredicto, solo en terminal), la cuenta de registros y
  líneas, y un diagnóstico por línea hasta `--lineas` (default 50) con "… y
  N más". `--json` es `{archivo, registros, lineas, resumen, diagnosticos}`
  con `a_mapa/2`. Códigos `0`, `1`, `2` como `detectar`.
- Tests con `CaptureIO` y `catch_exit`: archivo correcto (0), tres filas
  malas (1, "3 errores en 3 líneas", las tres a la vista, el RUT con DV malo
  redactado y con `--revelar` no), estricto, `--lineas 1`, `--idioma en`
  con `--usuario`, advertencias (0 con observaciones), multiregistro con
  los diagnósticos de cierre, `--json` decodificado con `Jason`, y los
  errores de uso.
- README (es y en) junto a `detectar`; CHANGELOG.

## Decisiones tomadas

1. Las cuentas que se imprimen (registros leídos, líneas) y el resumen van
   en español también con `--idioma en`: el idioma cambia el marco de los
   mensajes de diagnóstico, que es lo que `Diagnostico.mensaje/2` ofrece;
   la tarea no traduce su propia interfaz.
2. `--saltar`, `--omitir-vacias` y `--desde` no existen: la ruta es siempre
   un archivo y el default de `omitir_vacias` es el correcto para un
   archivo real.
