---
prompt: 0040
fecha: 2026-10-21T21:12:36-03:00
autor: Agustín Bereciartúa <bereciartua.agustin@gmail.com>
modelo: claude-fable-5-1
issue: 61
---

# 0040 — Gobernanza: SECURITY.md, CODEOWNERS, compatibilidad y soporte (issue #61)

**Contexto:** decimoctava iteración del loop sobre las issues abiertas; la
rama parte de la de #60 (prompt 0039). Para que un equipo de una empresa
regulada dependa del paquete tiene que poder responder quién lo mantiene,
cómo se reporta una vulnerabilidad, qué versiones de Elixir y OTP puede usar
y qué pasa cuando sale una serie nueva. Nada de eso estaba escrito.

## Prompt

> anda a main y revisa luego las issues, arma un /loop cada issue un pr si
> es necesario, senior level ultra mega pro ultrathink

## Resultado

- `SECURITY.md`: qué se considera vulnerabilidad en una librería que lee
  archivos hostiles por diseño, canal de reporte privado de GitHub (habilitado
  en el repositorio) con el correo de los commits como alternativa, plazos
  (acuse en 3 días hábiles, plan en 14), cómo se publica la corrección
  (versión nueva con `### Seguridad` en el CHANGELOG y aviso en GitHub),
  tabla de versiones con soporte y cómo se publica el paquete.
- `.github/CODEOWNERS` con el mantenedor, y `.github/dependabot.yml` para las
  dependencias de desarrollo (semanal, hasta 5 PRs) y las acciones de CI.
  Alertas de vulnerabilidades y actualizaciones de seguridad de Dependabot
  habilitadas en el repositorio.
- `mix deps.audit` (`mix_audit`, solo dev y test) en el job de calidad de la
  CI, junto a `mix hex.audit`.
- Sección "Mantenimiento, compatibilidad y soporte" en el README: quién
  mantiene, cómo reportar, matriz de Elixir y OTP (1.14/25 a 1.20/28, más la
  compilación como dependencia), qué es un cambio incompatible mientras la
  versión sea `0.x` y qué no lo es, cuánto dura una serie (la última, más
  seis meses de seguridad para la anterior si el arreglo es acotado) y la
  garantía de que solo se publica desde CI por tag.

## Decisiones tomadas

- El canal de reporte es el de GitHub y no un correo en el archivo: no filtra
  una dirección a los scrapers y queda registrado en el repositorio. El
  correo de los commits es la alternativa, señalada sin escribirla.
- La política de compatibilidad define "incompatible" por lo que obliga a
  tocar código, no por una lista de módulos: la forma de los valores, las
  opciones, los campos del diagnóstico y los mapas serializados. Agregar o
  cambiar lo `@moduledoc false` no cuenta.
- El segundo owner en Hex no se puede agregar desde el repositorio: es
  `mix hex.owner add ancho_fijo <correo>` con la credencial del dueño. Queda
  como paso del dueño en el PR, y el README no lo promete hasta que exista.
- Seis meses de seguridad para la serie anterior es una promesa que un
  mantenedor solo puede cumplir; más que eso sería escribir lo que se quiere
  leer y no lo que se va a hacer.
