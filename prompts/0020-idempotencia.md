---
prompt: 0020
fecha: 2026-10-16T19:43:29-03:00
autor: Agustín Bereciartúa <bereciartua.agustin@gmail.com>
modelo: claude-fable-5-1
issue: 11
---

# 0020 — Idempotencia de lotes (issue #11)

**Contexto:** el mismo archivo procesado dos veces es el error más caro de
una nómina, y la librería es la que ve el archivo completo antes de que
exista un registro en la base. La huella del lote llegó con la
trazabilidad (#7, prompt 0009 de esta rama), y esta issue la usa.

## Prompt

El `/loop` que gobierna la serie de issues, sin prompt propio para esta:

> y arma un /loop de cada issue que necesita un pr armalo y que sea senior
> level planifica monitorewa senio senior

## Resultado

- `AnchoFijo.Identidad` con `identidad/3`, `cotejar/2` y `duplicada?/2`;
  `AnchoFijo.identidad/3` delega.
- Opción `identidad: [campos: [...]]` en `AnchoFijo.Layout`, validada
  contra los campos del layout; lo declarado se lee del primer registro.
- Diagnóstico `:identidad` para el conflicto y el archivo vacío.
- 13 tests; sección "Idempotencia" en el README con la frontera.

## Decisiones tomadas

1. **Tres fuentes, y la huella manda.** Lo declarado es lo más confiable
   cuando existe, pero decide el contenido: el mismo contenido es el mismo
   archivo aunque cambie el nombre o alguien haya tocado el número de lote.
   El nombre no decide nada: dos nóminas distintas se llaman `nomina.txt`
   todos los días. Queda en la identidad para que el mensaje de rechazo
   pueda nombrar el archivo.

2. **Conflicto, no duplicado.** La misma identidad declarada con otra
   huella es el caso interesante de la issue, y es peor que un duplicado:
   o el emisor reutilizó el número de lote o alguien editó el archivo.
   `cotejar/2` lo devuelve aparte, con un diagnóstico que nombra la
   identidad y las dos huellas, y `duplicada?/2` responde `false`, para que
   nadie lo trate como un reproceso inocuo.

3. **Sin estado ni persistencia.** La librería recibe las identidades ya
   vistas y responde. El día en que un parser abre una tabla o un ETS deja
   de ser un parser y además decide por el usuario cuánto recordar y qué
   hacer. Eso es del sistema que paga, y el README lo dice con esas
   palabras. Lo que hay que guardar son dos binarios y un mapa chico.

4. **La identidad declarada sale del primer registro.** Sin multiregistro
   en esta rama, "el header" es la primera línea con contenido, leída con
   el mismo layout (respetando `:saltar`). Cuando multiregistro (#1) esté
   en `main`, lo natural es que `identidad:` pueda apuntar al registro
   `:header`; es un cambio pequeño que vale su propio commit.

5. **Un primer registro ilegible es su diagnóstico de línea; un archivo
   vacío, uno de identidad.** No hay lote que identificar sin un primer
   registro, y mezclar eso con "la línea no mide" confundiría.

6. **La huella se calcula aparte, por bloques.** `Traza.huella/2` lee el
   archivo por bloques y `declarada/3` lee solo la primera línea con
   `Entrada.lineas/2`, lazy. Dos lecturas, ninguna carga el archivo.
