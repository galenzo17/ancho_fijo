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

## La regresión de lectura de la 0.4.0 (issue #95)

La 0.4.0 leía menos líneas por segundo que la 0.3.1. Medido con el mismo
script sobre 300.000 líneas del layout de nómina de los fixtures (texto 10,
texto 20, decimal 10, fecha 8), mínimo de tres corridas, `Enum.each` sin
retener resultados. AMD Ryzen 7 PRO 8840U, Docker, Elixir 1.20.4 / OTP 28
(la máquina de la issue era más rápida; importan las proporciones).

| camino | 0.3.1 | 0.4.0 | después |
| --- | ---: | ---: | ---: |
| `stream/3` (`Enum.count`), líneas/ms | 323–331 | 256–273 | 303–315 |
| `parsear/3` tolerante | 1,26 s | 1,44 s | 1,24 s |
| `parsear/3` estricto | 2,24 s | 2,34 s | 2,27 s |
| `parsear/3` estricto, `traza: true` | 2,44 s | 2,60 s | 2,38 s |
| `Parser.parsear_linea/3` (la línea completa) | 2,40 µs | 3,08 µs | 2,53 µs |
| `Campo.leer` texto de 10 | 0,28 µs | 0,38 µs | 0,37 µs |
| texto de 20 | 0,39 µs | 0,53 µs | 0,53 µs |
| decimal | 0,39 µs | 0,49 µs | 0,49 µs |
| fecha | 0,78 µs | 2,23 µs | 0,80 µs |
| `Tipo.Fecha.leer/3` | 0,42 µs | 1,26 µs | 0,40 µs |
| `Campo.formatear` fecha | 1,03 µs | 3,33 µs | 0,65 µs |
| `Campo.formatear` texto de 20 | — | 0,43 µs | 0,27 µs |
| `Campo.formatear` decimal | — | 0,91 µs | 0,26 µs |
| `Escritor.escribir_linea/4` | 2,71 µs | 3,58 µs | 1,91 µs |
| `escribir/3` de 300.000 registros | 4,75 s | 5,2–5,7 s | 3,2 s |

(Los valores de 0.4.0 por pieza son los de la primera medición con este
arnés, ya con el patrón de fecha compilado una vez; con el arnés viejo, que
retenía los 300.000 resultados, `Campo.leer` fecha daba 5,3 µs.)

## Qué se encontró en la 0.4.0

3. **El patrón de fecha se compilaba en cada lectura.** `Tipo.Fecha.leer/3`
   (y `escribir/2`, `Hora`, `FechaHora`) llamaba a `Patron.compilar/1` por
   campo y por línea: tokenizar el formato, armar el mapa, chequear
   repetidos. Ahora `Campo.nuevo/1` lo compila una vez y lo guarda en
   `:formato_compilado` (un dato derivado, como `:modulo`; la serialización
   no lo emite).

4. **`Patron.leer/3` contaba grafemas dos veces.** `String.length/1` para
   el largo y `String.split_at/2` por token, y `nulo?/2` cortaba el texto
   otra vez antes de `leer/3`. Ahora, con un patrón ASCII y un texto que
   mide en bytes lo que el patrón, los tokens se cortan con `binary_part/3`
   en un solo recorrido que decide "sin dato" y lee a la vez; si algo no
   cuadra, el camino por grafemas decide y redacta el mismo mensaje de
   antes.

5. **Costos por campo y por línea que no existían.** `Reglas.del_valor/3`
   por campo y `Reglas.cruzadas/3` por línea aunque el layout no declarara
   reglas (ahora `Layout.nuevo/1` precalcula `:con_condiciones`, y un campo
   sin reglas sale en la primera cláusula); `a_utf8/2` por campo (ahora,
   si la línea entera es ASCII imprimible, el parser lo decide una vez y
   `Campo.leer/3` no transcodifica ni revisa cada tramo); dos
   `String.trim_trailing/2` por línea para quitar el terminador; y dos
   despachos por campo (`anidado?`, `relleno?`) más una tupla intermedia,
   ahora un solo despacho por el módulo del campo.

6. **El escritor pagaba por campo lo que no usaba** (issue #125). El valor
   canónico de #92 se calculaba antes de las reglas aunque el campo no
   tuviera ninguna (para un `:decimal`, llevar el valor a unidades y
   volver); `con_signo/5` contaba grafemas sobre dígitos ASCII y armaba la
   descripción de lo esperado en cada llamada, también cuando cabía;
   `Patron.escribir/3` y la fecha completaban con `String.pad_*`. Ahora el
   canónico se calcula solo con reglas, los dígitos se miden y completan
   por bytes, la descripción se arma solo si no cabe, y el escritor quedó
   un 30 % por debajo de la 0.3.1.

Lo que queda: `Campo.leer` de un `:texto` paga `revisar_doble_codificacion/3`
y las reglas por campo que la 0.3.1 no tenía: un 25 % sobre un campo de
0,4 µs.
