defmodule AnchoFijo.MultiregistroTest do
  use ExUnit.Case, async: true

  import AnchoFijo.Fixtures, only: [ruta: 1, leer: 1]

  alias AnchoFijo.Diagnostico
  alias AnchoFijo.Multiregistro

  # La nómina del fixture: header de 40, detalles de 50, trailer de 24.
  defp nomina(opts \\ []) do
    Multiregistro.nuevo!(
      discriminador: [posicion: 1, largo: 2],
      registros: [
        header: [
          valor: "01",
          cantidad: Keyword.get(opts, :header, :uno),
          layout: [
            campos: [
              [nombre: :tipo, largo: 2],
              [nombre: :empresa, largo: 10, tipo: :rut],
              [nombre: :fecha, largo: 8, tipo: :fecha, formato: :aaaammdd],
              [nombre: :glosa, largo: 20]
            ]
          ]
        ],
        detalle: [
          valor: "02",
          cantidad: :al_menos_uno,
          layout: [
            campos: [
              [nombre: :tipo, largo: 2],
              [nombre: :rut, largo: 10, tipo: :rut],
              [nombre: :nombre, largo: 20],
              [nombre: :monto, largo: 10, tipo: :decimal, precision: 2],
              [nombre: :cuenta, largo: 8, tipo: :entero]
            ]
          ]
        ],
        trailer: [
          valor: "09",
          cantidad: :uno,
          layout: [
            campos: [
              [nombre: :tipo, largo: 2],
              [nombre: :cantidad, largo: 6, tipo: :entero],
              [nombre: :total, largo: 16, tipo: :decimal, precision: 2]
            ]
          ]
        ]
      ],
      controles: [
        [en: :trailer, campo: :cantidad, cuenta: :detalle],
        [en: :trailer, campo: :total, suma: {:detalle, :monto}]
      ]
    )
  end

  describe "una nómina completa" do
    test "en estricto, con cada tipo en su layout y el trailer cuadrado" do
      assert {:ok, registros, []} = AnchoFijo.parsear(nomina(), ruta("nomina_multiregistro.txt"))

      assert Enum.map(registros, &elem(&1, 0)) == [:header, :detalle, :detalle, :detalle, :trailer]

      grupos = Multiregistro.agrupar(nomina(), registros)
      assert grupos.header.empresa == "76543210-3"
      assert grupos.header.fecha == ~D[2024-01-15]
      assert length(grupos.detalle) == 3
      assert hd(grupos.detalle).monto == {125_000, 2}
      assert grupos.trailer == %{tipo: "09", cantidad: 3, total: {10_115_095, 2}}
    end

    test "en tolerante da lo mismo sobre un archivo sano" do
      assert {:ok, registros, []} =
               AnchoFijo.parsear(nomina(), ruta("nomina_multiregistro.txt"), modo: :tolerante)

      assert length(registros) == 5
    end

    test "el stream entrega lo mismo que parsear/3 y nada al final si todo cuadra" do
      {:ok, registros, []} = AnchoFijo.parsear(nomina(), leer("nomina_multiregistro.txt"))

      del_stream = nomina() |> AnchoFijo.stream(ruta("nomina_multiregistro.txt")) |> Enum.to_list()
      assert Enum.map(del_stream, fn {:ok, registro, []} -> registro end) == registros
    end
  end

  describe "parsear!/3" do
    test "con un multiregistro devuelve los {tipo, mapa}, no un diagnóstico de layout" do
      registros = AnchoFijo.parsear!(AnchoFijo.Formatos.nacha(), ruta("nacha_ppd.txt"))

      assert length(registros) == 20
      assert {:encabezado_de_archivo, %{record_type_code: "1"}} = hd(registros)
      assert registros == Multiregistro.parsear!(AnchoFijo.Formatos.nacha(), ruta("nacha_ppd.txt"))
    end

    test "levanta AnchoFijo.Error con los diagnósticos reales de estructura y control" do
      sin_trailer = leer("nomina_multiregistro.txt") |> String.split("\n") |> Enum.take(4)

      error =
        assert_raise AnchoFijo.Error, fn ->
          AnchoFijo.parsear!(nomina(), Enum.map_join(sin_trailer, "", &(&1 <> "\n")))
        end

      assert [%Diagnostico{tipo: :estructura, esperado: "un registro :trailer en el archivo"}] =
               error.diagnosticos
    end

    test "en tolerante levanta con todos los errores, de línea y de control" do
      con_detalle_roto =
        leer("nomina_multiregistro.txt")
        |> String.replace("000012500011223344", "0000125000112233XX")

      error =
        assert_raise AnchoFijo.Error, fn ->
          AnchoFijo.parsear!(nomina(), con_detalle_roto, modo: :tolerante)
        end

      assert [:campo_invalido, :control, :control] = Enum.map(error.diagnosticos, & &1.tipo)
    end

    test "las advertencias no levantan ni se devuelven" do
      layout_tolerante = [
        relleno_final: :tolerar,
        campos: [[nombre: :t, largo: 1], [nombre: :glosa, largo: 5]]
      ]

      multi =
        Multiregistro.nuevo!(
          discriminador: [largo: 1],
          registros: [d: [valor: "D", layout: layout_tolerante]]
        )

      assert {:ok, [d: %{glosa: "ab"}], [%Diagnostico{gravedad: :advertencia}]} =
               AnchoFijo.parsear(multi, "Dab\n")

      assert [d: %{glosa: "ab"}] = AnchoFijo.parsear!(multi, "Dab\n")
    end
  end

  describe "opciones: las mismas de parsear/3 y stream/3, con el mismo contrato" do
    test "una opción desconocida o con un valor de otro tipo es ArgumentError" do
      for {funcion, opts} <- [
            {&AnchoFijo.parsear/3, [opcionx: 1]},
            {&AnchoFijo.parsear/3, [modo: :otro]},
            {&AnchoFijo.parsear/3, [saltar: -1]},
            {&AnchoFijo.stream/3, [opcionx: 1]},
            {&AnchoFijo.stream/3, [modo: :tolerante]},
            {&AnchoFijo.stream/3, [traza: 1]}
          ] do
        assert_raise ArgumentError, ~r/AnchoFijo\.(parsear|stream)\/3/, fn ->
          funcion.(nomina(), ruta("nomina_multiregistro.txt"), opts)
        end
      end
    end

    test "traza: true pone :__traza__ en cada mapa, con el offset real" do
      {:ok, registros, []} =
        AnchoFijo.parsear(nomina(), ruta("nomina_multiregistro.txt"), traza: true)

      trazas = Enum.map(registros, fn {_tipo, mapa} -> mapa.__traza__ end)
      assert Enum.map(trazas, & &1.linea) == [1, 2, 3, 4, 5]
      assert Enum.map(trazas, & &1.offset) == [0, 41, 92, 143, 194]
      assert Enum.map(trazas, & &1.largo) == [40, 50, 50, 50, 24]

      del_stream =
        nomina()
        |> AnchoFijo.stream(ruta("nomina_multiregistro.txt"), traza: true)
        |> Enum.map(fn {:ok, {_tipo, mapa}, []} -> mapa.__traza__ end)

      assert del_stream == trazas
    end

    test "sin traza, ningún mapa trae la clave" do
      {:ok, registros, []} = AnchoFijo.parsear(nomina(), ruta("nomina_multiregistro.txt"))
      refute Enum.any?(registros, fn {_tipo, mapa} -> Map.has_key?(mapa, :__traza__) end)
    end

    test "saltar y omitir_vacias se respetan en parsear/3 y en stream/3" do
      contenido = "BASURA\n\n" <> leer("nomina_multiregistro.txt")

      assert {:ok, registros, []} = AnchoFijo.parsear(nomina(), contenido, saltar: 1)
      assert Enum.map(registros, &elem(&1, 0)) == [:header, :detalle, :detalle, :detalle, :trailer]

      assert {:error, [%Diagnostico{linea: 2}]} =
               AnchoFijo.parsear(nomina(), contenido, saltar: 1, omitir_vacias: false)

      assert [{:ok, {:header, _}, []} | _] =
               nomina() |> AnchoFijo.stream(contenido, saltar: 1) |> Enum.to_list()
    end

    test "una clave desconocida en la definición es un diagnóstico :layout" do
      assert {:error, [d]} =
               Multiregistro.nuevo(
                 discriminador: [largo: 1],
                 registros: [h: [valor: "H", layout: [campos: [[nombre: :a, largo: 2]]]]],
                 controls: []
               )

      assert %Diagnostico{tipo: :layout, recibido: ":controls"} = d
      assert d.causa_probable =~ "error de tipeo"

      assert {:error, [%Diagnostico{tipo: :layout}]} = Multiregistro.nuevo(42)

      assert {:error, [%Diagnostico{tipo: :layout, recibido: "42"}]} =
               Multiregistro.nuevo(discriminador: [largo: 1], registros: [], nombre: 42)
    end

    test "el nombre viaja en el struct y en la telemetría" do
      assert %Multiregistro{nombre: "NACHA"} = AnchoFijo.Formatos.nacha()
      assert nomina().nombre == nil
    end
  end

  describe "discriminador por campo :constante" do
    defp layout_con_tipo(valor, posicion \\ 1) do
      [
        campos: [
          [nombre: :tipo, posicion: posicion, largo: 2, tipo: :constante, valor: valor],
          [nombre: :dato, largo: 3]
        ]
      ]
    end

    test "cada tipo toma su valor del literal, y el discriminador queda resuelto" do
      multi =
        Multiregistro.nuevo!(
          discriminador: [campo: :tipo],
          registros: [
            h: [cantidad: :uno, layout: layout_con_tipo("01")],
            d: [layout: layout_con_tipo("02")]
          ]
        )

      assert multi.discriminador == %{campo: :tipo, posicion: 1, largo: 2}

      assert {:ok, [h: %{tipo: "01", dato: "abc"}, d: %{tipo: "02", dato: "def"}], []} =
               AnchoFijo.parsear(multi, "01abc\n02def\n")
    end

    test "con posición y largo explícitos, :valor se puede omitir si hay una constante ahí" do
      multi =
        Multiregistro.nuevo!(
          discriminador: [posicion: 1, largo: 2],
          registros: [
            h: [layout: layout_con_tipo("01")],
            d: [valor: "02", layout: [campos: [[nombre: :x, largo: 5]]]]
          ]
        )

      assert Enum.map(multi.registros, fn {_, d} -> d.valores end) == [["01"], ["02"]]
    end

    test "sin :valor y sin constante en esas posiciones es un diagnóstico" do
      assert {:error, [d]} =
               Multiregistro.nuevo(
                 discriminador: [posicion: 1, largo: 2],
                 registros: [d: [layout: [campos: [[nombre: :x, largo: 5]]]]]
               )

      assert d.esperado =~ "un :valor para :d, o un campo :constante en las posiciones 1-2"
    end

    test "el campo tiene que existir, ser constante y estar igual en todos los layouts" do
      assert {:error, [d]} =
               Multiregistro.nuevo(
                 discriminador: [campo: :tipo],
                 registros: [d: [layout: [campos: [[nombre: :x, largo: 5]]]]]
               )

      assert d.esperado == "un campo :tipo en el layout de :d"

      assert {:error, [d]} =
               Multiregistro.nuevo(
                 discriminador: [campo: :tipo],
                 registros: [d: [layout: [campos: [[nombre: :tipo, largo: 2]]]]]
               )

      assert d.esperado == "un campo :tipo de tipo :constante en el layout de :d"
      assert d.recibido == "un campo :texto"

      assert {:error, [d]} =
               Multiregistro.nuevo(
                 discriminador: [campo: :tipo],
                 registros: [
                   h: [layout: layout_con_tipo("01")],
                   d: [layout: layout_con_tipo("02", 4)]
                 ]
               )

      assert d.esperado =~ "misma posición y con el mismo largo"
      assert d.recibido == ":h en 1 con largo 2, :d en 4 con largo 2"
    end

    test "un discriminador con :campo y :largo a la vez es inválido" do
      assert {:error, [%Diagnostico{tipo: :layout}]} =
               Multiregistro.nuevo(discriminador: [campo: :tipo, largo: 2], registros: [])
    end
  end

  describe "estructura" do
    @lineas [
      "0176543210-320240115SUELDOS ENERO       ",
      "0212345678-5JUAN PEREZ SOTO     000012500011223344",
      "0298765432-5ANA MARIA ROJAS     000999005055667788",
      "090000020000000010115050"
    ]

    defp contenido(lineas), do: Enum.map_join(lineas, "", &(&1 <> "\n"))

    test "un discriminador desconocido se diagnostica con causa" do
      lineas = List.insert_at(@lineas, 2, "07ALGO QUE NO SE SABE QUE ES")

      assert {:error, [d]} = AnchoFijo.parsear(nomina(), contenido(lineas))
      assert %Diagnostico{tipo: :estructura, linea: 3, recibido: "\"07\""} = d

      assert Diagnostico.mensaje(d) =~
               ~s|se esperaba un discriminador en "01" (:header), "02" (:detalle), "09" (:trailer), llegó "07"|

      assert d.causa_probable =~ "ningún tipo de registro declarado"
    end

    test "un detalle después del trailer está fuera de orden" do
      lineas = @lineas ++ ["0211111111-1PEDRO GONZALEZ      000000004599001122"]

      assert {:error, [d]} = AnchoFijo.parsear(nomina(), contenido(lineas))
      assert %Diagnostico{tipo: :estructura, linea: 5, recibido: ":detalle"} = d

      assert d.esperado ==
               "un registro :trailer o uno posterior en el orden :header, :detalle, :trailer"

      assert d.causa_probable =~ "archivo pegado a otro"
    end

    test "dos headers es un repetido" do
      lineas = [hd(@lineas) | @lineas]

      assert {:error, [d]} = AnchoFijo.parsear(nomina(), contenido(lineas))
      assert %Diagnostico{tipo: :estructura, linea: 2, esperado: "un solo registro :header"} = d
    end

    test "un trailer faltante se reporta al final, sin línea" do
      lineas = Enum.take(@lineas, 3)

      assert {:error, [d]} = AnchoFijo.parsear(nomina(), contenido(lineas))
      assert %Diagnostico{tipo: :estructura, linea: nil} = d
      assert d.esperado == "un registro :trailer en el archivo"
      assert d.causa_probable =~ "truncado"
    end

    test "al menos un detalle" do
      lineas = [hd(@lineas), "090000000000000000000000"]

      assert {:error, [d]} = AnchoFijo.parsear(nomina(), contenido(lineas))
      assert d.esperado == "un registro :detalle en el archivo"
    end

    test "el header puede ser opcional y el orden lo da :registros" do
      sin_header = Enum.drop(@lineas, 1)

      assert {:ok, registros, []} =
               AnchoFijo.parsear(nomina(header: :opcional), contenido(sin_header))

      assert Multiregistro.agrupar(nomina(header: :opcional), registros).header == nil
    end

    test "una línea más corta que el discriminador" do
      assert {:error, [d]} = AnchoFijo.parsear(nomina(), "0\n")
      assert d.esperado =~ "al menos 2 bytes para leer el discriminador"
    end
  end

  describe "controles" do
    test "cantidad que no cuadra" do
      lineas = List.replace_at(@lineas, 3, "090000030000000010115050")

      assert {:error, [d]} = AnchoFijo.parsear(nomina(), contenido(lineas))
      assert %Diagnostico{tipo: :control, linea: 4, campo: :cantidad, recibido: "3"} = d
      assert d.esperado == "2 en :cantidad, que es la cantidad de registros :detalle"
      assert Diagnostico.mensaje(d) =~ "faltan registros o sobran"
    end

    test "suma que no cuadra, con decimales" do
      lineas = List.replace_at(@lineas, 3, "090000020000000010115051")

      assert {:error, [d]} = AnchoFijo.parsear(nomina(), contenido(lineas))
      assert %Diagnostico{tipo: :control, campo: :total} = d
      assert d.esperado == "{10115050, 2} en :total, la suma de :monto de los :detalle"
      assert d.recibido == "{10115051, 2}"
    end

    test "en tolerante salen todos: la línea ilegible y los dos totales que ya no cuadran" do
      lineas = List.replace_at(@lineas, 2, "0298765432-5ANA MARIA ROJAS     0009990X5055667788")

      assert {:ok, registros, diagnosticos} =
               AnchoFijo.parsear(nomina(), contenido(lineas), modo: :tolerante)

      assert length(registros) == 3

      assert Enum.map(diagnosticos, &{&1.tipo, &1.linea}) == [
               {:campo_invalido, 3},
               {:control, 4},
               {:control, 4}
             ]

      assert Enum.at(diagnosticos, 1).causa_probable =~ "la cuenta las excluye"
    end

    test "en el stream los controles salen como último elemento" do
      lineas = List.replace_at(@lineas, 3, "090000030000000010115050")

      resultados = nomina() |> AnchoFijo.stream(contenido(lineas)) |> Enum.to_list()
      assert length(resultados) == 5

      assert [
               {:ok, _, _},
               {:ok, _, _},
               {:ok, _, _},
               {:ok, {:trailer, _}, _},
               {:error, [%Diagnostico{tipo: :control}]}
             ] = resultados
    end

    test "en el stream el trailer faltante también sale al final" do
      resultados = nomina() |> AnchoFijo.stream(contenido(Enum.take(@lineas, 3))) |> Enum.to_list()

      assert {:error,
              [%Diagnostico{tipo: :estructura, esperado: "un registro :trailer en el archivo"}]} =
               List.last(resultados)
    end

    test "sumas de enteros y de decimales con precisiones distintas" do
      multi =
        Multiregistro.nuevo!(
          discriminador: [largo: 1],
          registros: [
            d: [
              valor: "D",
              layout: [
                campos: [
                  [nombre: :t, largo: 1],
                  [nombre: :m, largo: 5, tipo: :decimal, precision: 1]
                ]
              ]
            ],
            t: [
              valor: "T",
              cantidad: :uno,
              layout: [
                campos: [
                  [nombre: :t, largo: 1],
                  [nombre: :m, largo: 6, tipo: :decimal, precision: 2]
                ]
              ]
            ]
          ],
          controles: [[en: :t, campo: :m, suma: {:d, :m}]]
        )

      # 1.5 + 2.5 = 4.0 en el detalle con precisión 1; el trailer declara 4.00.
      assert {:ok, _, []} = AnchoFijo.parsear(multi, "D00015\nD00025\nT000400\n")

      assert {:error, [%Diagnostico{tipo: :control}]} =
               AnchoFijo.parsear(multi, "D00015\nD00025\nT000401\n")
    end
  end

  describe "la definición" do
    test "valida discriminador, valores, cantidades, layouts y controles" do
      assert {:error, [d]} = Multiregistro.nuevo(registros: [])
      assert d.esperado =~ ":discriminador"

      assert {:error, [d]} =
               Multiregistro.nuevo(
                 discriminador: [largo: 2],
                 registros: [h: [valor: "H", layout: [campos: [[nombre: :a, largo: 2]]]]]
               )

      assert d.esperado =~ "de 2 bytes para :h"

      assert {:error, [d]} =
               Multiregistro.nuevo(
                 discriminador: [largo: 1],
                 registros: [
                   h: [valor: "H", cantidad: :muchos, layout: [campos: [[nombre: :a, largo: 2]]]]
                 ]
               )

      assert d.esperado =~ ":cantidad en"

      assert {:error, [d]} =
               Multiregistro.nuevo(
                 discriminador: [largo: 1],
                 registros: [h: [valor: "H", layout: [campos: []]]]
               )

      assert %Diagnostico{tipo: :layout, campo: :h} = d

      assert {:error, [d]} =
               Multiregistro.nuevo(
                 discriminador: [largo: 1],
                 registros: [
                   h: [valor: "H", layout: [campos: [[nombre: :a, largo: 2]]]],
                   d: [valor: "H", layout: [campos: [[nombre: :a, largo: 2]]]]
                 ]
               )

      assert d.esperado == "un :valor distinto por tipo de registro"

      assert {:error, [d]} =
               Multiregistro.nuevo(
                 discriminador: [largo: 1],
                 registros: [h: [valor: "H", layout: [campos: [[nombre: :a, largo: 2]]]]],
                 controles: [[en: :h, campo: :zzz, cuenta: :h]]
               )

      assert d.causa_probable =~ "no tiene el campo :zzz"
    end

    test "nuevo! levanta AnchoFijo.Error" do
      assert_raise AnchoFijo.Error, fn -> Multiregistro.nuevo!(registros: []) end
    end
  end
end
