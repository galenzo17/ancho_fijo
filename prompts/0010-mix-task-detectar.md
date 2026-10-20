---
prompt: 0010
fecha: 2026-10-16T18:19:54-03:00
autor: Agustín Bereciartúa <bereciartua.agustin@gmail.com>
modelo: claude-fable-5-1
issue: 15
---

# 0010 — `mix ancho_fijo.detectar` (issue #15)

**Fecha:** 2026-10-16
**Contexto:** `detectar/2` está pensado para el día uno de una integración,
pero usarlo exige un proyecto compilado, `iex` y tres líneas. El operador que
recibió el archivo por correo quiere un comando.

## Prompt

El `/loop` que gobierna la serie de issues, sin prompt propio para esta:

> y arma un /loop de cada issue que necesita un pr armalo y que sea senior
> level planifica monitorewa senio senior

## Resultado

- `Mix.Tasks.AnchoFijo.Detectar` en `lib/mix/tasks/ancho_fijo.detectar.ex`,
  con `@shortdoc`, `@moduledoc` con uso, opciones y códigos de salida.
- Opciones `--lineas N`, `--bytes N`, `--layout RUTA.exs`, `--json`, con
  `OptionParser` en modo `strict`.
- Salida legible: encabezado con el veredicto (verde o rojo, solo en TTY),
  una línea de resumen y las observaciones del reporte una por línea.
- Códigos de salida `0`, `1` y `2`, documentados y testeados.
- JSON a mano, sin dependencia de runtime; `jason` entra como dependencia de
  test para validar la salida con un decoder real.
- `test/mix/tasks/ancho_fijo.detectar_test.exs` con `Mix.Task.rerun/2` y
  `ExUnit.CaptureIO`, 16 tests. Fixture `test/fixtures/layout_nomina.exs`.
- Sección "Desde la terminal" en el README, CHANGELOG, grupo "Terminal" en
  hexdocs.

## Decisiones tomadas

1. **Las opciones se llaman como las de `detectar/2`.** La issue sugería
   `--muestra N`; se usó `--lineas N` y `--bytes N`, los nombres de las
   opciones de la función. Lo que se aprende en la terminal sirve en el
   código y viceversa, y la tarea no inventa un vocabulario propio.

2. **Códigos de salida 0/1/2, como `grep` y `diff`.** `0` es "sí, parece
   ancho fijo y concuerda con el layout"; `1` es "no", con el reporte
   impreso igual, porque un veredicto negativo no es una falla de la
   herramienta; `2` es "no pude responder": ruta ilegible, layout inválido,
   opciones mal. Un script de validación previa distingue así "el archivo
   está mal" de "la validación no corrió".

3. **`exit({:shutdown, n})` y no `Mix.raise/2`.** Es la forma de fijar el
   código de salida de una tarea sin matar la VM, lo que la deja testeable
   con `catch_exit/1`. `Mix.raise/2` con `:exit_status` existe recién en
   1.14.0 y de todos modos imprime el mensaje con formato de excepción, que
   no es lo que quiere ver un operador.

4. **JSON a mano.** El reporte tiene una forma conocida: mapas, listas,
   binarios, átomos, enteros, booleanos y `nil`. Un encoder para eso son
   treinta líneas. Agregar Jason al paquete habría sido la primera
   dependencia de runtime de la librería, por un flag de una tarea que el
   usuario puede no usar nunca. Lo que sí se agregó es `jason` como
   dependencia de test, para validar la salida con un decoder de verdad: un
   encoder a mano sin eso se valida a sí mismo. Las claves enteras de
   `largos` (`%{48 => 2}`) pasan a texto porque JSON no tiene claves
   numéricas.

5. **El layout se carga en la tarea, no en la librería.** `--layout` evalúa
   un `.exs` con `Code.eval_file/1`: es el archivo del propio usuario, y
   evaluar código es cosa de la terminal, no de `detectar/2`. Un `.exs` que
   no existe, no evalúa o no devuelve un layout es un error de uso, código
   `2`, con el diagnóstico en stderr.

6. **Colores solo en TTY, sin esfuerzo propio.** `Mix.shell().info/1` pasa
   por `IO.ANSI.format/1`, que ya omite los códigos cuando Elixir detectó al
   arrancar que stdout no es una terminal. No hay que hacer nada más que no
   escribir los escapes a mano. El test lo verifica: en `CaptureIO` no hay
   `\e[`.

7. **Sin escript.** Un escript empaqueta la librería para correr sin
   proyecto, pero exige Erlang instalado igual, hay que versionarlo aparte
   y mantener otro punto de entrada. El caso de uso real es "tengo el
   proyecto de la integración y quiero mirar el archivo": ahí `mix` ya está.
   Si algún día hace falta sin proyecto, `mix escript.build` sobre un
   proyecto mínimo lo resuelve sin tocar la librería.

8. **Los desacuerdos con el layout cuentan para el veredicto.** El reporte
   de `detectar/2` los trae como observaciones en prosa; la tarea los cuenta
   (empiezan con `entrada:`) y los refleja en el encabezado ("con 1
   desacuerdo con el layout") y en el código de salida. Un archivo que es
   de ancho fijo pero no mide lo que el layout dice no pasa la validación.
