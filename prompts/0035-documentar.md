---
prompt: 0035
fecha: 2026-10-22T01:00:00-03:00
autor: Agustín Bereciartúa <bereciartua.agustin@gmail.com>
modelo: claude-fable-5-1
issue: 56
---

# 0035 — `mix ancho_fijo.documentar`: la especificación desde el layout (issue #56)

**Contexto:** decimotercera iteración del loop sobre las issues abiertas;
la rama parte de la de #55 (prompt 0034). La especificación del formato
vivía dos veces, en el documento para el banco y en el layout, y divergían.

## Prompt

> anda a main y revisa luego las issues, arma un /loop cada issue un pr si
> es necesario, senior level ultra mega pro ultrathink

## Resultado

- `AnchoFijo.Documentacion`: `documentar/2` en Markdown, CSV (punto y coma,
  como Excel en español) o JSON, con `idioma: :es | :en`; `a_mapa/2` como
  datos. Una tabla por tipo más los controles para un multiregistro. La
  columna de formato describe lo que define al campo: patrón de fecha,
  precisión o moneda, separador, signo, literal, carácter de relleno,
  validación del RUT, encoding propio, pivote.
- `descripcion:` y `ejemplo:` como opciones comunes de campo, validadas
  como texto e ignoradas al parsear.
- `mix ancho_fijo.documentar RUTA.exs [--formato] [--idioma]`, y
  `Mix.Tasks.AnchoFijo.Carga` con lo que comparten las dos tareas (cargar
  el `.exs`, abortar con código 2). `AnchoFijo.Json` (sin doc) con el
  encoder a mano que antes vivía en la tarea `detectar`.
- `Layout.coercer!/1`, `Layout.documentar/2`, `Multiregistro.documentar/2`.
- El README tiene la tabla generada para la fixture
  `multiregistro_sin_codigo.exs`, y un test verifica que coincida con lo
  que `documentar/2` produce: si el layout cambia, el README falla.

## Decisiones tomadas

1. **El README se verifica contra lo generado, no se genera.** Un test que
   compara la tabla del README con la salida real es más simple que una
   tarea que escriba el README, y hace que la divergencia sea un fallo de
   CI y no un olvido.
2. **La traducción cubre encabezados, tipos y la prosa de la columna de
   formato**, no los nombres de campo ni las descripciones: son del
   formato y de quien lo documenta.
3. **CSV con punto y coma.** Es lo que Excel en español espera al abrir el
   archivo; una coma produce una sola columna.
4. **El encoder JSON a mano se compartió, no se reemplazó por Jason.**
   Sigue siendo la razón de siempre: sin dependencias de runtime.
