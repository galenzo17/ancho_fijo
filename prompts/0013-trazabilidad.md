---
prompt: 0013
fecha: 2026-10-16T18:44:08-03:00
autor: Agustín Bereciartúa <bereciartua.agustin@gmail.com>
modelo: claude-fable-5-1
issue: 7
---

# 0013 — Trazabilidad por registro y huella del lote (issue #7)

**Contexto:** el registro que devuelve `parsear/3` es un mapa con los valores
del layout y nada más. Los diagnósticos traen `:linea`; los registros
exitosos no, y no hay forma de volver del dato al byte del archivo. Tampoco
hay forma de decir *qué* archivo se procesó.

## Prompt

El `/loop` que gobierna la serie de issues, sin prompt propio para esta:

> y arma un /loop de cada issue que necesita un pr armalo y que sea senior
> level planifica monitorewa senio senior

## Resultado

- Opción `traza: true` en `parsear/3` y `stream/3`. Cada registro trae
  `:__traza__` con un `%AnchoFijo.Traza{linea, offset, largo}`.
- `AnchoFijo.Traza` con `nueva/3`, `linea_original/2`, `clave/0` y
  `huella/2`; `AnchoFijo.huella/2` delega.
- `Entrada.dividir_con_terminador/1`: partir conservando el terminador, que
  es lo que hace falta para saber dónde empieza la siguiente línea. Es la
  misma forma que entrega `File.stream!/1`, así que `stream/3` trata igual a
  un binario y a un archivo.
- `Campo` rechaza el nombre `:__traza__`.
- Medición sobre 100.000 líneas: sin traza el camino es el de siempre (716
  ms, 31 MB de registros); con traza, 1052 ms y 42 MB; en `stream/3`, 577
  contra 575 ms, sin diferencia medible.
- `test/ancho_fijo/traza_test.exs`: reconstrucción con `:binary.part/3` para
  LF, CRLF, CR, sin terminador final y mezclados; `:saltar` y
  `:omitir_vacias`; `File.Stream` con LF y CRLF; huella estable, sensible,
  insensible a terminadores, con CRLF partido entre bloques, y
  `normalizar: false` contra `:crypto`.

## Decisiones tomadas

1. **La traza va en una clave reservada del mapa.** Era la decisión de la
   issue, con tres opciones. La tupla `{registro, traza}` y el struct
   `%Registro{}` cambian la forma de retorno para todo el código que ya lee
   `registro.monto`, aunque sea con la opción encendida. La clave `:__traza__`
   deja el registro como está y pone la traza al lado. Los dos guiones bajos
   son la convención de Elixir para metadatos que no chocan con datos
   (`__struct__`, `__meta__` en Ecto), y el layout rechaza un campo con ese
   nombre, así que la colisión que la issue temía no puede ocurrir.

2. **Apagada no cuesta nada, y se midió.** El camino sin traza es
   literalmente el de antes: `Entrada.dividir/1` y `Enum.with_index/2`. El
   camino con traza es otro, con `dividir_con_terminador/1` y un
   `map_reduce` que arrastra el offset. Los números están en el README. La
   issue pedía "medido, no supuesto": 716 contra 1052 ms y 31 contra 42 MB
   sobre 100.000 líneas en `parsear/3`; en `stream/3` no hay diferencia
   medible.

3. **El offset en `stream/3` viaja en el acumulador de `Stream.transform/3`.**
   Sin estado global ni proceso. Y un hallazgo que cambió el diseño:
   `File.stream!/1` en modo línea convierte CRLF en LF, así que contar bytes
   sobre sus elementos corre los offsets un byte por línea en los archivos
   CRLF, que son los más comunes en banca. Con `traza: true` y una ruta,
   `stream/3` lee bloques crudos (`Stream.resource/3` sobre `IO.binread/2`,
   porque `File.stream!/3` cambió el orden de sus argumentos en 1.16) y
   parte las líneas por sí mismo, byte a byte, con el CR pendiente entre
   bloques resuelto. De paso, `stream/3` con ruta ahora lee archivos con CR
   solo. Con un `File.Stream` construido por el llamador no se puede saber;
   la doc dice que para CRLF se pase la ruta.

4. **Qué normaliza la huella.** Era "la mitad del ejercicio". El criterio: lo
   que no cambia lo que el parser lee no cambia la huella. El estilo de
   terminador (CRLF, LF, CR) y la presencia del terminador final son eso:
   `parsear/3` produce los mismos registros con cualquiera. Un archivo que
   pasó por un editor de Windows es el mismo lote, y para idempotencia (#11)
   eso es lo que importa. Lo que sí cambia la huella: un espacio de relleno
   (es un byte del registro, y con `relleno_final: :tolerar` el resultado
   depende del layout, que la huella no conoce) y el encoding (los bytes son
   el dato). `normalizar: false` da el hash de `sha256sum`, para cotejar con
   el emisor.

5. **Por bloques, con el CR partido resuelto.** `File.stream!/2` en bloques
   de 64 KB y `:crypto.hash_init/update/final`, así que un archivo de
   gigabytes no se carga. Un CRLF puede quedar partido entre dos bloques: el
   estado arrastra el CR pendiente y lo resuelve al ver el bloque siguiente.
   Hay test para eso y para el salto final.

6. **`huella/2` vive en `Traza`, no en un módulo propio.** Es la otra mitad
   de la trazabilidad —demostrar qué se procesó— y #11 (idempotencia) la va
   a usar desde ahí. Un módulo `Huella` de una función era ceremonia.
