defmodule AnchoFijo.ParserTest do
  use ExUnit.Case, async: true

  import AnchoFijo.Fixtures

  alias AnchoFijo.Diagnostico
  alias AnchoFijo.Parser

  describe "archivo correcto" do
    test "parsea las tres filas del fixture" do
      {:ok, registros, []} = Parser.parsear(layout_nomina(), leer("nomina_correcta.txt"))

      assert registros == [
               %{
                 rut: "12345678-9",
                 beneficiario: "JUAN PEREZ SOTO",
                 monto: {125_000, 2},
                 fecha: ~D[2024-01-15]
               },
               %{
                 rut: "98765432-1",
                 beneficiario: "ANA MARIA ROJAS",
                 monto: {9_990_050, 2},
                 fecha: ~D[2024-01-15]
               },
               %{
                 rut: "11111111-1",
                 beneficiario: "PEDRO GONZALEZ",
                 monto: {45, 2},
                 fecha: ~D[2024-01-16]
               }
             ]
    end

    test "lee desde una ruta de archivo" do
      {:ok, registros, []} = Parser.parsear(layout_nomina(), ruta("nomina_correcta.txt"))

      assert length(registros) == 3
    end

    test "el archivo sin terminador final no pierde la última fila" do
      {:ok, registros, []} =
        Parser.parsear(layout_nomina(), leer("nomina_sin_terminador_final.txt"))

      assert length(registros) == 2
      assert List.last(registros).rut == "98765432-1"
    end

    test "el archivo latin-1 declarado como tal transcodifica los nombres" do
      {:ok, registros, []} =
        Parser.parsear(layout_nomina(encoding: :latin1), leer("nomina_latin1.txt"))

      assert Enum.map(registros, & &1.beneficiario) == ["JOSÉ MUÑOZ PEÑA", "MARÍA ROJAS ÑAÑEZ"]
    end
  end

  describe "modo estricto" do
    test "corta en la primera línea mala y dice cuál es" do
      {:error, [diagnostico]} = Parser.parsear(layout_nomina(), leer("nomina_fila_corta.txt"))

      assert Diagnostico.mensaje(diagnostico) ==
               "línea 2: se esperaban 48 bytes, llegaron 46; posible campo faltante o archivo delimitado"
    end

    test "es el modo por default" do
      assert Parser.parsear(layout_nomina(), leer("nomina_fila_corta.txt")) ==
               Parser.parsear(layout_nomina(), leer("nomina_fila_corta.txt"), modo: :estricto)
    end

    test "el archivo latin-1 leído como UTF-8 falla con el byte exacto" do
      {:error, [diagnostico]} = Parser.parsear(layout_nomina(), leer("nomina_latin1.txt"))

      assert diagnostico.tipo == :encoding
      assert diagnostico.linea == 1
      assert diagnostico.causa_probable =~ "declare encoding: :latin1"
    end

    test "el CSV disfrazado falla por largo, con la causa correcta" do
      {:error, [diagnostico]} =
        Parser.parsear(layout_nomina(), leer("nomina_en_realidad_csv.csv"))

      assert diagnostico.tipo == :largo_de_linea
      assert diagnostico.linea == 1
      assert diagnostico.causa_probable =~ "archivo delimitado"
    end
  end

  describe "modo tolerante" do
    # La razón de existir del modo: una nómina de 10.000 filas con 3 malas debe
    # reportar las 3 y pagar las 9.997, no botar el lote.
    test "devuelve las filas buenas y los diagnósticos de las malas" do
      {:ok, registros, diagnosticos} =
        Parser.parsear(layout_nomina(), leer("nomina_fila_corta.txt"), modo: :tolerante)

      assert length(registros) == 2
      assert Enum.map(registros, & &1.rut) == ["12345678-9", "11111111-1"]
      assert [diagnostico] = diagnosticos
      assert diagnostico.linea == 2
    end

    test "acumula todos los errores en orden de línea" do
      layout = layout_nomina()

      contenido =
        [
          String.duplicate("X", 48),
          String.duplicate("Y", 40),
          String.duplicate("Z", 48)
        ]
        |> Enum.join("\n")

      {:ok, registros, diagnosticos} = Parser.parsear(layout, contenido, modo: :tolerante)

      assert registros == []
      assert Enum.map(diagnosticos, & &1.linea) == [1, 1, 2, 3, 3]
    end

    test "sin errores devuelve la lista de diagnósticos vacía" do
      {:ok, registros, []} =
        Parser.parsear(layout_nomina(), leer("nomina_correcta.txt"), modo: :tolerante)

      assert length(registros) == 3
    end

    test "un modo desconocido se diagnostica en vez de fallar silenciosamente" do
      {:error, [diagnostico]} =
        Parser.parsear(layout_nomina(), leer("nomina_correcta.txt"), modo: :permisivo)

      assert diagnostico.esperado == ":modo en [:estricto, :tolerante]"
    end
  end

  describe "una línea, un diagnóstico por causa" do
    # Un byte faltante corre todos los campos siguientes. Reportar los cuatro
    # campos corridos esconde el único diagnóstico que importa.
    test "una línea de largo incorrecto no reporta también sus campos" do
      {:ok, _registros, diagnosticos} =
        Parser.parsear(layout_nomina(), String.duplicate("X", 40), modo: :tolerante)

      assert length(diagnosticos) == 1
      assert hd(diagnosticos).tipo == :largo_de_linea
    end

    test "una línea del largo correcto sí reporta todos sus campos malos" do
      linea = String.pad_trailing("12345678-9JUAN", 30) <> "ABCDEFGHIJ" <> "20241332"

      {:ok, _registros, diagnosticos} =
        Parser.parsear(layout_nomina(), linea, modo: :tolerante)

      assert Enum.map(diagnosticos, & &1.campo) == [:monto, :fecha]
    end
  end

  describe "opciones" do
    test "saltar/1 ignora las líneas de header" do
      contenido = "ENCABEZADO\n" <> "AAA111\nBBB222\n"
      layout = [campos: [[nombre: :sigla, largo: 3], [nombre: :numero, largo: 3, tipo: :entero]]]

      {:ok, registros, []} = Parser.parsear(layout, contenido, saltar: 1)

      assert registros == [%{sigla: "AAA", numero: 111}, %{sigla: "BBB", numero: 222}]
    end

    test "los números de línea siguen siendo los del archivo después de saltar" do
      contenido = "ENCABEZADO\nAAA111\nBB\n"
      layout = [campos: [[nombre: :sigla, largo: 3], [nombre: :numero, largo: 3, tipo: :entero]]]

      {:error, [diagnostico]} = Parser.parsear(layout, contenido, saltar: 1)

      assert diagnostico.linea == 3
    end

    test "omitir_vacias: false convierte las líneas en blanco en diagnósticos" do
      layout = [campos: [[nombre: :a, largo: 3]]]

      {:ok, _registros, diagnosticos} =
        Parser.parsear(layout, "AAA\n\nBBB\n", modo: :tolerante, omitir_vacias: false)

      assert Enum.map(diagnosticos, & &1.linea) == [2, 4]
    end

    test "un archivo ilegible devuelve diagnóstico de entrada" do
      {:error, [diagnostico]} =
        Parser.parsear(layout_nomina(), "/no/existe.txt", desde: :archivo)

      assert diagnostico.tipo == :entrada
    end

    test "un layout inválido devuelve sus diagnósticos sin tocar el archivo" do
      {:error, [diagnostico]} = Parser.parsear([campos: []], "cualquier cosa")

      assert diagnostico.tipo == :layout
    end
  end

  describe "unidad :caracteres" do
    test "cuenta posiciones en caracteres cuando el archivo es UTF-8 con acentos" do
      layout =
        AnchoFijo.Layout.nuevo!(
          unidad: :caracteres,
          campos: [[nombre: :nombre, largo: 10], [nombre: :monto, largo: 4, tipo: :entero]]
        )

      {:ok, registros, []} = Parser.parsear(layout, "JOSÉ MUÑOZ0100\nJUAN PEREZ0200\n")

      assert registros == [%{nombre: "JOSÉ MUÑOZ", monto: 100}, %{nombre: "JUAN PEREZ", monto: 200}]
    end

    test "el mismo archivo en bytes falla por largo, no en silencio" do
      layout =
        AnchoFijo.Layout.nuevo!(
          campos: [[nombre: :nombre, largo: 10], [nombre: :monto, largo: 4, tipo: :entero]]
        )

      {:error, [diagnostico]} = Parser.parsear(layout, "JOSÉ MUÑOZ0100\n")

      assert diagnostico.tipo == :largo_de_linea
      assert diagnostico.recibido == "16"
    end
  end

  describe "stream/3" do
    test "emite una tupla por línea" do
      resultados =
        layout_nomina()
        |> Parser.stream(leer("nomina_fila_corta.txt"))
        |> Enum.to_list()

      assert Enum.count(resultados, &match?({:ok, _registro, _advertencias}, &1)) == 2
      assert Enum.count(resultados, &match?({:error, _diagnosticos}, &1)) == 1
    end

    test "es lazy: no lee más líneas de las que se consumen" do
      contenido = String.duplicate(String.duplicate("A", 48) <> "\n", 10_000)

      resultados =
        layout_nomina(campos: [[nombre: :todo, largo: 48]])
        |> Parser.stream(contenido)
        |> Enum.take(2)

      assert length(resultados) == 2
    end

    test "acepta un File.Stream y no carga el archivo" do
      resultados =
        layout_nomina()
        |> Parser.stream(File.stream!(ruta("nomina_correcta.txt")))
        |> Enum.to_list()

      assert length(resultados) == 3
      assert Enum.all?(resultados, &match?({:ok, _registro, _advertencias}, &1))
    end

    test "recorta el terminador de cada línea del File.Stream" do
      resultados =
        layout_nomina()
        |> Parser.stream(File.stream!(ruta("nomina_correcta.txt")))
        |> Enum.to_list()

      assert {:ok, %{rut: "12345678-9"}, []} = hd(resultados)
    end

    test "un archivo ilegible es el primer elemento del stream, no una excepción" do
      assert [{:error, [diagnostico]}] =
               layout_nomina()
               |> Parser.stream("/no/existe.txt", desde: :archivo)
               |> Enum.to_list()

      assert diagnostico.tipo == :entrada
    end

    test "un layout inválido sí levanta, porque es error del programador" do
      assert_raise AnchoFijo.Error, fn -> Parser.stream([campos: []], "AAA") end
    end
  end

  describe "relleno final tolerado" do
    test "sin la opción, la glosa recortada es un error de largo" do
      {:error, [diagnostico]} =
        Parser.parsear(layout_glosa(), leer("nomina_glosa_recortada.txt"))

      assert diagnostico.tipo == :largo_de_linea
      assert diagnostico.linea == 1
    end

    test "con la opción, completa el relleno y lee las tres filas" do
      {:ok, registros, advertencias} =
        Parser.parsear(
          layout_glosa(relleno_final: :tolerar),
          leer("nomina_glosa_recortada.txt")
        )

      assert Enum.map(registros, & &1.glosa) == [
               "PAGO NOMINA ENERO",
               "ANTICIPO",
               "REEMBOLSO GASTOS MENORES OK"
             ]

      assert Enum.map(registros, & &1.monto) == [{125_000, 2}, {9_990_050, 2}, {45, 2}]
      assert length(advertencias) == 2
    end

    test "la línea que ya venía completa no genera advertencia" do
      {:ok, _registros, advertencias} =
        Parser.parsear(
          layout_glosa(relleno_final: :tolerar),
          leer("nomina_glosa_recortada.txt")
        )

      assert Enum.map(advertencias, & &1.linea) == [1, 2]
    end

    test "la advertencia dice cuántas unidades se completaron y en qué línea" do
      {:ok, _registros, [primera | _]} =
        Parser.parsear(
          layout_glosa(relleno_final: :tolerar),
          leer("nomina_glosa_recortada.txt")
        )

      assert primera.gravedad == :advertencia
      assert primera.tipo == :relleno_completado

      assert Diagnostico.mensaje(primera) ==
               "línea 1: se esperaban 60 bytes, llegaron 47; se completaron 13 bytes de " <>
                 "relleno al final de la línea; el emisor recorta los espacios finales y " <>
                 "el layout lo tolera"
    end

    test "las advertencias no impiden procesar el lote" do
      {:ok, registros, diagnosticos} =
        Parser.parsear(
          layout_glosa(relleno_final: :tolerar),
          leer("nomina_glosa_recortada.txt")
        )

      assert Diagnostico.solo_advertencias?(diagnosticos)
      assert {[], [_, _]} = Diagnostico.separar(diagnosticos)
      assert length(registros) == 3
    end

    test "el faltante que alcanza al monto sigue siendo error" do
      linea = "12345678-92024011500000012\n"

      {:error, [diagnostico]} = Parser.parsear(layout_glosa(relleno_final: :tolerar), linea)

      assert diagnostico.tipo == :largo_de_linea
      assert diagnostico.causa_probable =~ "solo 30 son relleno reponible"
    end

    test "la fecha final truncada sigue siendo error, aunque falte un solo byte" do
      # layout_nomina termina en :fecha: ahí el ancho es el dato, no relleno.
      {:error, [diagnostico]} =
        Parser.parsear(layout_nomina(relleno_final: :tolerar), leer("nomina_fila_corta.txt"))

      assert diagnostico.tipo == :largo_de_linea
      assert diagnostico.linea == 2
    end

    test "una línea más larga que el layout sigue siendo error" do
      linea = "12345678-920240115000000125000" <> String.duplicate("X", 31) <> "\n"

      {:error, [diagnostico]} = Parser.parsear(layout_glosa(relleno_final: :tolerar), linea)

      assert diagnostico.tipo == :largo_de_linea
      assert diagnostico.recibido == "61"
    end

    test "el stream también tolera, y la advertencia viaja con su registro" do
      resultados =
        layout_glosa(relleno_final: :tolerar)
        |> Parser.stream(leer("nomina_glosa_recortada.txt"))
        |> Enum.to_list()

      assert [{:ok, %{glosa: "PAGO NOMINA ENERO"}, [advertencia]} | _] = resultados
      assert advertencia.tipo == :relleno_completado
      assert Enum.count(resultados, &match?({:ok, _, []}, &1)) == 1
    end
  end

  describe "zona tolerable" do
    test "el relleno no declarado al final de la línea se puede completar" do
      layout = fn opts ->
        AnchoFijo.Layout.nuevo!(
          Keyword.merge(
            [largo: 10, campos: [[nombre: :codigo, largo: 6, tipo: :entero]]],
            opts
          )
        )
      end

      assert {:ok, [%{codigo: 123}], [_advertencia]} =
               Parser.parsear(layout.(relleno_final: :tolerar), "000123\n")

      assert {:error, [_]} = Parser.parsear(layout.([]), "000123\n")
    end

    test "un hueco entre campos también es relleno reponible" do
      # Posiciones explícitas: código 1-4, hueco 5-10 sin declarar, glosa 11-20.
      layout =
        AnchoFijo.Layout.nuevo!(
          relleno_final: :tolerar,
          campos: [
            [nombre: :codigo, posicion: 1, largo: 4, tipo: :entero],
            [nombre: :glosa, posicion: 11, largo: 10]
          ]
        )

      # Faltan 16: los 10 de la glosa más los 6 del hueco. El código no se toca.
      assert {:ok, [%{codigo: 1, glosa: ""}], [advertencia]} = Parser.parsear(layout, "0001\n")
      assert advertencia.causa_probable =~ "se completaron 16 bytes"

      # Faltan 17: el último byte es del código.
      assert {:error, [diagnostico]} = Parser.parsear(layout, "000\n")
      assert diagnostico.causa_probable =~ "solo 16 son relleno reponible"
    end

    test "un campo numérico corto no se completa ni con relleno declarado detrás" do
      layout =
        AnchoFijo.Layout.nuevo!(
          largo: 10,
          relleno_final: :tolerar,
          campos: [[nombre: :codigo, largo: 6, tipo: :entero]]
        )

      # Faltan 5: los 4 de relleno no declarado alcanzan, el quinto es del código.
      assert {:error, [diagnostico]} = Parser.parsear(layout, "00012\n")
      assert diagnostico.causa_probable =~ "solo 4 son relleno reponible"
    end

    test "la zona se detiene cuando cambia el carácter de relleno" do
      layout =
        AnchoFijo.Layout.nuevo!(
          relleno_final: :tolerar,
          campos: [
            [nombre: :codigo, largo: 4, tipo: :entero],
            [nombre: :sucursal, largo: 6, relleno: "-"],
            [nombre: :glosa, largo: 10]
          ]
        )

      assert {:ok, [%{glosa: "PAGO"}], [_]} = Parser.parsear(layout, "0001SUC---PAGO\n")
      assert {:error, [_]} = Parser.parsear(layout, "0001SUC\n")
    end

    test "completa con el carácter de relleno del campo, no con espacios" do
      layout =
        AnchoFijo.Layout.nuevo!(
          relleno_final: :tolerar,
          campos: [
            [nombre: :codigo, largo: 4, tipo: :entero],
            [nombre: :glosa, largo: 8, relleno: "*"]
          ]
        )

      assert {:ok, [%{glosa: "PAGO"}], [_]} = Parser.parsear(layout, "0001PAGO\n")
    end

    test "con unidad :bytes, un relleno que no es ASCII no se repone" do
      # "·" ocupa dos bytes en UTF-8 y uno en latin-1: duplicarlo tantas veces
      # como bytes faltan no reconstruye la línea, así que la zona se detiene.
      layout =
        AnchoFijo.Layout.nuevo!(
          relleno_final: :tolerar,
          campos: [
            [nombre: :codigo, largo: 4, tipo: :entero],
            [nombre: :glosa, largo: 8, relleno: "·"]
          ]
        )

      assert {:error, [diagnostico]} = Parser.parsear(layout, "0001PAGO\n")
      assert diagnostico.causa_probable =~ "solo 0 son relleno reponible"
    end

    test "un :texto que queda entero en blanco también es relleno" do
      layout =
        AnchoFijo.Layout.nuevo!(
          relleno_final: :tolerar,
          campos: [
            [nombre: :codigo, largo: 4, tipo: :entero],
            [nombre: :glosa, largo: 8],
            [nombre: :observacion, largo: 6, opcional: true]
          ]
        )

      assert {:ok, [%{glosa: "PAGO", observacion: nil}], [_]} =
               Parser.parsear(layout, "0001PAGO\n")
    end

    test "con unidad :caracteres cuenta caracteres, no bytes" do
      layout =
        AnchoFijo.Layout.nuevo!(
          unidad: :caracteres,
          relleno_final: :tolerar,
          campos: [
            [nombre: :monto, largo: 4, tipo: :entero],
            [nombre: :beneficiario, largo: 12]
          ]
        )

      assert {:ok, [%{beneficiario: "JOSÉ MUÑOZ"}], [advertencia]} =
               Parser.parsear(layout, "0100JOSÉ MUÑOZ\n")

      assert advertencia.recibido == "14"
      assert advertencia.causa_probable =~ "se completaron 2 caracteres"
    end
  end
end
