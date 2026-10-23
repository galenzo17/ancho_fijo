# Historia de prompts

Este directorio guarda el registro de los prompts que dieron origen a cada
cambio significativo de la librería. La idea es que el "porqué" de una decisión
de diseño no viva solo en el código o en la memoria de quien lo escribió.

Desde el 0009 el registro es, además, **auditable**: lo que cada archivo
declara sobre cuándo y quién se verifica contra git con
`mix prompts.verificar`, y CI lo exige.

## Convención

Un archivo por prompt, numerado en orden cronológico y correlativo, sin
saltos ni repetidos:

```
prompts/NNNN-titulo-en-kebab-case.md
```

Cada archivo empieza con un frontmatter YAML y sigue con el cuerpo:

```markdown
---
prompt: 0009
fecha: 2026-10-16T19:03:12-03:00
autor: Agustin Bereciartua <bereciartua.agustin@gmail.com>
modelo: claude-fable-5-1
issue: 17
---

# 0009 — Título

**Contexto:** breve.

## Prompt

> el prompt literal, sin editar

## Resultado

- qué se produjo o cambió

## Decisiones tomadas

1. lo que hubo que resolver y no venía en el prompt
```

- `prompt` es el número del archivo.
- `fecha` es el instante del commit que agregó el archivo, ISO 8601 con huso
  horario. **La autoridad es el commit; el frontmatter es la copia declarada**,
  para leer sin `git`.
- `autor` es `Nombre <email>`; el email es el del autor de ese commit.
- `modelo` es el modelo que respondió el prompt. Es procedencia, no autoría:
  la regla del repo de no acreditar la herramienta en commits ni PRs sigue
  intacta, porque ahí sería autoría y la autoría es de la persona. Saber con
  qué modelo se generó un cambio es exactamente el dato que uno quiere seis
  meses después, al encontrar una decisión rara. Queda acá y en ningún otro
  lado.
- `issue` es opcional.
- Las tres secciones `## Prompt`, `## Resultado` y `## Decisiones tomadas` son
  obligatorias.

El prompt se transcribe literal a propósito. Reescribirlo en prosa limpia
elimina justamente la ambigüedad que después explica por qué el código quedó
como quedó.

## Verificación

```
mix prompts.verificar
```

Revisa numeración, frontmatter, fecha y autor contra el commit que agregó cada
archivo, secciones obligatorias y que el índice de abajo liste exactamente los
archivos que hay, en orden. Cualquier discrepancia falla con código `1`: un
registro de auditoría que se contradice a sí mismo es peor que no tenerlo.
Corre como job propio en CI (`.github/workflows/ci.yml`) y bloquea el merge.

El flujo para agregar un prompt es en dos commits, porque la fecha que vale es
la del commit y no se conoce antes de hacerlo:

1. Escribir el archivo con el frontmatter (la fecha puede ser aproximada),
   agregar la fila al índice, commitear.
2. `mix prompts.verificar --corregir`, que reescribe `fecha` y `autor` con lo
   que git registró, y commitear la corrección.

La tarea vive en `lib/mix/tasks/prompts.verificar.ex` pero está excluida del
paquete de Hex (`exclude_patterns` en `mix.exs`): es del repositorio, no de la
librería.

## Alcance de la garantía

Conviene decirlo sin exagerar. Lo que la verificación prueba es que **el
frontmatter no contradice a git**. Lo que git prueba depende de cómo se
hicieron los commits:

- La fecha verificada es la de autoría (`AuthorDate`, `%aI`), que un merge o
  un rebase conservan. La de commit (`%cI`) se reescribe con cada rebase y
  no sirve. Pero `git commit --date` escribe la fecha de autoría que uno
  quiera, sin dejar rastro.
- El email verificado es el del autor del commit, que `git config` pone y
  cualquiera cambia.
- Las firmas no se verifican. Los commits desde el 0008 están firmados
  (`git log --show-signature`); los anteriores no. Verificar firmas exige
  tener las claves y es un paso aparte que esta tarea no promete.
- Un squash merge reescribe la fecha de autoría al momento del merge y rompe
  la verificación del archivo agregado. El repo mergea con merge commit, y
  tiene que seguir así.

