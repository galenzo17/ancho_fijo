defmodule AnchoFijo.EscrituraEnBytesTest do
  # El error clásico de un escritor de ancho fijo es medir caracteres cuando
  # el archivo se mide en bytes. Cada test escribe un texto con caracteres de
  # uno, dos, tres y cuatro bytes y mide la línea resultante en la unidad del
  # layout: la garantía es el largo exacto, no la forma del texto.
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias AnchoFijo.Diagnostico
  alias AnchoFijo.Layout

  defp layout(opts \\ [], campo \\ []) do
    Layout.nuevo!(Keyword.merge([campos: [Keyword.merge([nombre: :g, largo: 4], campo)]], opts))
  end

  defp escribir(layout, valor, opts \\ []), do: AnchoFijo.escribir(layout, [%{g: valor}], opts)

  describe "unidad :bytes en UTF-8 (el default)" do
    test "un carácter de dos bytes ocupa dos posiciones y el relleno completa el resto" do
      assert {:ok, <<"añ ", "\n">>, []} = escribir(layout(), "añ")
      assert {:ok, "ññ\n", []} = escribir(layout(), "ññ")
      assert {:ok, linea, []} = escribir(layout(), "añ")
      assert byte_size(linea) == 5
    end

    test "cuatro letras con tilde no caben en cuatro bytes, y el diagnóstico dice las dos medidas" do
      assert {:error, [%Diagnostico{campo: :g} = d]} = escribir(layout(), "José")

      assert d.causa_probable ==
               "el valor no cabe en el campo: 5 posiciones en 4 (5 bytes, 4 caracteres)"

      # Con solo ASCII el mensaje no agrega nada.
      assert {:error, [d]} = escribir(layout(), "Josef")
      assert d.causa_probable == "el valor no cabe en el campo: 5 posiciones en 4"
    end

    test "truncar: true corta en una frontera de carácter y completa el byte que sobra" do
      assert {:ok, "a€\n", [a]} = escribir(layout(), "a€bc", truncar: true)
      assert a.tipo == :campo_truncado
      assert a.causa_probable =~ "sobraban 2 (6 bytes, 4 caracteres)"
      assert {:ok, <<"añ ", "\n">>, [_]} = escribir(layout(), "añño", truncar: true)
      assert {:ok, <<"😀", "\n">>, [_]} = escribir(layout(), "😀x", truncar: true)
      assert {:ok, <<"a   ", "\n">>, [_]} = escribir(layout(), "a😀", truncar: true)
    end

    test "trim: false exige el largo exacto en bytes, no en caracteres" do
      exacto = layout([], trim: false, largo: 3)
      assert {:ok, "añ\n", []} = escribir(exacto, "añ")
      assert {:ok, "abc\n", []} = escribir(exacto, "abc")
      assert {:error, [d]} = escribir(exacto, "añb")
      assert d.esperado == "un texto de hasta 3 posiciones"
      assert {:error, [d]} = escribir(exacto, "ab")
      assert d.esperado == "un texto de exactamente 3 posiciones (trim: false)"
    end

    test "un relleno de dos bytes no puede completar el campo: advertencia del layout y error al escribir" do
      layout = layout([], relleno: "·")
      assert [%Diagnostico{tipo: :layout, campo: :g} = advertencia] = layout.advertencias

      assert advertencia.esperado ==
               "un :relleno de un byte, porque el layout mide en bytes en UTF-8"

      assert {:error, [%Diagnostico{tipo: :layout, campo: :g} = d]} = escribir(layout, "ab")
      assert d.causa_probable =~ "el relleno mide 2 bytes y hay 2 posiciones por completar"

      # Si no hay nada que completar, se escribe igual.
      assert {:ok, "abcd\n", []} = escribir(layout, "abcd")

      # Lo mismo para un campo de relleno y para una constante.
      relleno = Layout.nuevo!(campos: [[nombre: :r, largo: 3, tipo: :relleno, relleno: "·"]])
      assert {:error, [%Diagnostico{tipo: :layout, campo: :r}]} = AnchoFijo.escribir(relleno, [%{}])

      constante =
        Layout.nuevo!(campos: [[nombre: :c, largo: 3, tipo: :constante, valor: "A", relleno: "·"]])

      assert {:error, [%Diagnostico{tipo: :layout, campo: :c}]} =
               AnchoFijo.escribir(constante, [%{}])
    end
  end

  describe "unidad :caracteres" do
    test "se cuentan grafemas, y la línea puede tener más bytes que posiciones" do
      layout = layout(unidad: :caracteres)
      assert {:ok, "añoo\n", []} = escribir(layout, "añoo")
      assert {:ok, linea, []} = escribir(layout, "añoo")
      assert String.length(linea) == 5 and byte_size(linea) == 6

      assert {:error, [d]} = escribir(layout, "añooo")

      assert d.causa_probable ==
               "el valor no cabe en el campo: 5 posiciones en 4 (6 bytes, 5 caracteres)"

      assert {:ok, "añoo\n", [_]} = escribir(layout, "añooo", truncar: true)
      assert {:ok, "😀abc\n", []} = escribir(layout, "😀abc")
    end

    test "un relleno de dos bytes sí sirve: mide un carácter" do
      layout = layout([unidad: :caracteres], relleno: "·")
      assert layout.advertencias == []
      assert {:ok, "ab··\n", []} = escribir(layout, "ab")
    end
  end

  describe "encoding :latin1" do
    test "el valor se transcodifica antes de medir: una ñ es un byte" do
      layout = layout(encoding: :latin1)
      assert {:ok, <<"a", 241, "oo", "\n">>, []} = escribir(layout, "añoo")
      assert {:ok, <<"a", 241, "  ", "\n">>, []} = escribir(layout, "añ")

      assert {:error, [d]} = escribir(layout, "añooo")
      assert d.causa_probable == "el valor no cabe en el campo: 5 posiciones en 4"

      assert {:ok, <<"a", 241, "oo", "\n">>, [_]} = escribir(layout, "añooo", truncar: true)
    end

    test "un carácter que latin-1 no tiene es un diagnóstico :encoding, no un signo de pregunta" do
      assert {:error, [%Diagnostico{tipo: :encoding, campo: :g} = d]} =
               escribir(layout(encoding: :latin1), "a€")

      assert d.recibido == "\"€\" en la posición 2 del valor"
    end

    test "un relleno latin-1 de un byte, como el punto medio, sirve" do
      layout = layout([encoding: :latin1], relleno: "·")
      assert layout.advertencias == []
      assert {:ok, <<"ab", 183, 183, "\n">>, []} = escribir(layout, "ab")
    end

    test "con relleno_final: :tolerar, el relleno latin-1 que el escritor completa el lector lo repone" do
      layout =
        Layout.nuevo!(
          encoding: :latin1,
          relleno_final: :tolerar,
          campos: [[nombre: :a, largo: 3], [nombre: :g, largo: 5, relleno: "·"]]
        )

      assert layout.advertencias == []

      assert {:ok, <<"abcxy", 0xB7, 0xB7, 0xB7, "\n">> = linea, []} =
               AnchoFijo.escribir(layout, [%{a: "abc", g: "xy"}])

      assert {:ok, [%{a: "abc", g: "xy"}], []} = AnchoFijo.parsear(layout, linea)

      assert {:ok, [%{a: "abc", g: "xy"}], [%Diagnostico{tipo: :relleno_completado}]} =
               AnchoFijo.parsear(layout, "abcxy\n")

      # Con el encoding declarado en el campo, lo mismo.
      por_campo =
        Layout.nuevo!(
          relleno_final: :tolerar,
          campos: [[nombre: :a, largo: 3], [nombre: :g, largo: 5, relleno: "·", encoding: :latin1]]
        )

      assert por_campo.advertencias == []
      assert {:ok, [%{a: "abc", g: "xy"}], [_]} = AnchoFijo.parsear(por_campo, "abcxy\n")

      # En UTF-8 midiendo bytes, "·" son dos bytes y no se repone: el layout avisa.
      utf8 =
        Layout.nuevo!(
          relleno_final: :tolerar,
          campos: [[nombre: :a, largo: 3], [nombre: :g, largo: 5, relleno: "·"]]
        )

      assert [%Diagnostico{campo: :g}] = utf8.advertencias
      assert {:error, [%Diagnostico{tipo: :largo_de_linea}]} = AnchoFijo.parsear(utf8, "abcxy\n")
    end

    test "un relleno que no existe en latin-1 es una advertencia del layout, un diagnóstico al escribir y no se repone" do
      layout =
        Layout.nuevo!(
          encoding: :latin1,
          relleno_final: :tolerar,
          campos: [[nombre: :g, largo: 4, relleno: "€"]]
        )

      assert [%Diagnostico{tipo: :layout, campo: :g} = d] = layout.advertencias

      assert d.esperado ==
               "un :relleno que exista en latin-1, porque el campo se escribe en latin-1"

      assert {:error, [%Diagnostico{tipo: :encoding, campo: :g}]} = escribir(layout, "ab")
      assert {:error, [%Diagnostico{tipo: :largo_de_linea}]} = AnchoFijo.parsear(layout, "ab\n")
    end

    test "el encoding por campo manda sobre el del layout al medir y al transcodificar" do
      layout =
        Layout.nuevo!(campos: [[nombre: :g, largo: 4, encoding: :latin1], [nombre: :h, largo: 4]])

      assert {:ok, <<"a", 241, "oo", "añ ", "\n">>, []} =
               AnchoFijo.escribir(layout, [%{g: "añoo", h: "añ"}])

      assert {:error, [%Diagnostico{campo: :h}]} =
               AnchoFijo.escribir(layout, [%{g: "añoo", h: "añoo"}])
    end

    test "el signo al final y los dígitos son ASCII en los dos encodings" do
      for encoding <- [:utf8, :latin1] do
        layout =
          Layout.nuevo!(
            encoding: encoding,
            campos: [[nombre: :m, largo: 8, tipo: :decimal, precision: 2, signo: :final]]
          )

        assert {:ok, "0123456-\n", []} = AnchoFijo.escribir(layout, [%{m: {-123_456, 2}}])
      end
    end
  end

  describe "propiedad" do
    @alfabeto ["a", "Z", " ", "ñ", "é", "·", "€", "😀", "ü"]
    @latin1 ["a", "Z", " ", "ñ", "é", "·", "ü"]

    defp medir(linea, %Layout{unidad: :caracteres}), do: String.length(linea)
    defp medir(linea, _layout), do: byte_size(linea)

    property "con relleno_final: :tolerar, lo que el escritor completa con cualquier relleno el lector lo repone" do
      configuraciones = [
        {[], @alfabeto, [" ", "0", "*"]},
        {[unidad: :caracteres], @alfabeto, [" ", "·", "ü", "€"]},
        {[encoding: :latin1], @latin1, [" ", "·", "ü", "ñ"]}
      ]

      check all(
              {opts, alfabeto, rellenos} <- member_of(configuraciones),
              relleno <- member_of(rellenos),
              largo <- integer(1..8),
              texto <- alfabeto |> member_of() |> list_of(max_length: 8) |> map(&Enum.join/1)
            ) do
        layout =
          Layout.nuevo!(
            Keyword.merge(
              [
                relleno_final: :tolerar,
                campos: [[nombre: :a, largo: 2], [nombre: :g, largo: largo, relleno: relleno]]
              ],
              opts
            )
          )

        assert layout.advertencias == []
        texto = String.replace(texto, relleno, "x")

        {:ok, linea, _} = AnchoFijo.escribir(layout, [%{a: "ab", g: texto}], truncar: true)
        assert {:ok, [%{g: leido}], []} = AnchoFijo.parsear(layout, linea)

        recortada =
          linea
          |> String.trim_trailing("\n")
          |> String.trim_trailing(relleno_codificado(relleno, layout))

        assert {:ok, [%{g: ^leido}], _} = AnchoFijo.parsear(layout, recortada <> "\n")
      end
    end

    defp relleno_codificado(relleno, %Layout{encoding: :latin1, unidad: :bytes}),
      do: :unicode.characters_to_binary(relleno, :utf8, :latin1)

    defp relleno_codificado(relleno, _layout), do: relleno

    property "con truncar: true, cada línea mide exactamente el largo del layout en su unidad" do
      configuraciones = [
        {[], @alfabeto},
        {[unidad: :caracteres], @alfabeto},
        {[encoding: :latin1], @latin1}
      ]

      check all(
              {opts, alfabeto} <- member_of(configuraciones),
              largo <- integer(1..12),
              texto <- alfabeto |> member_of() |> list_of(max_length: 12) |> map(&Enum.join/1)
            ) do
        layout = Layout.nuevo!(Keyword.merge([campos: [[nombre: :g, largo: largo]]], opts))

        assert {:ok, linea, _} = AnchoFijo.escribir(layout, [%{g: texto}], truncar: true)
        assert medir(linea, layout) == largo + 1

        assert String.valid?(
                 :unicode.characters_to_binary(
                   linea,
                   if(layout.encoding == :latin1, do: :latin1, else: :utf8)
                 )
               )

        assert {:ok, [%{g: leido}], _} = AnchoFijo.parsear(layout, linea)
        assert String.starts_with?(String.trim(texto), leido) or leido == ""
      end
    end
  end
end
