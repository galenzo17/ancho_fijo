defmodule AnchoFijo.EscritorTest do
  use ExUnit.Case, async: true

  import AnchoFijo.Fixtures, only: [layout_nomina: 0, layout_nomina: 1, leer: 1]

  alias AnchoFijo.Diagnostico
  alias AnchoFijo.Escritor
  alias AnchoFijo.Layout

  describe "round-trip con los fixtures" do
    test "la nómina correcta se vuelve a escribir byte a byte" do
      contenido = leer("nomina_correcta.txt")
      {:ok, registros, []} = AnchoFijo.parsear(layout_nomina(), contenido)

      assert {:ok, ^contenido, []} = AnchoFijo.escribir(layout_nomina(), registros)
    end

    test "la nómina latin-1 se escribe en latin-1" do
      layout = layout_nomina(encoding: :latin1)
      contenido = leer("nomina_latin1.txt")
      {:ok, registros, []} = AnchoFijo.parsear(layout, contenido)

      assert {:ok, ^contenido, []} = AnchoFijo.escribir(layout, registros)
      refute String.valid?(contenido)
    end
  end

  describe "relleno, signo y huecos" do
    test "texto a la derecha, números con ceros a la izquierda, huecos en blanco" do
      layout =
        Layout.nuevo!(
          campos: [
            [nombre: :glosa, largo: 6],
            [nombre: :codigo, posicion: 9, largo: 4, tipo: :entero],
            [nombre: :monto, largo: 8, tipo: :decimal, precision: 2]
          ],
          largo: 24
        )

      assert {:ok, "ab      0042-0001250    \n", []} =
               AnchoFijo.escribir(layout, [%{glosa: "ab", codigo: 42, monto: {-1250, 2}}])
    end

    test "trim: :izquierda rellena a la izquierda; trim: false exige el ancho exacto" do
      izquierda = Layout.nuevo!(campos: [[nombre: :a, largo: 4, trim: :izquierda, relleno: "0"]])
      assert {:ok, "00ab\n", []} = AnchoFijo.escribir(izquierda, [%{a: "ab"}])

      exacto = Layout.nuevo!(campos: [[nombre: :a, largo: 4, trim: false]])
      assert {:ok, "abcd\n", []} = AnchoFijo.escribir(exacto, [%{a: "abcd"}])
      assert {:error, [d]} = AnchoFijo.escribir(exacto, [%{a: "ab"}])
      assert d.esperado == "un texto de exactamente 4 posiciones (trim: false)"
    end

    test "signo al final y positivo sin signo" do
      layout = Layout.nuevo!(campos: [[nombre: :n, largo: 5, tipo: :entero, signo: :final]])
      assert {:ok, "0012-\n", []} = AnchoFijo.escribir(layout, [%{n: -12}])
      assert {:ok, "00012\n", []} = AnchoFijo.escribir(layout, [%{n: 12}])
    end

    test "decimal con separador explícito y fecha en los dos formatos" do
      layout =
        Layout.nuevo!(
          campos: [
            [nombre: :m, largo: 9, tipo: :decimal, precision: 2, separador: :coma],
            [nombre: :f1, largo: 8, tipo: :fecha, formato: :aaaammdd],
            [nombre: :f2, largo: 8, tipo: :fecha, formato: :ddmmaaaa]
          ]
        )

      registro = %{m: {1_234_567, 2}, f1: ~D[2024-01-31], f2: ~D[2024-01-31]}
      assert {:ok, contenido, []} = AnchoFijo.escribir(layout, [registro])
      assert contenido == "012345,672024013131012024\n"
      assert {:ok, [^registro], []} = AnchoFijo.parsear(layout, contenido)
    end

    test "rut canónico, y solo el cuerpo con dv: :ausente" do
      layout =
        Layout.nuevo!(
          campos: [
            [nombre: :r, largo: 12, tipo: :rut],
            [nombre: :c, largo: 9, tipo: :rut, dv: :ausente]
          ]
        )

      assert {:ok, "12345678-5  12345678 \n", []} =
               AnchoFijo.escribir(layout, [%{r: "12.345.678-5", c: "12345678"}])
    end

    test "nil en un campo opcional es blanco; sin opcional es error" do
      layout =
        Layout.nuevo!(
          campos: [
            [nombre: :a, largo: 3, tipo: :entero, opcional: true],
            [nombre: :b, largo: 3, tipo: :entero]
          ]
        )

      assert {:ok, "   007\n", []} = AnchoFijo.escribir(layout, [%{a: nil, b: 7}])
      assert {:ok, "   007\n", []} = AnchoFijo.escribir(layout, [%{b: 7}])

      assert {:error, [d]} = AnchoFijo.escribir(layout, [%{a: 1}])
      assert d.campo == :b
      assert d.causa_probable =~ "el registro no trae el campo"
    end

    test "terminadores" do
      layout = Layout.nuevo!(campos: [[nombre: :a, largo: 1]])

      for {terminador, texto} <- [lf: "x\ny\n", crlf: "x\r\ny\r\n", cr: "x\ry\r", ninguno: "xy"] do
        assert {:ok, ^texto, []} =
                 AnchoFijo.escribir(layout, [%{a: "x"}, %{a: "y"}], terminador: terminador)
      end
    end
  end

  describe "lo que no cabe" do
    @layout Layout.nuevo!(
              campos: [
                [nombre: :glosa, largo: 4],
                [nombre: :codigo, largo: 3, tipo: :entero],
                [nombre: :monto, largo: 5, tipo: :decimal, precision: 2]
              ]
            )

    test "un valor que no cabe produce diagnóstico con campo, posición y causa, y no escribe nada" do
      assert {:error, [glosa, codigo]} =
               AnchoFijo.escribir(@layout, [%{glosa: "demasiado", codigo: 1234, monto: {1, 2}}])

      assert %Diagnostico{tipo: :campo_invalido, linea: 1, campo: :glosa, posicion: {1, 4}} = glosa
      assert glosa.causa_probable == "el valor no cabe en el campo: 9 posiciones en 4"
      assert %Diagnostico{campo: :codigo, posicion: {5, 7}, recibido: "1234"} = codigo

      assert Diagnostico.mensaje(codigo) =~
               "se esperaban un entero de hasta 3 dígitos, llegaron 1234"
    end

    test "todos los registros se revisan y los diagnósticos traen el número de registro" do
      registros = [
        %{glosa: "a", codigo: 1, monto: {1, 2}},
        %{glosa: "b", codigo: 99_999, monto: {1, 2}},
        %{glosa: "c", codigo: 1, monto: {-99_999, 2}}
      ]

      assert {:error, [d2, d3]} = AnchoFijo.escribir(@layout, registros)
      assert {d2.linea, d2.campo} == {2, :codigo}
      assert {d3.linea, d3.campo} == {3, :monto}
      assert d3.causa_probable == "el valor no cabe en el campo: 6 posiciones en 5"
    end

    test "truncar: true recorta solo los textos y deja una advertencia" do
      registro = %{glosa: "demasiado", codigo: 1, monto: {1, 2}}

      assert {:ok, "dema00100001\n", [advertencia]} =
               AnchoFijo.escribir(@layout, [registro], truncar: true)

      assert %Diagnostico{tipo: :campo_truncado, gravedad: :advertencia, campo: :glosa} =
               advertencia

      assert advertencia.causa_probable =~ "sobraban 5"

      assert {:error, [%Diagnostico{campo: :codigo}]} =
               AnchoFijo.escribir(@layout, [%{glosa: "x", codigo: 1234, monto: {1, 2}}],
                 truncar: true
               )
    end

    test "truncar en bytes no corta un carácter multibyte a la mitad" do
      layout = Layout.nuevo!(campos: [[nombre: :g, largo: 4]])
      assert {:ok, "año\n", [_]} = AnchoFijo.escribir(layout, [%{g: "añoso"}], truncar: true)
      assert {:ok, "añ \n", [_]} = AnchoFijo.escribir(layout, [%{g: "añño"}], truncar: true)
    end

    test "precisión distinta de la del campo es error, no se escala" do
      assert {:error, [d]} =
               AnchoFijo.escribir(@layout, [%{glosa: "a", codigo: 1, monto: {100, 0}}])

      assert d.esperado == "un monto {unidades, 2} con la precisión del campo"
    end

    test "valores de otro tipo y RUT inválido" do
      assert {:error, [d]} =
               AnchoFijo.escribir(@layout, [%{glosa: "a", codigo: "7", monto: {1, 2}}])

      assert d.esperado == "un entero"

      layout = Layout.nuevo!(campos: [[nombre: :r, largo: 10, tipo: :rut]])
      assert {:error, [d]} = AnchoFijo.escribir(layout, [%{r: "12345678-9"}])
      assert d.esperado =~ "para ese cuerpo corresponde 5"
    end

    test "un carácter que latin-1 no tiene es un diagnóstico de encoding" do
      layout = Layout.nuevo!(campos: [[nombre: :g, largo: 6]], encoding: :latin1)
      assert {:error, [d]} = AnchoFijo.escribir(layout, [%{g: "ab€"}])
      assert %Diagnostico{tipo: :encoding, campo: :g} = d
      assert d.recibido == "\"€\" en la posición 3 del valor"
    end

    test "un registro que no es un mapa es un diagnóstico de entrada" do
      assert {:error, [%Diagnostico{tipo: :entrada, linea: 2, recibido: "una lista"}]} =
               AnchoFijo.escribir(@layout, [%{glosa: "a", codigo: 1, monto: {1, 2}}, [1, 2]])
    end

    test "un layout inválido es un diagnóstico de layout" do
      assert {:error, [%Diagnostico{tipo: :layout}]} = AnchoFijo.escribir([campos: []], [%{}])
    end
  end

  describe "stream/3" do
    test "emite una línea por registro, lazy, y el error en su posición" do
      layout = Layout.nuevo!(campos: [[nombre: :n, largo: 2, tipo: :entero]])
      registros = Stream.cycle([%{n: 1}, %{n: 999}])

      assert [{:ok, "01\n", []}, {:error, [%Diagnostico{linea: 2}]}, {:ok, "01\n", []}] =
               layout |> Escritor.stream(registros) |> Enum.take(3)
    end

    test "con unidad :caracteres y texto multibyte el ancho es en caracteres" do
      layout = Layout.nuevo!(campos: [[nombre: :g, largo: 4]], unidad: :caracteres)
      assert {:ok, "añ  \n", []} = AnchoFijo.escribir(layout, [%{g: "añ"}])
      assert {:ok, [%{g: "añ"}], []} = AnchoFijo.parsear(layout, "añ  \n")
    end
  end
end