En resumen: esto acredita disciplina y buena fe, no imposibilidad de
falsificación. Es lo mismo que garantiza un libro contable bien llevado sin
notario.

## Decisiones

Las que la convención tuvo que zanjar y no eran obvias:

1. **Varios prompts en un commit se aceptan.** `0001` y `0002` entraron en el
   mismo commit y comparten fecha. Exigir un commit por prompt sería limpio
   pero antinatural cuando el prompt y su código van juntos, y de todos
   modos la hora del commit es la única que existe: la resolución dentro de
   un commit se pierde y el orden lo da el número.
2. **El `autor` es el email de git.** Es lo único verificable. Un mapa de
   alias hacia una identidad canónica habría agregado un archivo más que
   cualquiera edita, o sea otra declaración sin verificar. El nombre es
   libre: `Agustin Bereciartua` y `Agustín Bereciartúa` son la misma persona
   con distinta configuración de git ese día.
3. **`AuthorDate`, comparada como instante.** `2026-08-06T17:42:34-04:00` y
   `2026-08-06T21:42:34Z` son la misma fecha; el huso es presentación. Por qué
   `AuthorDate` y no `CommitDate`, y hasta dónde llega, está arriba.
4. **Los prompts anteriores a la convención se completaron con datos reales.**
   `0001` a `0004` ganaron frontmatter con la fecha y el email de sus commits,
   que concuerdan con lo que decían en prosa, así que el backfill es honesto.
   `modelo: no registrado` en los cuatro: no se anotó en su momento y
   adivinarlo sería inventar un dato en un registro de auditoría.
5. **Una conversación que no produjo commit no entra.** No hay archivo que
   fechar ni commit contra el cual verificarlo. El registro es completo
   respecto de los cambios, no de las conversaciones; es la única
   completitud que se puede sostener.
6. **El número se gana al mergear.** Dos ramas en paralelo pueden escribir
   cada una "su" 0009; la verificación obliga a que cada rama sea
   correlativa por sí misma, y la segunda en llegar a `main` renumera su
   prompt al integrar. Es un `git mv` y una fila del índice, y es el precio
   de que la numeración siga siendo cronológica en `main`.

## Índice

