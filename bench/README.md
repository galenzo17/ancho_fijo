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
Elixir 1.16.3 / OTP 26.

| camino | tiempo | pico de heap |
| --- | ---: | ---: |
| `parsear/3` estricto (corta en la línea 1000) | 0,46 s | 390 MB |
| `stream/3` sobre la ruta | 7,74 s | 34 KB |
| `stream/3` sobre `File.stream!/1` | 7,94 s | 34 KB |
| `parsear/3` tolerante (todo en memoria) | 11,19 s | 1,06 GB |

`stream/3` corre en memoria constante. `parsear/3` estricto ocupa cuatro
veces el archivo para leer mil líneas: parte y numera las dos millones antes
de mirar la primera. Eso, y el costo por línea, se arreglan en el commit
siguiente.
