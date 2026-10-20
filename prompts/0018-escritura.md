---
prompt: 0018
fecha: 2026-10-16T19:28:30-03:00
autor: Agustín Bereciartúa <bereciartua.agustin@gmail.com>
modelo: claude-fable-5-1
issue: 2
---

# 0018 — Escritura con el mismo layout (issue #2)

**Contexto:** la librería solo leía. Para mandarle una nómina al banco había
que generarla con el formato del anexo, que ya estaba escrito una vez: el
layout. El generador de los tests serializaba por su cuenta, con un
comentario que decía "la serialización vive acá y no en la librería a
propósito: 0.1 solo lee".

## Prompt

El `/loop` que gobierna la serie de issues, sin prompt propio para esta:

> y arma un /loop de cada issue que necesita un pr armalo y que sea senior
> level planifica monitorewa senio senior

## Resultado

- `AnchoFijo.Escritor` con `escribir/3` (todo o nada, todos los
  diagnósticos), `stream/3` (lazy) y `escribir_linea/4`.
  `AnchoFijo.escribir/3` delega.
- `AnchoFijo.Campo.formatear/3`, el inverso de `extraer/3`, por tipo:
  relleno del lado que `:trim` recorta, ceros a la izquierda y signo solo
  en negativos, decimal con separador implícito o explícito, fecha según
  `:formato`, RUT canónico (o sin guion si el campo no tiene lugar), nil en
  opcionales, encoding latin-1 con diagnóstico por carácter no
  representable, ancho medido en la unidad del layout.
- `truncar: true` solo para `:texto`, con advertencia `:campo_truncado`
  (tipo nuevo de diagnóstico).
- Tres propiedades de round-trip en `propiedades_test.exs` sobre los
  generadores existentes, y 17 tests en `escritor_test.exs`, incluido el
  round-trip byte a byte de los fixtures, el de latin-1 incluido.
- Sección "Escribir con el mismo layout" en el README.

## Decisiones tomadas

1. **Todo o nada, con todos los diagnósticos.** No hay `modo: :tolerante`
   para escribir. Una nómina con una fila menos es otro archivo, y mandarlo
   al banco es peor que no mandarlo. Pero el operador que corrige quiere la
   lista completa, así que se revisan todos los registros y se devuelven
   todos los problemas, cada uno con el número de registro como `:linea`.
   La versión lazy sí entrega el error en su posición: ahí decide el
   consumidor, igual que en `stream/3`.

2. **Lo que no cabe no se trunca, salvo `:texto` y a pedido.** Era la
   decisión de la issue, con la sugerencia de fallar por default. Se fue un
   paso más allá: un monto truncado es otro monto y un RUT truncado es otra
   persona, así que para ellos no hay opción de truncar. La glosa es lo
   único que a veces se acepta recortar, y queda una advertencia por cada
   una, con cuántas posiciones sobraban. El recorte en bytes nunca parte un
   carácter multibyte.

3. **La representación mínima más ceros.** El parser acepta `-01` como
   `{-1, 2}` en tres posiciones, así que escribir `{-1, 2}` tiene que dar
   eso y no fallar por "falta un dígito entero". Cada tipo numérico produce
   su forma mínima (los dígitos de las unidades; con separador explícito,
   entera posiblemente vacía más los decimales) y `con_signo/5` completa
   con ceros a la izquierda y pone el signo del lado declarado solo si es
   negativo. Los positivos no llevan signo: el parser no lo exige y una
   posición más de dato vale más que un `+`.

4. **La precisión no se escala.** `{100, 0}` en un campo de precisión 2 es
   un error que lo dice, no `10000` ni `1`. Escalar acá es donde se pierde
   el peso.

5. **El guion del RUT es presentación.** Los generadores producen campos
   de RUT del ancho de la representación que llegó, y hay formatos reales
   que reservan nueve posiciones para `123456785`. Se escribe canónico si
   cabe y sin guion si no; el dígito verificador nunca se omite.

6. **El round-trip es la especificación.** Tres propiedades: escribir y
   leer da los registros originales; cada línea mide el largo del layout;
   y leer una línea válida, escribirla y leerla da lo mismo. Más el
   round-trip byte a byte de los fixtures, donde el de latin-1 verifica que
   el archivo sale en latin-1 y no en UTF-8.

7. **`escribir_linea/4` es pública.** Es lo que un consumidor que ya tiene
   su propio `File` abierto o su propio batching necesita, y es lo que
   `stream/3` usa. Los huecos y el relleno final del layout se escriben en
   blanco.
