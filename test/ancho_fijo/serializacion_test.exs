defmodule AnchoFijo.SerializacionTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

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

  @layout_valido %{
    "version" => 1,
    "nombre" => "x",
    "encoding" => "latin1",
    "unidad" => "caracteres",
    "relleno_final" => "tolerar",
    "largo" => 40,
    "identidad" => %{"campos" => ["rut"]},
    "campos" => [
      %{"nombre" => "rut", "largo" => 10, "tipo" => "rut", "sensible" => true},
      %{
        "nombre" => "f",
        "largo" => 8,
        "tipo" => "fecha",
        "formato" => "aaaammdd",
        "rango" => ["2024-01-01", nil]
      },
      %{
        "nombre" => "m",
        "largo" => 8,
        "tipo" => "decimal",
        "precision" => 2,
        "rango" => ["0.00", "99.99"],
        "moneda" => "clp"
      },
      %{
        "nombre" => "t",
        "largo" => 6,
        "patron" => %{"patron" => "^[A-Z]+$", "opciones" => "i"},
        "en" => ["ABC"],
        "requerido_si" => %{"campo" => "rut"}
      },
      %{
        "nombre" => "g",
        "tipo" => "grupo",
        "campos" => [
          %{
            "nombre" => "h",
            "largo" => 4,
            "tipo" => "hora",
            "formato" => "hhmm",
            "rango" => [nil, "23:59:00"]
          }
        ]
      },
      %{
        "nombre" => "v",
        "tipo" => "variante",
        "segun" => "t",
        "variantes" => %{"ABC" => [%{"nombre" => "w", "largo" => 4}]}
      }
    ]
  }

  # Basura en cualquier valor del mapa, a cualquier profundidad: la vuelta
  # sigue siendo {:ok, _} o una lista de diagnósticos, nunca una excepción.
  defp con_basura(mapa, ruta, basura) when is_map(mapa) do
    case ruta do
      [] ->
        basura

      [clave | resto] when is_map_key(mapa, clave) ->
        Map.put(mapa, clave, con_basura(Map.fetch!(mapa, clave), resto, basura))

      _ ->
        mapa
    end
  end

  defp con_basura(lista, [indice | resto], basura)
       when is_list(lista) and is_integer(indice) and indice < length(lista),
       do: List.update_at(lista, indice, &con_basura(&1, resto, basura))

  defp con_basura(_valor, [], basura), do: basura
  defp con_basura(valor, _ruta, _basura), do: valor

  defp rutas(mapa, prefijo \\ [])

  defp rutas(mapa, prefijo) when is_map(mapa) and not is_struct(mapa),
    do: Enum.flat_map(mapa, fn {k, v} -> [prefijo ++ [k] | rutas(v, prefijo ++ [k])] end)

  defp rutas(lista, prefijo) when is_list(lista),
    do:
      lista
      |> Enum.with_index()
      |> Enum.flat_map(fn {v, i} -> [prefijo ++ [i] | rutas(v, prefijo ++ [i])] end)

  defp rutas(_valor, _prefijo), do: []

  defp basura do
    one_of([
      term(),
      string(:printable),
      list_of(term(), max_length: 3),
      map_of(string(:printable), term(), max_length: 3),
      constant(%{"patron" => "(", "opciones" => "zz"}),
      constant(["2024-99-99", "25:61:61"]),
      constant([1, -1, "xxx"]),
      constant(%{"campos" => "no"})
    ])
  end

  @multi_valido %{
    "version" => 1,
    "nombre" => "m",
    "orden" => "estricto",
    "discriminador" => %{"posicion" => 1, "largo" => 1},
    "registros" => [
      %{
        "tipo" => "h",
        "valor" => "H",
        "cantidad" => "uno",
        "ubicacion" => "primera",
        "layout" => %{
          "campos" => [
            %{"nombre" => "t", "largo" => 1},
            %{
              "nombre" => "f",
              "largo" => 8,
              "tipo" => "fecha",
              "formato" => "aaaammdd",
              "rango" => ["2024-01-01", nil]
            }
          ]
        }
      },
      %{
        "tipo" => "d",
        "valor" => "D",
        "cantidad" => "varios",
        "layout" => %{
          "campos" => [
            %{"nombre" => "t", "largo" => 1},
            %{"nombre" => "n", "largo" => 8, "tipo" => "entero"}
          ]
        }
      },
      %{
        "tipo" => "z",
        "valor" => "Z",
        "cantidad" => "uno",
        "ubicacion" => "ultima",
        "layout" => %{
          "campos" => [
            %{"nombre" => "t", "largo" => 1},
            %{"nombre" => "c", "largo" => 8, "tipo" => "entero"}
          ]
        }
      }
    ],
    "controles" => [%{"en" => "z", "campo" => "c", "cuenta" => "d"}]
  }

  describe "desde_mapa/1 con basura en cualquier clave" do
    property "Layout.desde_mapa/1 con basura en cualquier clave responde {:ok, _} o diagnósticos, nunca levanta" do
      check all(ruta <- member_of(rutas(@layout_valido)), valor <- basura()) do
        case Layout.desde_mapa(con_basura(@layout_valido, ruta, valor)) do
          {:ok, %Layout{}} ->
            :ok

          {:error, [%Diagnostico{} | _] = diagnosticos} ->
            assert Enum.all?(diagnosticos, &match?(%Diagnostico{tipo: :layout}, &1))
        end
      end
    end

    property "Multiregistro.desde_mapa/1 con basura en cualquier clave responde {:ok, _} o diagnósticos, nunca levanta" do
      check all(ruta <- member_of(rutas(@multi_valido)), valor <- basura()) do
        case Multiregistro.desde_mapa(con_basura(@multi_valido, ruta, valor)) do
          {:ok, %Multiregistro{}} -> :ok
          {:error, [%Diagnostico{} | _]} -> :ok
        end
      end
    end
  end

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

    test "un rango, un patrón o un decimal mal formados son diagnósticos con el campo y la clave, no excepciones" do
      assert {:error, [d]} =
               Layout.desde_mapa(%{
                 "campos" => [
                   %{
                     "nombre" => "f",
                     "largo" => 8,
                     "tipo" => "fecha",
                     "formato" => "aaaammdd",
                     "rango" => ["2024-13-01", nil]
                   }
                 ]
               })

      assert %Diagnostico{tipo: :layout, campo: :f} = d
      assert d.esperado == ~s|"rango": una fecha ISO 8601 (AAAA-MM-DD)|
      assert d.recibido == ~s(["2024-13-01", nil])
      assert d.causa_probable =~ ":invalid_date"

      assert {:error, [d]} =
               Layout.desde_mapa(%{
                 "campos" => [
                   %{
                     "nombre" => "t",
                     "largo" => 8,
                     "patron" => %{"patron" => "([", "opciones" => ""}
                   }
                 ]
               })

      assert %Diagnostico{campo: :t} = d
      assert d.esperado == ~s("patron": una expresión regular que compile)
      assert d.causa_probable =~ "missing terminating ]"

      assert {:error, [d]} =
               Layout.desde_mapa(%{
                 "campos" => [
                   %{"nombre" => "t", "largo" => 8, "patron" => %{"patron" => "a", "opciones" => 7}}
                 ]
               })

      assert d.esperado =~ ~s("opciones" como texto)

      assert {:error, [d]} =
               Layout.desde_mapa(%{
                 "campos" => [
                   %{
                     "nombre" => "m",
                     "largo" => 8,
                     "tipo" => "decimal",
                     "precision" => 2,
                     "rango" => ["abc", nil]
                   }
                 ]
               })

      assert %Diagnostico{campo: :m} = d
      assert d.esperado =~ ~s("rango": un entero, [unidades, precision])

      assert {:error, [d]} =
               Layout.desde_mapa(%{
                 "campos" => [
                   %{
                     "nombre" => "h",
                     "largo" => 6,
                     "tipo" => "hora",
                     "formato" => "hhmmss",
                     "rango" => [nil, "25:00:00"]
                   }
                 ]
               })

      assert d.esperado == ~s|"rango": una hora ISO 8601 (HH:MM:SS)|

      assert {:error, [d]} =
               Layout.desde_mapa(%{
                 "campos" => [
                   %{
                     "nombre" => "m",
                     "largo" => 8,
                     "tipo" => "decimal",
                     "precision" => 2,
                     "rango" => [[1, "x", "clp"], nil]
                   }
                 ]
               })

      assert d.esperado =~ ~s("rango": un entero, [unidades, precision], [unidades, precision, "moneda"])
    end

    test "los valores que no se pudieron convertir se acumulan con los diagnósticos de nuevo/1" do
      assert {:error, diagnosticos} =
               Layout.desde_mapa(%{
                 "campos" => [
                   %{"nombre" => "f", "largo" => 8, "tipo" => "fecha", "rango" => ["ayer", "hoy"]},
                   %{"nombre" => "g", "largo" => 0, "patron" => %{"patron" => "("}},
                   %{"nombre" => "m", "largo" => 8, "tipo" => "decimal"}
                 ]
               })

      assert Enum.map(diagnosticos, &{&1.campo, &1.esperado}) == [
               {:f, ~s|"rango": una fecha ISO 8601 (AAAA-MM-DD)|},
               {:g, ~s("patron": una expresión regular que compile)},
               {:f,
                ~s|:formato con un formato con nombre o un patrón de tokens, por ejemplo :aaaammdd o "DD/MM/AAAA"|},
               {:g, "un :largo entero mayor que cero"},
               {:m, ":precision declarada para un campo :decimal"}
             ]
    end

    test "un rango mal formado dentro de un grupo, una variante o un registro de un multiregistro también es un diagnóstico" do
      assert {:error, [%Diagnostico{campo: :f}]} =
               Layout.desde_mapa(%{
                 "campos" => [
                   %{
                     "nombre" => "g",
                     "tipo" => "grupo",
                     "campos" => [
                       %{
                         "nombre" => "f",
                         "largo" => 8,
                         "tipo" => "fecha",
                         "formato" => "aaaammdd",
                         "rango" => ["x", nil]
                       }
                     ]
                   }
                 ]
               })

      assert {:error, [%Diagnostico{campo: :f}]} =
               Layout.desde_mapa(%{
                 "campos" => [
                   %{"nombre" => "tipo", "largo" => 1},
                   %{
                     "nombre" => "v",
                     "tipo" => "variante",
                     "segun" => "tipo",
                     "variantes" => %{
                       "A" => [
                         %{
                           "nombre" => "f",
                           "largo" => 8,
                           "tipo" => "fecha",
                           "formato" => "aaaammdd",
                           "rango" => ["x", nil]
                         }
                       ]
                     }
                   }
                 ]
               })

      assert {:error, [%Diagnostico{campo: :v}] = [d]} =
               Layout.desde_mapa(%{
                 "campos" => [
                   %{"nombre" => "tipo", "largo" => 1},
                   %{
                     "nombre" => "v",
                     "tipo" => "variante",
                     "segun" => "tipo",
                     "variantes" => %{"A" => "no"}
                   }
                 ]
               })

      assert d.esperado == "una lista de campos, no vacía, por cada valor de :variantes"

      assert {:error, [%Diagnostico{tipo: :layout, campo: :f}]} =
               Multiregistro.desde_mapa(%{
                 "discriminador" => %{"largo" => 1},
                 "registros" => [
                   %{
                     "tipo" => "d",
                     "valor" => "D",
                     "layout" => %{
                       "campos" => [
                         %{"nombre" => "t", "largo" => 1},
                         %{
                           "nombre" => "f",
                           "largo" => 8,
                           "tipo" => "fecha",
                           "formato" => "aaaammdd",
                           "rango" => ["2024-02-30", nil]
                         }
                       ]
                     }
                   }
                 ]
               })
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

    test "un escape \\u inválido, un surrogate suelto o un número fuera de rango es un error, no un throw" do
      assert {:error, motivo} = AnchoFijo.Json.decodificar(~s("\\uZZZZ"))
      assert motivo == "escape \\uZZZZ inválido: se esperaban cuatro dígitos hexadecimales"

      assert {:error, motivo} = AnchoFijo.Json.decodificar(~s("\\uD800x"))
      assert motivo == "escape \\uD800 inválido: un surrogate sin su par"

      # Integer.parse/2 acepta un signo; el decodificador no.
      assert {:error, _} = AnchoFijo.Json.decodificar(~s("\\u-001"))
      assert {:error, _} = AnchoFijo.Json.decodificar(~s("\\u12"))
      assert {:error, "número JSON fuera de rango: 1e999"} = AnchoFijo.Json.decodificar("1e999")

      assert {:error, [%Diagnostico{tipo: :entrada} = d]} =
               Layout.desde_json(~s({"campos":[{"nombre":"a\\uZZZZ","largo":2}]}))

      assert d.recibido =~ "escape \\uZZZZ inválido"

      assert {:error, [%Diagnostico{tipo: :entrada}]} =
               Multiregistro.desde_json(~s({"registros":[{"tipo":"\\uD83D"}]}))
    end

    property "decodificar/1 nunca levanta ni lanza: {:ok, _} o {:error, _} para cualquier binario" do
      con_escapes =
        gen all(
              trozos <-
                list_of(
                  one_of([
                    string(:ascii, max_length: 6),
                    constant("\\"),
                    constant("\\u"),
                    string(:alphanumeric, length: 4),
                    constant(~s(")),
                    constant("\\ud83d\\ude00"),
                    constant("1e"),
                    constant("999999")
                  ]),
                  max_length: 8
                )
            ) do
          ~s(") <> Enum.join(trozos) <> ~s(")
        end

      check all(binario <- one_of([binary(), string(:printable), con_escapes])) do
        resultado = AnchoFijo.Json.decodificar(binario)

        assert match?({:ok, _}, resultado) or
                 match?({:error, motivo} when is_binary(motivo), resultado)
      end
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
