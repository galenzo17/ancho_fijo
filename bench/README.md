# Benchmarks

```
mix run bench/generar.exs        # 100 MB en bench/datos/ (en .gitignore)
mix run bench/parseo.exs         # tiempo (Benchee) y pico de memoria por camino
```

`bench/parseo.exs` mide dos cosas distintas. Benchee da tiempo y throughput.
La memoria que reporta Benchee es la *asignada* durante la corrida, no la
retenida: para un stream de dos millones de líneas es un número grande aunque
nunca haya más de una línea viva. La pregunta que importa, "¿cabe un archivo
de 2 GB?", se responde con el **pico del heap**: el script corre cada camino
en un proceso aparte y otro lo muestrea cada 10 ms.

## Resultados

Archivo de 100 MB, 2.040.816 líneas de 48 bytes (rut, beneficiario, monto
decimal, fecha), una fila mala cada mil. AMD Ryzen 7 PRO 8840U, Docker,
Elixir 1.16.3 / OTP 26. Antes y después de los dos arreglos del PR de la
issue #6.

| camino | tiempo antes | tiempo después | pico de heap antes | después |
| --- | ---: | ---: | ---: | ---: |
| `parsear/3` estricto (corta en la línea 1000) | 0,46 s | 0,02 s | 390 MB | 147 KB |
| `stream/3` sobre la ruta | 7,74 s | 5,17 s | 34 KB | 34 KB |
| `stream/3` sobre `File.stream!/1` | 7,94 s | 5,18 s | 34 KB | 34 KB |
| `parsear/3` tolerante (todo en memoria) | 11,19 s | 11,28 s | 1,06 GB | 1,25 GB |

Throughput de `stream/3` después: 19 MB/s, 395.000 líneas por segundo, con
un pico de heap que no depende del tamaño del archivo. El binario de 100 MB
que `parsear/3` lee vive fuera del heap (es un binario con contador de
referencias), así que el pico de `parsear/3` estricto mide lo que la
librería construye encima: antes, la lista de dos millones de sub-binarios
con su índice; después, mil.

## Qué se encontró

1. **`parsear/3` materializaba todas las líneas antes de mirar la primera.**
   `String.split` más `Enum.with_index` sobre el archivo entero, y recién
   entonces el `reduce_while` que corta. Ahora parte de a una
   (`Entrada.dividir_lazy/1`) y numera con `Stream.with_index`; en modo
   estricto lee mil líneas y termina.

2. **Tres regex por línea.** `solo_digitos?` y la detección de fecha en
   ceros costaban 0,36 µs cada uno, más que el resto de la conversión del
   campo. Recorridos de bytes. Y la validación UTF-8 recorría la línea dos
   veces en Elixir para el caso bueno; `String.valid?/1` lo decide antes.
   Por línea: de 3,2 µs a 1,9 µs.

`parsear/3` tolerante no mejora: el tiempo se va en construir dos millones
de mapas y en el GC de un heap de más de un gigabyte, no en leer. Es el
contrato de "todo en memoria"; para archivos grandes existe `stream/3`.

## `traza: true` en estricto (issue #96)

Con `traza: true`, `parsear/3` partía y numeraba todas las líneas antes de
leer la primera (`Regex.split` con capturas, `chunk_every`, `map_reduce`):
lo que la issue #6 había arreglado para el camino sin traza se perdía con
traza. Ahora `Parser.numerar/2` con traza sale del mismo recorrido lazy
que parte las líneas (`Entrada.dividir_lazy_con_offset/1`), con el offset
de cada una en el acumulador.

Contenido en memoria de 500.000 líneas de 48 bytes (24 MB) con la primera
fila mala, modo estricto. AMD Ryzen 7 PRO 8840U, Docker, Elixir 1.20.4 /
OTP 28. Pico de heap muestreado cada 5 ms en un proceso aparte.

| camino | tiempo antes | tiempo después | pico de heap antes | después |
| --- | ---: | ---: | ---: | ---: |
| `parsear/3` estricto con `traza: true` | 700–820 ms | < 10 ms | 210–280 MB | ~5 KB |
| `parsear/3` estricto sin traza | < 1 ms | < 1 ms | ~5 KB | ~5 KB |
