---
prompt: 0026
fecha: 2026-10-21T18:09:14-03:00
autor: Agustín Bereciartúa <bereciartua.agustin@gmail.com>
modelo: claude-fable-5-1
issue: 40
---

# 0026 — La identidad de un Multiregistro está en el header (issue #40)

**Contexto:** cuarta iteración del loop sobre las issues abiertas; la rama
parte de la de #39 (prompt 0025). `identidad/3` recibía solo un `Layout`,
y justo los formatos con header, que son los que traen una identidad
declarada de verdad, son multiregistro.

## Prompt

> anda a main y revisa luego las issues, arma un /loop cada issue un pr si
> es necesario, senior level ultra mega pro ultrathink

## Resultado

- `Identidad.identidad/3` con una cláusula para `%Multiregistro{}`: la
  huella y el nombre como siempre; la identidad declarada con el layout
  del primer tipo de `:registros` que tenga `identidad:`. El primer
  registro del archivo se discrimina con el multiregistro
  (`Multiregistro.discriminar/3`, público sin doc) y tiene que ser de ese
  tipo; si no, diagnóstico `:identidad` con el tipo esperado y el que
  llegó.
- `Formatos.Nacha.encabezado_de_archivo/0` declara `identidad:` con
  `immediate_origin`, `file_creation_date`, `file_creation_time` y
  `file_id_modifier`, con la fuente en el doc de la función.
- Doctest con la fixture NACHA, tests en `identidad_test` (header, archivo
  sin header, tipo desconocido, multiregistro sin identidad, tipo que
  declara la identidad sin ser el primero) y en `nacha_test`.

## Decisiones tomadas

1. **El tipo que declara la identidad se busca, no se asume el primero.**
   La issue dejaba las dos opciones. Buscar el primero con `identidad:`
   cubre el caso común (el header es el primero y la declara) y además un
   formato donde el header va después de un registro opcional de otro
   tipo; asumir el primero de `:registros` habría obligado a declarar la
   identidad en un tipo que no la tiene.
2. **El primer registro se discrimina antes de leerlo.** Leer la primera
   línea directamente con el layout del header, cuando la línea es un
   detalle, falla con diagnósticos de campos que no explican nada. Un
   diagnóstico `:identidad` que diga "se esperaba un `:encabezado_de_archivo`,
   llegó `:entrada`" sí.
3. **Cuatro campos y no cinco en la identidad NACHA.** La especificación
   define el *File ID Modifier* para distinguir archivos del mismo
   originador en el mismo día; con el origen, la fecha y la hora es la
   identidad que el emisor declara. El *Immediate Destination* no
   identifica el archivo sino a quién va dirigido, y quedó fuera.
