defmodule AnchoFijo.SerializacionTest do
  use ExUnit.Case, async: true

  import AnchoFijo.Fixtures

  alias AnchoFijo.Diagnostico
  alias AnchoFijo.Layout
  alias AnchoFijo.Multiregistro
  alias Mix.Tasks.AnchoFijo.Carga

  defp sin_codigo, do: elem(Code.eval_file(ruta("multiregistro_sin_codigo.exs")), 0)

  @con_todo Layout.nuevo!(
              nombre: "de todo",
              encoding: :latin1,
              relleno_final: :tolerar,
              identidad: [campos: [:lote]],
              campos: [
                [
                  nombre: :lote,
                  largo: 4,
                  tipo: :entero,
                  signo: :final,
                  descripcion: "lote",
                  ejemplo: "0001"
                ],
                [nombre: :monto, largo: 10, tipo: :decimal, moneda: :usd, como: :decimal],
                [
                  nombre: :importe,
                  largo: 8,
                  tipo: :decimal,
                  precision: 2,
                  separador: :coma,
                  opcional: true
                ],
                [nombre: :fecha, largo: 10, tipo: :fecha, formato: "DD/MM/AAAA"],
                [nombre: :corta, largo: 6, tipo: :fecha, formato: :aammdd, pivote: 1970],
                [nombre: :hora, largo: 6, tipo: AnchoFijo.TipoHora, segundos: true],
                [nombre: :rut, largo: 9, tipo: :rut, dv: :ausente, sensible: false],
                [nombre: :tipo, largo: 2, tipo: :constante, valor: "01"],
                [nombre: :filler, largo: 3, tipo: :relleno, relleno: "0"],
                [
                  nombre: :mensaje,
                  largo: 20,
                  encoding: :utf8,
                  trim: :derecha,
                  reparar_doble_codificacion: true
                ],
                [nombre: :fijo, largo: 5, trim: false, relleno: "*"]
              ]
            )

  describe "a_mapa/1 y desde_mapa/1" do
    test "son inversos para todos los layouts de los fixtures y uno con todas las opciones" do
      for layout <- [
            layout_nomina(),
            layout_nomina(encoding: :latin1),
            layout_glosa(),
            layout_respuesta_mixta(),
            @con_todo,
            Layout.nuevo!(
              decimales_como: :decimal,
              campos: [[nombre: :m, largo: 6, tipo: :decimal, precision: 2]]
            )
          ] do
        mapa = Layout.a_mapa(layout)
        assert mapa["version"] == 1
        assert Layout.desde_mapa(mapa) == {:ok, layout}
      end
    end

    test "el mapa no tiene átomos ni funciones y solo lleva lo declarado" do
      mapa = Layout.a_mapa(@con_todo)
      refute mapa |> inspect() |> String.contains?(["Elixir.", "#Function"])
      assert Enum.all?(Map.keys(mapa), &is_binary/1)

      [lote, monto, _importe, fecha, corta, hora | _] = mapa["campos"]

      assert lote == %{
               "nombre" => "lote",
               "posicion" => 1,
               "largo" => 4,
               "tipo" => "entero",
               "signo" => "final",
               "descripcion" => "lote",
               "ejemplo" => "0001"
             }

      assert monto["moneda"] == "usd" and monto["como"] == "decimal" and monto["precision"] == 2
      assert fecha["formato"] == "DD/MM/AAAA"
      assert corta["formato"] == "aammdd" and corta["pivote"] == 1970

      assert hora == %{
               "nombre" => "hora",
               "posicion" => 39,
               "largo" => 6,
               "tipo" => "AnchoFijo.TipoHora",
               "segundos" => true
             }

      assert mapa["identidad"] == %{"campos" => ["lote"]}
      refute Map.has_key?(mapa, "decimales_como")
    end

    test "una clave desconocida es un diagnóstico, en el layout y en un campo" do
      assert {:error, [d]} =
               Layout.desde_mapa(%{
                 "campos" => [%{"nombre" => "a", "largo" => 2}],
                 "enconding" => "latin1"
               })

      assert %Diagnostico{tipo: :layout, recibido: "enconding"} = d

      assert {:error, [d]} =
               Layout.desde_mapa(%{
                 "campos" => [%{"nombre" => "a", "largo" => 2, "trimm" => false}]
               })

      assert %Diagnostico{tipo: :layout, campo: :a, recibido: "trimm"} = d
    end

    test "otra versión del esquema, un tipo propio que no existe y un mapa que no lo es" do
      assert {:error, [d]} = Layout.desde_mapa(%{"version" => 2, "campos" => []})
      assert d.esperado == "version 1 del esquema de serialización"

      assert {:error, [d]} =
               Layout.desde_mapa(%{
                 "campos" => [%{"nombre" => "a", "largo" => 2, "tipo" => "MiApp.NoExiste"}]
               })

      assert d.campo == :a
      assert d.recibido =~ "MiApp.NoExiste"

      assert {:error, [%Diagnostico{tipo: :layout}]} = Layout.desde_mapa(42)
    end

    test "los mismos diagnósticos que nuevo/1 para una definición inválida" do
      assert {:error, [d]} =
               Layout.desde_mapa(%{
                 "campos" => [%{"nombre" => "m", "largo" => 8, "tipo" => "decimal"}]
               })

      assert d.esperado == ":precision declarada para un campo :decimal"
    end
  end

  describe "multiregistro" do
    test "a_mapa/1 y desde_mapa/1 son inversos para NACHA, el fixture sin código y uno por posición con controles agrupados" do
      por_posicion =
        Multiregistro.nuevo!(
          nombre: "por posición",
          discriminador: [por: :posicion_en_archivo],
          registros: [
            h: [ubicacion: :primera, cantidad: :uno, layout: [campos: [[nombre: :t, largo: 1]]]],
            d: [
              ubicacion: :resto,
              layout: [campos: [[nombre: :moneda, largo: 3], [nombre: :m, largo: 6, tipo: :entero]]]
            ],
            t: [
              ubicacion: :ultima,
              cantidad: :uno,
              layout: [
                campos: [[nombre: :moneda, largo: 3], [nombre: :total, largo: 8, tipo: :entero]]
              ]
            ]
          ],
          controles: [
            [en: :t, campo: :total, suma: {:d, :m}, agrupar_por: :moneda],
            [en: :t, campo: :total, cuenta: :d]
          ]
        )

      for multi <- [AnchoFijo.Formatos.nacha(), sin_codigo(), por_posicion] do
        mapa = Multiregistro.a_mapa(multi)
        assert mapa["version"] == 1
        assert Enum.all?(mapa["registros"], &(&1["layout"]["version"] == 1))
        assert Multiregistro.desde_mapa(mapa) == {:ok, multi}
      end

      mapa = Multiregistro.a_mapa(AnchoFijo.Formatos.nacha())
      assert mapa["discriminador"] == %{"posicion" => 1, "largo" => 2}
      assert mapa["orden"] == "libre"
      assert hd(mapa["registros"])["valor"] == ["10"]

      assert Multiregistro.a_mapa(por_posicion)["controles"] == [
               %{"en" => "t", "campo" => "total", "suma" => ["d", "m"], "agrupar_por" => "moneda"},
               %{"en" => "t", "campo" => "total", "cuenta" => "d"}
             ]
    end

    test "un discriminador por función no se serializa, y una clave desconocida se reclama" do
      multi =
        Multiregistro.nuevo!(
          discriminador: [por: fn _, _ -> :d end],
          registros: [d: [layout: [campos: [[nombre: :t, largo: 1]]]]]
        )

      assert_raise ArgumentError, ~r/no se puede serializar/, fn -> Multiregistro.a_mapa(multi) end

      assert {:error, [%Diagnostico{tipo: :layout, recibido: "controls"}]} =
               Multiregistro.desde_mapa(%{
                 "discriminador" => %{"largo" => 1},
                 "registros" => [
                   %{"tipo" => "d", "layout" => %{"campos" => [%{"nombre" => "t", "largo" => 1}]}}
                 ],
                 "controls" => []
               })
    end
  end

  describe "json" do
    test "a_json/1 y desde_json/1, verificados con un decoder de verdad" do
      json = Layout.a_json(@con_todo)
      assert Jason.decode!(json) == Layout.a_mapa(@con_todo)
      assert Layout.desde_json(json) == {:ok, @con_todo}

      json = Multiregistro.a_json(sin_codigo())
      assert Jason.decode!(json) == Multiregistro.a_mapa(sin_codigo())
      assert Multiregistro.desde_json(json) == {:ok, sin_codigo()}

      assert {:error, [%Diagnostico{tipo: :entrada} = d]} = Layout.desde_json("{\"campos\": [")
      assert d.esperado == "un JSON válido con la definición del layout"
    end

    test "el decodificador lee lo que Jason codifica" do
      for valor <- [
            %{"a" => [1, -2, 3.5, 1.0e3, true, false, nil, "x"]},
            %{"texto" => "con \"comillas\", \\ barras, \n saltos, tab\t y ñ, 日本, 😀"},
            [],
            %{},
            "solo un string",
            42
          ] do
        assert AnchoFijo.Json.decodificar(Jason.encode!(valor)) == {:ok, valor}
      end

      assert {:ok, %{"e" => "😀"}} = AnchoFijo.Json.decodificar(~s({"e": "\\ud83d\\ude00"}))
      assert {:error, _} = AnchoFijo.Json.decodificar("{\"a\": }")
      assert {:error, _} = AnchoFijo.Json.decodificar("[1, 2")
      assert {:error, _} = AnchoFijo.Json.decodificar("{} x")
    end

    test "el JSON Schema de priv/ es JSON válido y cubre las claves del mapa" do
      assert {:ok, schema} = "priv/layout.schema.json" |> File.read!() |> Jason.decode()
      campo = get_in(schema, ["definitions", "campo", "properties"])
      layout = get_in(schema, ["definitions", "layout", "properties"])

      for clave <-
            @con_todo
            |> Layout.a_mapa()
            |> Map.get("campos")
            |> Enum.flat_map(&Map.keys/1)
            |> Enum.uniq(),
          clave != "segundos" do
        assert Map.has_key?(campo, clave), "falta #{clave} en el schema del campo"
      end

      for clave <- Map.keys(Layout.a_mapa(@con_todo)) do
        assert Map.has_key?(layout, clave), "falta #{clave} en el schema del layout"
      end
    end
  end

  describe "las tareas Mix leen un .json" do
    test "cargar_layout con un layout y con un multiregistro en JSON" do
      dir = System.tmp_dir!()
      layout_json = Path.join(dir, "layout_#{System.unique_integer([:positive])}.json")
      multi_json = Path.join(dir, "multi_#{System.unique_integer([:positive])}.json")
      File.write!(layout_json, Layout.a_json(layout_nomina()))
      File.write!(multi_json, Multiregistro.a_json(sin_codigo()))

      on_exit(fn ->
        File.rm(layout_json)
        File.rm(multi_json)
      end)

      assert {:ok, layout_nomina()} == Carga.cargar_layout(layout_json)
      assert {:ok, sin_codigo()} == Carga.cargar_layout(multi_json)

      assert {:error, motivo} =
               Carga.cargar_layout(Path.join(dir, "no_existe.json"))

      assert motivo =~ "no such file"
    end
  end
end
