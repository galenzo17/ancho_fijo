# Seguridad

`ancho_fijo` lee archivos que vienen de afuera: nóminas, respuestas de bancos,
exportaciones de otros sistemas. Que el archivo sea hostil o esté roto es un
caso normal, no una excepción, y la librería está escrita para que un archivo
malformado produzca un diagnóstico, nunca una excepción sin controlar ni un
consumo de memoria proporcional al tamaño del archivo (`stream/3` procesa
línea por línea). Si encontró un caso en que eso no se cumple, es una
vulnerabilidad y queremos saberlo.

## Cómo reportar una vulnerabilidad

Use el reporte privado de GitHub:
<https://github.com/galenzo17/ancho_fijo/security/advisories/new>. Solo lo
ven los mantenedores. Si no puede usar GitHub, escriba al autor que figura en
los commits (`git log --format=%ae -1`) con el asunto `[ancho_fijo] seguridad`.

No abra un issue público para un problema de seguridad hasta que haya una
versión corregida publicada.

Incluya, si puede: la versión de `ancho_fijo`, la de Elixir y OTP, el layout
y una línea del archivo que reproduzca el problema (sin datos personales:
reemplace los valores por otros de la misma forma), y qué pasó frente a qué
esperaba.

## Qué esperar

- Acuse de recibo dentro de los 3 días hábiles.
- Evaluación y un plan (corrección, mitigación o explicación de por qué no es
  una vulnerabilidad) dentro de los 14 días.
- La corrección se publica en Hex como una versión nueva de la última serie
  publicada, con una entrada `### Seguridad` en el `CHANGELOG.md` que describe
  el problema, las versiones afectadas y el crédito a quien lo reportó, si lo
  quiere. Se publica también un aviso de seguridad en GitHub.
- Si el arreglo es acotado, se publica además una corrección para la serie
  anterior durante los seis meses siguientes a la publicación de la serie
  nueva. Ver la política de compatibilidad en el README.

## Versiones con soporte

| Versión | Soporte                                                          |
| ------- | ---------------------------------------------------------------- |
| 0.4.x   | Correcciones y seguridad                                         |
| 0.3.x   | Solo seguridad, hasta el 2027-04-23 (seis meses después de 0.4.0) |
| < 0.3   | Sin soporte: actualice, el CHANGELOG dice qué cambia             |

La tabla se actualiza en el mismo PR que sube `@version`: `release.yml` no
publica un tag cuya serie no esté acá, y un test de la suite lo verifica
antes.

## Cómo se publica

Cada versión la publica el workflow `release.yml` cuando se empuja un tag
`vX.Y.Z`, después de verificar que el tag coincide con `@version` en `mix.exs`,
que el CHANGELOG tiene una sección para esa versión y que esta tabla nombra
la serie, y de correr la suite una vez más. Nadie publica a mano desde su máquina. El paquete no tiene
dependencias de runtime; `:decimal` y `:telemetry` son opcionales y se
declaran en el proyecto que las usa.

Las dependencias de desarrollo y de CI se revisan con `mix hex.audit`
(paquetes retirados) y `mix deps.audit` (avisos de seguridad conocidos) en
cada corrida de CI, y Dependabot abre PRs cuando hay una versión nueva. El
flujo completo de una versión está en
[CONTRIBUTING.md](https://github.com/galenzo17/ancho_fijo/blob/main/CONTRIBUTING.md).