| # | Prompt | Resultado |
| --- | --- | --- |
| [0001](0001-creacion-inicial-libreria.md) | Creación de la librería desde cero | `0.1.0` completa: layout, detector, parser, tests, docs |
| [0002](0002-directorio-de-prompts.md) | Mantener un directorio de prompts | Este directorio y su convención |
| [0003](0003-crear-el-repo.md) | Crear el repositorio, privado | `git init`, repo privado en GitHub, `.gitattributes` |
| [0004](0004-env-vars-y-publicacion-en-hex.md) | Env vars, `.env` y publicar en Hex | `.env` ignorado, repo público, `0.1.0` en Hex |
| [0005](0005-relleno-final-tolerado.md) | Issue #3: relleno final tolerado, una issue por PR | `relleno_final: :tolerar`, advertencia `:relleno_completado`, fixture |
| [0006](0006-signo-al-final.md) | Issue #4: signo al final del campo | `signo: :final` en `:entero` y `:decimal`, diagnósticos de signo mal ubicado |
| [0007](0007-tipo-rut.md) | Issue #5: tipo `:rut` | `AnchoFijo.Rut`, tipo `:rut` con `dv:`, generador y propiedades |
| [0008](0008-ci-github-actions.md) | Issue #14: CI y publicación por tag | `ci.yml` con matriz y PLT en caché, `release.yml`, umbral de cobertura |
| [0009](0009-parsear-bang-y-superficie-de-fallas.md) | Issue #16: `parsear!/3`, `AnchoFijo.Error` y la superficie de fallas | Bangs, `ArgumentError` para opciones, claves desconocidas rechazadas, test de basura |
| [0010](0010-mix-task-detectar.md) | Issue #15: `mix ancho_fijo.detectar` | Tarea Mix con `--layout`, `--json`, códigos de salida 0/1/2, test con `CaptureIO` |
| [0011](0011-prompts-auditables.md) | Issue #17: historial de prompts auditable | `mix prompts.verificar`, frontmatter verificado contra git, job en CI |
| [0012](0012-datos-sensibles.md) | Issue #8: datos personales en los diagnósticos | `sensible: true`, forma en vez de valor, `revelar: true`, `inspect` redactado |
| [0013](0013-trazabilidad.md) | Issue #7: trazabilidad por registro y huella del lote | `traza: true` con `:__traza__`, `AnchoFijo.Traza`, `huella/2` normalizada |
| [0014](0014-telemetria.md) | Issue #13: instrumentación con `:telemetry` | `AnchoFijo.Telemetria`, `span/3`, eventos de `parsear`, `detectar` y `stream`, dependencia opcional |
| [0015](0015-behaviour-tipo.md) | Issue #12: behaviour `AnchoFijo.Tipo` | Los cinco tipos como implementaciones, `tipo: MiApp.Hora`, verificación al construir el layout |
| [0016](0016-moneda.md) | Issue #9: moneda y escala | `moneda:` en `:decimal`, `AnchoFijo.Monto`, escala ISO 4217 validada, aritmética sin floats |
| [0017](0017-benchmark.md) | Issue #6: benchmark de `stream/3` y presupuesto de memoria | `bench/`, memoria constante medida, dos cuellos de botella arreglados con antes y después |
| [0018](0018-escritura.md) | Issue #2: escritura con el mismo layout | `AnchoFijo.escribir/3`, `Escritor.stream/3`, `Campo.formatear/3`, round-trip como propiedad |
| [0019](0019-multiregistro.md) | Issue #1: header, detalle y trailer | `AnchoFijo.Multiregistro`, discriminador, orden y cantidad, controles cruzados, stream con cierre |
| [0020](0020-idempotencia.md) | Issue #11: idempotencia de lotes | `AnchoFijo.Identidad`, tres fuentes, `cotejar/2` con duplicado y conflicto, sin estado |
| [0021](0021-catalogo-nacha.md) | Issue #10: catálogo de formatos reales, NACHA primero | `AnchoFijo.Formatos` con vigencias, `Formatos.Nacha` completo y validado, fixture inventado |
| [0022](0022-como-dependencia.md) | Issue #45: lo que ve un proyecto que agrega la librería | `:crypto` en `extra_applications`, `@prefijo` sin usar, job de CI "Como dependencia" |
| [0023](0023-parsear-bang-multiregistro.md) | Issue #37: `parsear!/3` con un Multiregistro | `Multiregistro.parsear!/3`, despacho en la fachada, `estructura:` en el mensaje de cierre |
| [0024](0024-multiregistro-opciones.md) | Issue #38: opciones, traza y telemetría del Multiregistro | `Opciones.validar!/3`, `traza: true`, eventos `parsear` y `stream`, `:nombre`, claves desconocidas |
| [0025](0025-escritor-opciones.md) | Issue #39: Escritor con opciones validadas y telemetría | `ArgumentError` por terminador u opción inválida, eventos `escribir` y `escribir_stream` |
| [0026](0026-identidad-multiregistro.md) | Issue #40: la identidad de un Multiregistro está en el header | `identidad/3` con `%Multiregistro{}`, `identidad:` en el header NACHA, diagnóstico por tipo inesperado |
| [0027](0027-tests-escritura-tipos.md) | Issue #41: tests de escritura para tipos propios y `Monto` | `TipoHora.escribir/2`, tipos de prueba para cada falla, generador con moneda, cobertura sin `test/support` |
| [0028](0028-campos-constantes.md) | Issue #48: campos constantes y de relleno | Tipos `:constante` y `:relleno`, discriminador por campo, literales contados por `detectar` |
| [0029](0029-fechas-y-horas.md) | Issue #49: fechas y horas con más formatos | `Tipo.Patron`, ocho formatos de fecha y patrones, `:pivote`, tipos `:hora` y `:fecha_hora` |
| [0030](0030-discriminador-sin-codigo.md) | Issue #50: discriminar sin código de tipo | `por: :largo`, `por: :posicion_en_archivo`, `por: fun`; `detectar/2` con un Multiregistro y veredicto por tipo |
