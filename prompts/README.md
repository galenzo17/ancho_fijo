# Historia de prompts

Este directorio guarda el registro de los prompts que dieron origen a cada
cambio significativo de la librería. La idea es que el "porqué" de una decisión
de diseño no viva solo en el código o en la memoria de quien lo escribió.

## Convención

Un archivo por prompt, numerado en orden cronológico:

```
prompts/NNNN-titulo-en-kebab-case.md
```

Cada archivo tiene:

- **Fecha** y **contexto** breve.
- El **prompt literal**, sin editar, en un bloque de cita o de código.
- **Resultado**: qué se produjo o cambió a partir de él.
- **Decisiones tomadas**: lo que hubo que resolver y no venía en el prompt.

El prompt se transcribe literal a propósito. Reescribirlo en prosa limpia
elimina justamente la ambigüedad que después explica por qué el código quedó
como quedó.

## Índice

| # | Prompt | Resultado |
| --- | --- | --- |
| [0001](0001-creacion-inicial-libreria.md) | Creación de la librería desde cero | `0.1.0` completa: layout, detector, parser, tests, docs |
| [0002](0002-directorio-de-prompts.md) | Mantener un directorio de prompts | Este directorio y su convención |
| [0003](0003-crear-el-repo.md) | Crear el repositorio, privado | `git init`, repo privado en GitHub, `.gitattributes` |
| [0004](0004-env-vars-y-publicacion-en-hex.md) | Env vars, `.env` y publicar en Hex | `.env` ignorado, repo público, `0.1.0` en Hex |
