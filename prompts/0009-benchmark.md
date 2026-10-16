---
prompt: 0009
fecha: 2026-10-16T19:20:16-03:00
autor: Agustín Bereciartúa <bereciartua.agustin@gmail.com>
modelo: claude-fable-5-1
issue: 6
---

# 0009 — Benchmark de `stream/3` y presupuesto de memoria (issue #6)

**Contexto:** el README prometía que `stream/3` sirve para archivos de 2 GB
sin acumular nada, sin una cifra medida. "Debería ser lazy" no es una
respuesta en una entrevista de infraestructura de pagos ni en producción.

## Prompt

El `/loop` que gobierna la serie de issues, sin prompt propio para esta:

> y arma un /loop de cada issue que necesita un pr armalo y que sea senior
> level planifica monitorewa senio senior

## Resultado

- `bench/generar.exs`: un archivo de nómina de 100 MB (o del tamaño que se
  pida) con el layout de los fixtures y una fila mala cada mil.
- `bench/parseo.exs`: Benchee para tiempo y throughput, más un medidor de
  memoria pico por proceso. Resultados, máquina y versión en
  `bench/README.md`.
- Dos cuellos de botella encontrados y arreglados en un commit aparte, con
  antes y después: `parsear/3` materializaba todas las líneas antes de mirar
  la primera, y la conversión de campos pagaba un regex por chequeo.
- Benchee como dependencia `:dev`; `bench/datos/` en `.gitignore`.

## Decisiones tomadas

1. **La memoria de Benchee no responde la pregunta.** Benchee mide la memoria
   *asignada* por el proceso durante la corrida, no la retenida: para un
   stream de dos millones de líneas da un número enorme aunque nunca haya
   más de una línea viva. La pregunta "¿cabe un archivo de 2 GB?" se
   responde con el pico del heap, así que el script corre cada camino en un
   proceso aparte y otro lo muestrea cada 10 ms. `stream/3` sobre 100 MB:
   34 KB de pico. Esa es la cifra.

2. **El primer cuello era estructural, no de CPU.** `parsear/3` hacía
   `String.split` más `Enum.with_index` sobre el archivo entero antes de
   procesar una línea: en estricto, con la primera fila mala en la línea
   1000, eso eran 0,46 s y 390 MB de heap para leer mil líneas. Ahora parte
   de a una (`Entrada.dividir_lazy/1`, `Stream.unfold` sobre
   `:binary.match` con un patrón compilado) y numera con
   `Stream.with_index`; los `Enum.reduce` de siempre consumen el stream. De
   0,46 s a 0,02 s. Hay una propiedad que verifica que las piezas son
   exactamente las de `String.split`, trailing vacío incluido.

3. **El segundo eran tres regex por línea.** `solo_digitos?` (dos o tres
   veces por campo numérico) y `fecha_nula?` costaban 0,36 µs cada uno,
   más que el resto de la conversión. Un recorrido de bytes hace lo mismo
   en nada. Y `a_utf8/2` recorría la línea dos veces en Elixir para el caso
   bueno; `String.valid?/1` es un BIF y decide ese caso antes, y la búsqueda
   de controles pasó de decodificar puntos de código a un recorrido por
   bytes, que alcanza porque sobre UTF-8 válido los únicos controles no
   ASCII son `0xC2 0x80..0x9F`. Por línea de cuatro campos: 3,2 µs a 1,9
   µs; `stream/3` sobre 100 MB, de 7,7 s a 5,2 s.

4. **`parsear/3` tolerante no mejoró, y está bien.** 11 segundos y 1,2 GB
   para 100 MB: el tiempo se va en construir dos millones de mapas y en el
   GC de un heap de ese tamaño, no en leer. Es el contrato de "todo en
   memoria"; para eso existe `stream/3`, y el README ahora lo dice con
   números.

5. **El fix va en commit aparte.** Como pedía la issue: el primer commit deja
   el benchmark y las cifras de antes; el segundo, los arreglos y las de
   después. Quien lea la historia ve qué cambió y cuánto.

6. **Sin `eprof`.** La imagen de Docker no trae `tools`; se midió por etapa
   con `:timer.tc` sobre 50.000 líneas, que para este caso dio la misma
   información: dónde se va el tiempo de una línea.
