defmodule AnchoFijo.SuperficieTest do
  # La superficie de fallas de la API pública: qué puede escapar de una función
  # pública cuando se la llama con basura. El contrato es que solo dos cosas:
  # un diagnóstico (como valor o dentro de AnchoFijo.Error) cuando el problema
  # es de los datos, y ArgumentError cuando el problema es de la llamada.
  # Cualquier otra excepción es un bug de la librería.
  use ExUnit.Case, async: true

  alias AnchoFijo.Diagnostico
  alias AnchoFijo.Layout

  @layout Layout.nuevo!(
            campos: [
              [nombre: :codigo, largo: 2],
              [nombre: :fecha, largo: 8, tipo: :fecha, formato: :aaaammdd]
            ]
          )

  describe "opciones mal formadas: ArgumentError que nombra la función y la opción" do
    test "opts que no es keyword list" do
      assert_raise ArgumentError, ~r/parsear\/3 espera las opciones como keyword list/, fn ->
        AnchoFijo.parsear(@layout, "xx20240101\n", %{modo: :tolerante})
      end
    end

    test "opción desconocida, con la lista de las válidas" do
      error =
        assert_raise ArgumentError, fn ->
          AnchoFijo.parsear(@layout, "xx20240101\n", modos: :tolerante)
        end

      assert error.message =~ "no reconoce la opción :modos"
      assert error.message =~ ":modo, :saltar, :omitir_vacias, :desde"
    end

    test "valores de otro tipo en parsear/3" do
      for opts <- [
            [saltar: :x],
            [saltar: -1],
            [omitir_vacias: :si],
            [desde: :x],
            [modo: "estricto"]
          ] do
        assert_raise ArgumentError, ~r/parsear\/3: la opción/, fn ->
          AnchoFijo.parsear(@layout, "xx20240101\n", opts)
        end
      end
    end

    test "valores de otro tipo en stream/3" do
      for opts <- [[saltar: :x], [omitir_vacias: 1], [desde: :x], [modo: :tolerante]] do
        assert_raise ArgumentError, ~r/stream\/3/, fn ->
          AnchoFijo.stream(@layout, "xx20240101\n", opts)
        end
      end
    end

    test "valores de otro tipo en detectar/2" do
      for opts <- [
            [lineas: :x],
            [lineas: 0],
            [bytes: :x],
            [bytes: -5],
            [desde: :x],
            [layout: 42],
            [delimitadores: :x],
            [delimitadores: [42]],
            [delimitadores: [""]]
          ] do
        assert_raise ArgumentError, ~r/detectar\/2: la opción/, fn ->
          AnchoFijo.detectar("abc\ndef\n", opts)
        end
      end
    end

    test "las opciones válidas siguen pasando" do
      assert {:ok, _, _} = AnchoFijo.parsear(@layout, "xx20240101\n", modo: :tolerante, saltar: 0)
      assert {:ok, _} = AnchoFijo.detectar("abc\ndef\n", lineas: 1, bytes: 10, delimitadores: [";"])
    end
  end

  describe "definiciones mal formadas: diagnóstico :layout, nunca una excepción ajena" do
    test "el layout no es una definición" do
      for basura <- [42, nil, :atomo, "texto", [1, 2], [{:a, 2, 3}]] do
        assert {:error, [%Diagnostico{tipo: :layout}]} = Layout.nuevo(basura)
        assert {:error, [%Diagnostico{tipo: :layout}]} = AnchoFijo.parsear(basura, "xx\n")
      end
    end

    test "un elemento de :campos no es una definición" do
      for basura <- [42, nil, {:a, 2}, "a", [1, 2]] do
        assert {:error, [%Diagnostico{tipo: :layout} = diagnostico]} =
                 Layout.nuevo(campos: [basura])

        assert diagnostico.esperado == "la definición del campo como keyword list o mapa"
      end
    end

    test "una clave desconocida en el layout se reporta, no se ignora" do
      assert {:error, [diagnostico]} =
               Layout.nuevo(campos: [[nombre: :a, largo: 2]], enconding: :latin1)

      assert diagnostico.recibido == ":enconding"
      assert diagnostico.causa_probable =~ "error de tipeo"
    end

    test "una clave desconocida en un campo se reporta, no se ignora" do
      assert {:error, [diagnostico]} =
               Layout.nuevo(
                 campos: [[nombre: :a, largo: 2, tipo: :decimal, precision: 2, trimm: false]]
               )

      assert diagnostico.campo == :a
      assert diagnostico.recibido == ":trimm"
    end

    test "un Map.from_struct/1 de otro layout o campo no cuenta como claves desconocidas" do
      {:ok, layout} = Layout.nuevo(campos: [[nombre: :a, largo: 2]], nombre: "x")
      campo = hd(layout.campos)

      assert {:ok, _} = Layout.nuevo(%{Map.from_struct(layout) | nombre: "y"})
      assert {:ok, _} = Layout.nuevo(campos: [Map.from_struct(campo)])
    end

    test "valores de otro tipo en las opciones globales" do
      assert {:error, [%Diagnostico{recibido: "42"}]} =
               Layout.nuevo(campos: [[nombre: :a, largo: 2]], nombre: 42)

      assert {:error, [%Diagnostico{campo: :a}]} =
               Layout.nuevo(campos: [[nombre: :a, largo: 2, opcional: :si]])
    end
  end

  describe "entradas mal formadas: diagnóstico :entrada" do
    test "parsear/3 con algo que no es binario" do
      for basura <- [42, nil, [1], %{}] do
        assert {:error, [%Diagnostico{tipo: :entrada}]} = AnchoFijo.parsear(@layout, basura)
      end
    end

    test "detectar/2 con algo que no es binario" do
      for basura <- [42, nil, [1], %{}] do
        assert {:error, [%Diagnostico{tipo: :entrada}]} = AnchoFijo.detectar(basura)
      end
    end

    test "stream/3 con algo que no es binario ni enumerable" do
      assert [{:error, [%Diagnostico{tipo: :entrada}]}] =
               AnchoFijo.stream(@layout, 42) |> Enum.to_list()
    end

    test "stream/3 con un enumerable que no entrega binarios" do
      resultado = AnchoFijo.stream(@layout, ["xx20240101", 2, nil, %{a: 1}]) |> Enum.to_list()

      assert [{:ok, _, []}, {:error, [d2]}, {:error, [d3]}, {:error, [d4]}] = resultado
      assert Enum.map([d2, d3, d4], & &1.linea) == [2, 3, 4]
      assert Enum.all?([d2, d3, d4], &(&1.tipo == :entrada))
    end

    test "stream/3 con un mapa, que es enumerable pero no entrega binarios" do
      assert [{:error, [%Diagnostico{tipo: :entrada, linea: 1}]}] =
               AnchoFijo.stream(@layout, %{a: 1}) |> Enum.to_list()
    end
  end

  describe "datos sucios que podrían tentar a una excepción interna" do
    test "una fecha con mes 13 es diagnóstico, no un error de Date.new/3" do
      assert {:error, [%Diagnostico{campo: :fecha}]} = AnchoFijo.parsear(@layout, "xx20241399\n")
    end

    test "una fecha con letras es diagnóstico" do
      assert {:error, [%Diagnostico{campo: :fecha}]} = AnchoFijo.parsear(@layout, "xx2024ab01\n")
    end

    test "un directorio en vez de un archivo es diagnóstico" do
      assert {:error, [%Diagnostico{tipo: :entrada}]} =
               AnchoFijo.parsear(@layout, System.tmp_dir!(), desde: :archivo)
    end

    test "bytes inválidos en la muestra de detectar/2 son un reporte, no una excepción" do
      assert {:ok, %{encoding_probable: :latin1}} = AnchoFijo.detectar(<<0xFF, 0xFE, 10>>)
    end

    test "un reporte que no es tal en contrastar/2 es un error de la llamada" do
      assert_raise FunctionClauseError, fn -> AnchoFijo.Detector.contrastar(%{}, @layout) end
    end
  end
end
