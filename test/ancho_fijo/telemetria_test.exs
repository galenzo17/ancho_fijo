defmodule AnchoFijo.TelemetriaTest do
  # No es async: el handler de telemetry es global y recibiría los eventos de
  # los parseos de cualquier otro test que corra en paralelo.
  use ExUnit.Case, async: false

  import AnchoFijo.Fixtures, only: [ruta: 1, layout_nomina: 0]

  alias AnchoFijo.Escritor
  alias AnchoFijo.Layout
  alias AnchoFijo.Telemetria

  @layout Layout.nuevo!(nombre: "códigos", campos: [[nombre: :codigo, largo: 3, tipo: :entero]])

  @eventos [
    [:ancho_fijo, :parsear, :start],
    [:ancho_fijo, :parsear, :stop],
    [:ancho_fijo, :parsear, :exception],
    [:ancho_fijo, :detectar, :start],
    [:ancho_fijo, :detectar, :stop],
    [:ancho_fijo, :stream, :start],
    [:ancho_fijo, :stream, :stop],
    [:ancho_fijo, :escribir, :start],
    [:ancho_fijo, :escribir, :stop],
    [:ancho_fijo, :escribir_stream, :start],
    [:ancho_fijo, :escribir_stream, :stop]
  ]

  setup do
    ref = :telemetry_test.attach_event_handlers(self(), @eventos)
    on_exit(fn -> :telemetry.detach(ref) end)
    {:ok, ref: ref}
  end

  test "telemetry está disponible en este build" do
    assert Telemetria.disponible?()
  end

  describe "parsear/3" do
    test "emite start y stop con las cuentas y la metadata del layout", %{ref: ref} do
      contenido = "001\nXYZ\n\n003\n"
      assert {:ok, _, _} = AnchoFijo.parsear(@layout, contenido, modo: :tolerante)

      assert_received {[:ancho_fijo, :parsear, :start], ^ref, %{system_time: _}, metadata}
      assert metadata.modo == :tolerante
      assert metadata.desde == :contenido

      assert_received {[:ancho_fijo, :parsear, :stop], ^ref, medidas, metadata}
      assert %{duration: d, lineas: 3, registros: 2, errores: 1, advertencias: 0} = medidas
      assert is_integer(d)
      assert metadata.resultado == :ok
      assert metadata.layout == "códigos"
      assert metadata.encoding == :utf8
      assert metadata.unidad == :bytes
    end

    test "en estricto con error, stop dice :error y cuenta los diagnósticos", %{ref: ref} do
      assert {:error, _} = AnchoFijo.parsear(@layout, "001\nXYZ\n")

      assert_received {[:ancho_fijo, :parsear, :stop], ^ref, medidas, %{resultado: :error}}
      assert %{lineas: 2, registros: 0, errores: 1} = medidas
    end

    test "las advertencias se cuentan aparte", %{ref: ref} do
      layout =
        Layout.nuevo!(
          relleno_final: :tolerar,
          campos: [[nombre: :a, largo: 3], [nombre: :b, largo: 3]]
        )

      assert {:ok, _, [_]} = AnchoFijo.parsear(layout, "abc\n")

      assert_received {[:ancho_fijo, :parsear, :stop], ^ref,
                       %{registros: 1, errores: 0, advertencias: 1}, _}
    end

    test "un layout inválido o un archivo ilegible también cierran el span, con la misma forma",
         %{ref: ref} do
      assert {:error, _} = AnchoFijo.parsear([campos: []], "001\n")

      assert_received {[:ancho_fijo, :parsear, :stop], ^ref, medidas, metadata}
      assert %{duration: _, lineas: 0, registros: 0, errores: 1, advertencias: 0} = medidas
      assert %{resultado: :error, layout: nil, encoding: nil, unidad: nil} = metadata

      assert {:error, _} = AnchoFijo.parsear(@layout, "/no/existe", desde: :archivo)

      assert_received {[:ancho_fijo, :parsear, :stop], ^ref, %{errores: 1},
                       %{resultado: :error, desde: :archivo, layout: nil}}
    end

    test "desde una ruta, la metadata lo dice", %{ref: ref} do
      assert {:ok, _, _} = AnchoFijo.parsear(layout_nomina(), ruta("nomina_correcta.txt"))
      assert_received {[:ancho_fijo, :parsear, :stop], ^ref, %{registros: 3}, %{desde: :archivo}}
    end
  end

  describe "detectar/2" do
    test "emite start y stop con líneas, bytes y el veredicto", %{ref: ref} do
      contenido = "juan;100\nmaria;20000\n"
      assert {:ok, _} = AnchoFijo.detectar(contenido)

      assert_received {[:ancho_fijo, :detectar, :start], ^ref, _, %{desde: :contenido}}

      assert_received {[:ancho_fijo, :detectar, :stop], ^ref, medidas, metadata}
      assert medidas.lineas == 2
      assert medidas.bytes == byte_size(contenido)
      assert metadata.resultado == :ok
      assert metadata.probablemente_ancho_fijo? == false
    end

    test "una entrada ilegible cierra el span con :error y la misma forma", %{ref: ref} do
      assert {:error, _} = AnchoFijo.detectar("/no/existe", desde: :archivo)

      assert_received {[:ancho_fijo, :detectar, :stop], ^ref, %{duration: _, lineas: 0, bytes: 0},
                       %{resultado: :error, probablemente_ancho_fijo?: nil}}
    end
  end

  describe "stream/3" do
    test "no emite nada hasta que se enumera", %{ref: ref} do
      stream = AnchoFijo.stream(@layout, "001\n002\n")
      refute_received {[:ancho_fijo, :stream, :start], ^ref, _, _}

      assert Enum.count(stream) == 2

      assert_received {[:ancho_fijo, :stream, :start], ^ref, %{system_time: _},
                       %{layout: "códigos"}}

      assert_received {[:ancho_fijo, :stream, :stop], ^ref, medidas, %{desde: :contenido}}
      assert %{duration: _, lineas: 2, registros: 2, errores: 0, advertencias: 0} = medidas
    end

    test "cuenta errores y advertencias por línea", %{ref: ref} do
      layout =
        Layout.nuevo!(
          relleno_final: :tolerar,
          campos: [[nombre: :a, largo: 3, tipo: :entero], [nombre: :b, largo: 3]]
        )

      resultados = AnchoFijo.stream(layout, "001\nXYZabc\n002ab\n") |> Enum.to_list()
      assert length(resultados) == 3

      assert_received {[:ancho_fijo, :stream, :stop], ^ref, medidas, _}
      assert %{lineas: 3, registros: 2, errores: 1, advertencias: 2} = medidas
    end

    test "si la enumeración se corta, stop sale igual con lo contado hasta ahí", %{ref: ref} do
      assert [_] = AnchoFijo.stream(@layout, "001\n002\n003\n") |> Enum.take(1)

      assert_received {[:ancho_fijo, :stream, :stop], ^ref, %{lineas: 1, registros: 1}, _}
    end

    test "sigue siendo lazy: con un stream infinito, take termina", %{ref: ref} do
      infinito = Stream.cycle(["001\n"])
      assert [_, _] = AnchoFijo.stream(@layout, infinito) |> Enum.take(2)

      assert_received {[:ancho_fijo, :stream, :stop], ^ref, %{lineas: 2}, %{desde: :enumerable}}
    end

    test "un archivo ilegible emite start y stop con el error contado", %{ref: ref} do
      assert [{:error, _}] =
               AnchoFijo.stream(@layout, "/no/existe", desde: :archivo) |> Enum.to_list()

      assert_received {[:ancho_fijo, :stream, :stop], ^ref, %{lineas: 1, errores: 1},
                       %{desde: :archivo}}
    end
  end

  describe "escribir/3" do
    test "emite start y stop con las cuentas y la metadata", %{ref: ref} do
      assert {:ok, _, []} =
               AnchoFijo.escribir(@layout, [%{codigo: 1}, %{codigo: 2}], terminador: :crlf)

      assert_received {[:ancho_fijo, :escribir, :start], ^ref, %{system_time: _}, metadata}
      assert %{terminador: :crlf, truncar: false} = metadata

      assert_received {[:ancho_fijo, :escribir, :stop], ^ref, medidas, metadata}
      assert %{duration: _, lineas: 2, registros: 2, errores: 0, advertencias: 0} = medidas
      assert %{resultado: :ok, layout: "códigos", encoding: :utf8, unidad: :bytes} = metadata
    end

    test "con un registro que no se puede escribir, stop dice :error y cuenta todo", %{ref: ref} do
      assert {:error, [_]} = AnchoFijo.escribir(@layout, [%{codigo: 1}, %{codigo: 1234}])

      assert_received {[:ancho_fijo, :escribir, :stop], ^ref,
                       %{lineas: 2, registros: 0, errores: 1}, %{resultado: :error}}
    end

    test "las advertencias de truncar se cuentan", %{ref: ref} do
      layout = Layout.nuevo!(campos: [[nombre: :g, largo: 2]])
      assert {:ok, _, [_]} = AnchoFijo.escribir(layout, [%{g: "abc"}], truncar: true)

      assert_received {[:ancho_fijo, :escribir, :stop], ^ref, %{registros: 1, advertencias: 1},
                       %{truncar: true, layout: nil}}
    end

    test "un layout inválido cierra el span con la misma forma", %{ref: ref} do
      assert {:error, _} = AnchoFijo.escribir([campos: []], [])

      assert_received {[:ancho_fijo, :escribir, :stop], ^ref, %{lineas: 0, errores: 1},
                       %{resultado: :error, layout: nil, encoding: nil, unidad: nil}}
    end

    test "Escritor.stream/3 emite al enumerar, con lo contado hasta el corte", %{ref: ref} do
      stream = Escritor.stream(@layout, [%{codigo: 1}, %{codigo: :x}, %{codigo: 3}])
      refute_received {[:ancho_fijo, :escribir_stream, :start], ^ref, _, _}

      assert [{:ok, _, _}, {:error, _}] = Enum.take(stream, 2)

      assert_received {[:ancho_fijo, :escribir_stream, :start], ^ref, _, %{layout: "códigos"}}

      assert_received {[:ancho_fijo, :escribir_stream, :stop], ^ref,
                       %{lineas: 2, registros: 1, errores: 1}, %{terminador: :lf}}
    end
  end

  describe "con un Multiregistro" do
    @multi AnchoFijo.Multiregistro.nuevo!(
             nombre: "lote",
             discriminador: [largo: 1],
             registros: [
               h: [valor: "H", cantidad: :uno, layout: [campos: [[nombre: :t, largo: 1]]]],
               d: [
                 valor: "D",
                 cantidad: :varios,
                 layout: [campos: [[nombre: :t, largo: 1], [nombre: :n, largo: 2, tipo: :entero]]]
               ],
               t: [
                 valor: "T",
                 cantidad: :uno,
                 layout: [campos: [[nombre: :t, largo: 1], [nombre: :c, largo: 2, tipo: :entero]]]
               ]
             ],
             controles: [[en: :t, campo: :c, cuenta: :d]]
           )

    test "parsear/3 emite start y stop con el nombre del multiregistro", %{ref: ref} do
      assert {:ok, _, []} = AnchoFijo.parsear(@multi, "H\nD01\nD02\nT02\n")

      assert_received {[:ancho_fijo, :parsear, :start], ^ref, _,
                       %{modo: :estricto, desde: :contenido}}

      assert_received {[:ancho_fijo, :parsear, :stop], ^ref, medidas, metadata}
      assert %{lineas: 4, registros: 4, errores: 0, advertencias: 0} = medidas
      assert %{resultado: :ok, layout: "lote", encoding: nil, unidad: nil} = metadata
    end

    test "en tolerante, los errores de línea y de cierre se cuentan juntos", %{ref: ref} do
      assert {:ok, _, diagnosticos} =
               AnchoFijo.parsear(@multi, "H\nD01\nDxx\nT02\n", modo: :tolerante)

      assert length(diagnosticos) == 2

      assert_received {[:ancho_fijo, :parsear, :stop], ^ref, %{lineas: 4, registros: 3, errores: 2},
                       %{resultado: :ok, modo: :tolerante}}
    end

    test "en estricto, un error corta y lineas es lo leído hasta ahí", %{ref: ref} do
      assert {:error, _} = AnchoFijo.parsear(@multi, "H\nDxx\nD02\nT02\n")

      assert_received {[:ancho_fijo, :parsear, :stop], ^ref, %{lineas: 2, registros: 0, errores: 1},
                       _}
    end

    test "escribir/3 con un multiregistro emite con el nombre del multiregistro", %{ref: ref} do
      assert {:ok, _, []} = AnchoFijo.escribir(@multi, h: %{}, d: %{n: 1}, d: %{n: 2}, t: %{})

      assert_received {[:ancho_fijo, :escribir, :stop], ^ref, medidas, metadata}
      assert %{lineas: 4, registros: 4, errores: 0, advertencias: 0} = medidas
      assert %{resultado: :ok, layout: "lote", terminador: :lf, truncar: false} = metadata
    end

    test "stream/3 cuenta el cierre como errores pero no como línea", %{ref: ref} do
      resultados = AnchoFijo.stream(@multi, "H\nD01\nD02\nT05\n") |> Enum.to_list()
      assert [{:ok, _, _}, {:ok, _, _}, {:ok, _, _}, {:ok, _, _}, {:error, [_]}] = resultados

      assert_received {[:ancho_fijo, :stream, :start], ^ref, _,
                       %{layout: "lote", desde: :contenido}}

      assert_received {[:ancho_fijo, :stream, :stop], ^ref, medidas, %{encoding: nil, unidad: nil}}
      assert %{lineas: 4, registros: 4, errores: 1, advertencias: 0} = medidas
    end

    test "stream/3 cortado emite stop sin cierre", %{ref: ref} do
      assert [_] = AnchoFijo.stream(@multi, "H\nD01\nT05\n") |> Enum.take(1)
      assert_received {[:ancho_fijo, :stream, :stop], ^ref, %{lineas: 1, errores: 0}, _}
    end

    test "un archivo ilegible emite start y stop con el error contado", %{ref: ref} do
      assert [{:error, _}] =
               AnchoFijo.stream(@multi, "/no/existe", desde: :archivo) |> Enum.to_list()

      assert_received {[:ancho_fijo, :stream, :stop], ^ref, %{lineas: 1, errores: 1},
                       %{layout: "lote"}}
    end
  end

  describe "span/3" do
    test "una excepción adentro emite :exception y la propaga", %{ref: ref} do
      assert_raise RuntimeError, "boom", fn ->
        Telemetria.span(:parsear, %{modo: :prueba}, fn -> raise "boom" end)
      end

      assert_received {[:ancho_fijo, :parsear, :exception], ^ref, %{duration: _}, metadata}
      assert metadata.kind == :error
      assert %RuntimeError{message: "boom"} = metadata.reason
      assert metadata.modo == :prueba
    end

    test "devuelve el resultado de la función, no la tupla" do
      assert Telemetria.span(:parsear, %{}, fn -> {:valor, %{}, %{}} end) == :valor
    end
  end
end
