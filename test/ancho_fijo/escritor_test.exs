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

    test "la respuesta con encodings mezclados por campo se vuelve a escribir byte a byte" do
      contenido = leer("respuesta_mixta.txt")

      {:ok, registros, []} =
        AnchoFijo.parsear(AnchoFijo.Fixtures.layout_respuesta_mixta(), contenido)

      assert {:ok, ^contenido, []} =
               AnchoFijo.escribir(AnchoFijo.Fixtures.layout_respuesta_mixta(), registros)

      refute String.valid?(contenido)
      assert contenido =~ "operación"
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

  describe "opciones" do
    test "un terminador que no existe es ArgumentError, no KeyError" do
      layout = [campos: [[nombre: :a, largo: 1]]]

      error =
        assert_raise ArgumentError, fn ->
          AnchoFijo.escribir(layout, [%{a: "x"}], terminador: :lf2)
        end

      assert error.message =~ "AnchoFijo.escribir/3: la opción :terminador espera"
      assert error.message =~ ":lf, :crlf, :cr o :ninguno"
    end

    test "una opción mal escrita no se ignora" do
      layout = [campos: [[nombre: :a, largo: 1]]]

      error =
        assert_raise ArgumentError, fn ->
          AnchoFijo.escribir(layout, [%{a: "xy"}], truncarr: true)
        end

      assert error.message =~ "no reconoce la opción :truncarr"
      assert error.message =~ ":terminador, :truncar"

      assert_raise ArgumentError, ~r/Escritor\.stream\/3/, fn ->
        Escritor.stream(layout, [%{a: "x"}], truncar: :si)
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

  describe "tipos propios: escribir/2 del behaviour" do
    @horas Layout.nuevo!(
             campos: [
               [nombre: :hora, largo: 4, tipo: AnchoFijo.TipoHora],
               [nombre: :exacta, largo: 6, tipo: AnchoFijo.TipoHora, segundos: true],
               [nombre: :libre, largo: 4, tipo: AnchoFijo.TipoHora, opcional: true]
             ]
           )

    test "round-trip: lo que el tipo lee, lo escribe igual" do
      linea = "0930123456    \n"
      assert {:ok, [registro], []} = AnchoFijo.parsear(@horas, linea)
      assert registro == %{hora: ~T[09:30:00], exacta: ~T[12:34:56], libre: nil}
      assert {:ok, ^linea, []} = AnchoFijo.escribir(@horas, [registro])
    end

    test "un tipo sin escribir/2 solo sabe leer, y el diagnóstico lo dice" do
      layout = Layout.nuevo!(campos: [[nombre: :x, largo: 3, tipo: AnchoFijo.TipoSoloLectura]])
      assert {:ok, [%{x: "abc"}], []} = AnchoFijo.parsear(layout, "abc\n")

      assert {:error, [d]} = AnchoFijo.escribir(layout, [%{x: "abc"}])
      assert %Diagnostico{campo: :x, linea: 1, esperado: "un tipo que implemente escribir/2"} = d
      assert d.recibido == "AnchoFijo.TipoSoloLectura"
      assert d.causa_probable =~ "solo sabe leer; implemente escribir/2"
    end

    test "un escribir/2 que devuelve {:error, causa} es un diagnóstico con esa causa" do
      assert {:error, [d]} = AnchoFijo.escribir(@horas, [%{hora: "0930", exacta: ~T[00:00:00]}])

      assert %Diagnostico{campo: :hora, esperado: "un valor que AnchoFijo.TipoHora sepa escribir"} =
               d

      assert d.recibido == ~s|"0930"|
      assert d.causa_probable == "se esperaba un Time"
    end

    test "un escribir/2 que devuelve un texto del ancho equivocado no corre la línea" do
      layout = Layout.nuevo!(campos: [[nombre: :x, largo: 3, tipo: AnchoFijo.TipoAnchoEquivocado]])

      assert {:error, [d]} = AnchoFijo.escribir(layout, [%{x: "abc"}])
      assert %Diagnostico{campo: :x, esperado: "un texto de exactamente 3 posiciones"} = d
      assert d.causa_probable =~ "no cabe"
    end

    test "el ancho del texto del tipo propio se mide en la unidad del layout" do
      layout =
        Layout.nuevo!(
          campos: [[nombre: :x, largo: 3, tipo: AnchoFijo.TipoAnchoEquivocado]],
          unidad: :caracteres
        )

      assert {:ok, "añ!\n", []} = AnchoFijo.escribir(layout, [%{x: "añ"}])
    end

    test "nil en un campo propio opcional es blanco; sin opcional, es un error" do
      assert {:ok, "0930000000    \n", []} =
               AnchoFijo.escribir(@horas, [%{hora: ~T[09:30:00], exacta: ~T[00:00:00]}])

      assert {:error, [%Diagnostico{campo: :hora}]} =
               AnchoFijo.escribir(@horas, [%{exacta: ~T[00:00:00]}])
    end
  end

  describe "un :decimal con moneda escribe un AnchoFijo.Monto" do
    @con_moneda Layout.nuevo!(
                  campos: [
                    [nombre: :clp, largo: 10, tipo: :decimal, moneda: :clp],
                    [nombre: :usd, largo: 10, tipo: :decimal, moneda: :usd, signo: :final]
                  ]
                )

    test "round-trip: parsear y escribir dan la misma línea" do
      linea = "0000125000000012500-\n"
      assert {:ok, [registro], []} = AnchoFijo.parsear(@con_moneda, linea)

      assert registro == %{
               clp: AnchoFijo.Monto.nuevo(125_000, :clp),
               usd: AnchoFijo.Monto.nuevo(-12_500, :usd)
             }

      assert {:ok, ^linea, []} = AnchoFijo.escribir(@con_moneda, [registro])
    end

    test "la tupla {unidades, precision} también se acepta, con la precisión de la moneda" do
      assert {:ok, "00001250000000012500\n", []} =
               AnchoFijo.escribir(@con_moneda, [%{clp: {125_000, 0}, usd: {12_500, 2}}])

      assert {:error, [%Diagnostico{campo: :clp} = d]} =
               AnchoFijo.escribir(@con_moneda, [%{clp: {125_000, 2}, usd: {12_500, 2}}])

      assert d.esperado == "un monto {unidades, 0} con la precisión del campo"
    end

    test "un Monto de otra moneda es un diagnóstico, no una conversión silenciosa" do
      registro = %{clp: AnchoFijo.Monto.nuevo(125_000, :usd), usd: AnchoFijo.Monto.nuevo(1, :usd)}

      assert {:error, [%Diagnostico{campo: :clp} = d]} = AnchoFijo.escribir(@con_moneda, [registro])
      assert d.esperado == "un AnchoFijo.Monto en CLP con precisión 0"
      assert d.recibido == "#AnchoFijo.Monto<1.250,00 USD>"
      assert d.causa_probable =~ "otra moneda o de otra precisión"
    end

    test "un Monto de la moneda pero con otra precisión también" do
      registro = %{
        clp: AnchoFijo.Monto.nuevo(125_000, 2, :clp),
        usd: AnchoFijo.Monto.nuevo(1, :usd)
      }

      assert {:error, [%Diagnostico{campo: :clp, recibido: "#AnchoFijo.Monto<1.250,00 CLP>"}]} =
               AnchoFijo.escribir(@con_moneda, [registro])
    end

    test "un Monto en un campo sin moneda es un valor de otro tipo" do
      layout = Layout.nuevo!(campos: [[nombre: :m, largo: 6, tipo: :decimal, precision: 2]])

      assert {:error, [%Diagnostico{esperado: "un monto {unidades, 2}"}]} =
               AnchoFijo.escribir(layout, [%{m: AnchoFijo.Monto.nuevo(100, :usd)}])
    end
  end

  describe "constantes y rellenos en un multiregistro" do
    # Header, detalle y trailer con el código de tipo como constante, un
    # literal fijo en el header y fillers en los tres.
    @formato AnchoFijo.Multiregistro.nuevo!(
               discriminador: [campo: :tipo],
               registros: [
                 header: [
                   cantidad: :uno,
                   layout: [
                     campos: [
                       [nombre: :tipo, largo: 2, tipo: :constante, valor: "01"],
                       [nombre: :literal, largo: 10, tipo: :constante, valor: "HEADER"],
                       [nombre: :fecha, largo: 8, tipo: :fecha, formato: :aaaammdd],
                       [nombre: :filler, largo: 4, tipo: :relleno]
                     ]
                   ]
                 ],
                 detalle: [
                   cantidad: :al_menos_uno,
                   layout: [
                     campos: [
                       [nombre: :tipo, largo: 2, tipo: :constante, valor: "02"],
                       [nombre: :monto, largo: 8, tipo: :entero],
                       [nombre: :ceros, largo: 3, tipo: :relleno, relleno: "0"],
                       [nombre: :glosa, largo: 11]
                     ]
                   ]
                 ],
                 trailer: [
                   cantidad: :uno,
                   layout: [
                     campos: [
                       [nombre: :tipo, largo: 2, tipo: :constante, valor: "09"],
                       [nombre: :cantidad, largo: 3, tipo: :entero],
                       [nombre: :total, largo: 8, tipo: :entero],
                       [nombre: :filler, largo: 11, tipo: :relleno]
                     ]
                   ]
                 ]
               ],
               controles: [
                 [en: :trailer, campo: :cantidad, cuenta: :detalle],
                 [en: :trailer, campo: :total, suma: {:detalle, :monto}]
               ]
             )

    @archivo "01HEADER    20240131    \n" <>
               "0200001000000PAGO ENERO \n" <>
               "0200000250000AJUSTE     \n" <>
               "0900200001250           \n"

    test "round-trip byte a byte, sin literales ni rellenos en los mapas" do
      assert {:ok, registros, []} = AnchoFijo.parsear(@formato, @archivo)

      assert [
               header: %{tipo: "01", literal: "HEADER", fecha: ~D[2024-01-31]},
               detalle: %{tipo: "02", monto: 1000, glosa: "PAGO ENERO"},
               detalle: %{tipo: "02", monto: 250, glosa: "AJUSTE"},
               trailer: %{tipo: "09", cantidad: 2, total: 1250}
             ] = registros

      refute Enum.any?(registros, fn {_, m} ->
               Map.has_key?(m, :filler) or Map.has_key?(m, :ceros)
             end)

      escritos =
        for {tipo, mapa} <- registros do
          layout = Keyword.fetch!(@formato.registros, tipo).layout
          {:ok, linea, []} = AnchoFijo.escribir(layout, [Map.drop(mapa, [:tipo, :literal])])
          linea
        end

      assert IO.iodata_to_binary(escritos) == @archivo
    end

    test "el discriminador por campo toma posición, largo y valores de las constantes" do
      assert @formato.discriminador == %{campo: :tipo, posicion: 1, largo: 2}
      assert Enum.map(@formato.registros, fn {_, d} -> d.valores end) == [["01"], ["02"], ["09"]]
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
