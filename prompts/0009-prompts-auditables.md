---
prompt: 0009
fecha: 2026-10-16T19:00:00-03:00
autor: Agustin Bereciartua <bereciartua.agustin@gmail.com>
modelo: claude-fable-5-1
issue: 17
---

# 0009 — Historial de prompts auditable (issue #17)

**Contexto:** `prompts/` tenía diez archivos con dos convenciones: `0001` a
`0004` con la fecha en prosa y sin hora, `0005` en adelante con un
frontmatter que nadie verificaba. Los tres de esta misma tarde (`0008` a
`0010`) declaraban horas que no eran las del commit: el reloj de los
contenedores de Docker está en UTC y el del host en UTC-3, y la fecha se
escribió a mano mirando el log equivocado. Exactamente el problema que la
issue describe.

## Prompt

El `/loop` que gobierna la serie de issues, sin prompt propio para esta:

> y arma un /loop de cada issue que necesita un pr armalo y que sea senior
> level planifica monitorewa senio senior

## Resultado

- `mix prompts.verificar` en `lib/mix/tasks/prompts.verificar.ex`, excluida
  del paquete de Hex con `exclude_patterns`. Verifica numeración,
  frontmatter, fecha y autor contra `git log --diff-filter=A`, secciones
  obligatorias e índice. `--corregir` reescribe `fecha` y `autor` desde git.
- Job `prompts` en `ci.yml`, con `fetch-depth: 0` porque la verificación lee
  la historia.
- Frontmatter en `0001` a `0004` con los datos reales de sus commits y
  `modelo: no registrado`. Fecha corregida en `0008`.
- `prompts/README.md` reescrito: convención con frontmatter, flujo de dos
  commits, alcance de la garantía y las cinco decisiones.
- Test sobre un repo git temporal con `Mix.Task.rerun/2` y `CaptureIO`:
  13 tests que cubren cada falla posible y el `--corregir`.

## Decisiones tomadas

Las de la convención están en `prompts/README.md`, que es donde tienen que
vivir. Las de la implementación:

1. **Comparar instantes, no textos.** `DateTime.from_iso8601/1` sobre las dos
   fechas y `DateTime.compare/2`. Una fecha copiada con otro huso horario es
   la misma fecha; exigir igualdad textual habría convertido una diferencia
   de presentación en una falla de auditoría.

2. **El email verifica, el nombre no.** Los commits del repo tienen
   `Agustin Bereciartua` y `Agustín Bereciartúa` con el mismo email. Verificar
   el nombre habría fallado en los commits viejos por una tilde.

3. **`git log` con `-C` y el archivo relativo al directorio.** La tarea
   acepta `--directorio` para que los tests trabajen sobre un repo temporal;
   `git -C <dir>` encuentra el repo desde cualquier subdirectorio y evita
   calcular rutas relativas a la raíz.

4. **El último de la lista, no el primero.** `--diff-filter=A` lista los
   commits que agregaron el archivo, del más nuevo al más viejo. Si alguna
   vez se borró y se volvió a agregar, el que vale es el primero de la
   historia.

5. **Flujo de dos commits en vez de `git commit --date`.** La fecha que vale
   no se conoce antes del commit. Se podría commitear con `--date` igual a la
   del frontmatter, pero eso es mentirle a git para que coincida con el
   archivo, al revés de lo que la convención dice. `--corregir` después del
   commit hace lo contrario: el archivo copia a git. Este mismo prompt se
   agregó así: el primer commit lo trae con una fecha aproximada, el
   siguiente la corrige.

6. **Sin verificar firmas.** `%G?` necesita las claves públicas en la
   máquina que verifica; en CI no están. Prometer verificación de firmas y
   no cumplirla sería lo que el README llama exagerar la garantía. Se
   documenta que existen desde el 0008 y cómo verlas a mano.
