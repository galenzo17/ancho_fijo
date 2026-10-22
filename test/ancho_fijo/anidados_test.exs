defmodule AnchoFijo.AnidadosTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  import AnchoFijo.Fixtures, only: [ruta: 1, leer: 1, layout_anidado: 0]
  import AnchoFijo.Test

  alias AnchoFijo.Campo
  alias AnchoFijo.Diagnostico
  alias AnchoFijo.Layout
  alias AnchoFijo.Test.Generadores

  defp primera_linea, do: leer("nomina_anidada.txt") |> String.split("\n") |> hd()

  describe "un grupo (OCCURS) y una variante (REDEFINES)" do
    test "el fixture se lee con la lista de repeticiones y el mapa de la variante elegida" do
      assert layout_anidado().largo == 69

      assert {:ok, [primero, segundo, tercero], []} =
               AnchoFijo.parsear(layout_anidado(), ruta("nomina_anidada.txt"))

      assert primero.totales == [
               %{moneda: "CLP", importe: {125_000, 2}},
               %{moneda: "USD", importe: {1250, 2}},
               %{moneda: "EUR", importe: {0, 2}}
             ]

      assert primero.destino == %{banco: "001", cuenta: 12_345_678}
      assert segundo.destino == %{clabe: "012345678901234567"}
      assert tercero.destino == %{banco: "012", cuenta: 42}
    end

    test "round-trip byte a byte, y los helpers de test lo expresan en una línea" do
      contenido = leer("nomina_anidada.txt")
      {:ok, registros, []} = AnchoFijo.parsear(layout_anidado(), contenido)
      assert {:ok, ^contenido, []} = AnchoFijo.escribir(layout_anidado(), registros)
      assert_round_trip(layout_anidado(), hd(registros))
    end

    test "un campo interno roto se diagnostica con su ruta y su posición absoluta" do
      linea = String.replace(primera_linea(), "USD0000001250", "USD00000X1250")
      {:error, [d]} = AnchoFijo.parsear(layout_anidado(), linea <> "\n")
      assert %Diagnostico{campo: "totales[2].importe", posicion: {29, 38}, linea: 1} = d
      assert Diagnostico.mensaje(d) =~ "campo totales[2].importe (posiciones 29-38)"

      linea = String.replace(primera_linea(), "001000000012345678", "001000000012345X78")
      {:error, [d]} = AnchoFijo.parsear(layout_anidado(), linea <> "\n")
      assert %Diagnostico{campo: "destino.cuenta", posicion: {55, 69}} = d
    end

    test "un valor sin variante es un diagnóstico que lista las que hay" do
      linea = "09" <> String.slice(primera_linea(), 2..-1//1)
      {:error, [d]} = AnchoFijo.parsear(layout_anidado(), linea <> "\n")
      assert %Diagnostico{campo: :destino, posicion: {52, 69}} = d
      assert d.esperado == "un valor de :tipo_cuenta con variante declarada: \"01\", \"02\""
      assert d.recibido == "\"09\""
    end

    test "al escribir, la lista trae exactamente las repeticiones, y la variante un mapa" do
      {:ok, [registro | _], []} = AnchoFijo.parsear(layout_anidado(), ruta("nomina_anidada.txt"))

      assert {:error, [d]} =
               AnchoFijo.escribir(layout_anidado(), [
                 %{registro | totales: Enum.take(registro.totales, 2)}
               ])

      assert d.campo == :totales
      assert d.esperado == "una lista de 3 mapas, una por repetición del grupo"

      assert {:error, [d]} = AnchoFijo.escribir(layout_anidado(), [%{registro | destino: "x"}])
      assert d.esperado == "un mapa con los campos de la variante"

      assert {:error, [d]} =
               AnchoFijo.escribir(layout_anidado(), [%{registro | destino: %{banco: "001"}}])

      assert d.campo == "destino.cuenta"

      assert {:error, [d]} = AnchoFijo.escribir(layout_anidado(), [%{registro | tipo_cuenta: "77"}])
      assert d.campo == :destino
    end

    test "una variante más corta se completa con blanco al escribir cuando el campo declara el largo" do
      layout =
        Layout.nuevo!(
          campos: [
            [nombre: :t, largo: 1],
            [
              nombre: :v,
              tipo: :variante,
              segun: :t,
              largo: 6,
              variantes: %{"a" => [[nombre: :x, largo: 2]], "b" => [[nombre: :y, largo: 6]]}
            ]
          ]
        )

      assert {:ok, "axy    \n", []} = AnchoFijo.escribir(layout, [%{t: "a", v: %{x: "xy"}}])
      assert {:ok, [%{t: "a", v: %{x: "xy"}}], []} = AnchoFijo.parsear(layout, "axy    \n")
    end

    test "la definición: largo calculado o verificado, segun anterior, campos internos válidos" do
      assert Campo.nuevo!(nombre: :g, tipo: :grupo, repetir: 4, campos: [[nombre: :a, largo: 3]]).largo ==
               12

      assert Campo.nuevo!(nombre: :g, tipo: :grupo, campos: [[nombre: :a, largo: 3]]).repetir == 1

      assert {:error, [d]} =
               Campo.nuevo(
                 nombre: :g,
                 tipo: :grupo,
                 repetir: 2,
                 largo: 5,
                 campos: [[nombre: :a, largo: 3]]
               )

      assert d.esperado == "un :largo de 6, el de una repetición por :repetir, o ninguno"

      assert {:error, [d]} =
               Campo.nuevo(nombre: :g, tipo: :grupo, repetir: 0, campos: [[nombre: :a, largo: 3]])

      assert d.esperado == "un :repetir entero mayor que cero"

      assert {:error, [d]} =
               Campo.nuevo(
                 nombre: :g,
                 tipo: :grupo,
                 campos: [[nombre: :a, largo: 3], [nombre: :a, largo: 2]]
               )

      assert d.campo == :g
      assert d.esperado == "nombres únicos dentro del grupo"

      assert {:error, [d]} =
               Campo.nuevo(
                 nombre: :g,
                 tipo: :grupo,
                 campos: [[nombre: :a, largo: 3], [nombre: :b, largo: 2, posicion: 2]]
               )

      assert d.campo == "g.b"
      assert d.causa_probable =~ "se solapa"

      assert {:error, [d]} = Campo.nuevo(nombre: :g, tipo: :grupo, campos: [[nombre: :a, largo: 0]])
      assert d.campo == "g.a"

      assert {:error, [d]} =
               Campo.nuevo(
                 nombre: :v,
                 tipo: :variante,
                 segun: :t,
                 largo: 3,
                 variantes: %{"a" => [[nombre: :x, largo: 5]]}
               )

      assert d.esperado == "un :largo de al menos 5, la variante más ancha, o ninguno"

      assert {:error, [d]} =
               Layout.nuevo(
                 campos: [
                   [
                     nombre: :v,
                     tipo: :variante,
                     segun: :t,
                     variantes: %{"a" => [[nombre: :x, largo: 2]]}
                   ],
                   [nombre: :t, largo: 1]
                 ]
               )

      assert d.esperado == "un :segun que venga antes de la variante en el layout"

      assert {:error, [d]} =
               Layout.nuevo(
                 campos: [
                   [
                     nombre: :v,
                     tipo: :variante,
                     segun: :nada,
                     variantes: %{"a" => [[nombre: :x, largo: 2]]}
                   ]
                 ]
               )

      assert d.esperado == "un :segun que sea un campo de este layout"

      assert {:error, [d]} = Campo.nuevo(nombre: :a, largo: 2, repetir: 3)
      assert d.esperado == ":repetir solo en campos :grupo"
    end

    test "con un segun entero las claves pueden ser enteros, y desde JSON strings" do
      layout = [
        campos: [
          [nombre: :t, largo: 1, tipo: :entero],
          [
            nombre: :v,
            tipo: :variante,
            segun: :t,
            variantes: %{1 => [[nombre: :x, largo: 2]], 2 => [[nombre: :y, largo: 2]]}
          ]
        ]
      ]

      assert {:ok, [%{t: 2, v: %{y: "ab"}}], []} = AnchoFijo.parsear(layout, "2ab\n")

      {:ok, construido} = Layout.nuevo(layout)
      {:ok, releido} = construido |> Layout.a_json() |> Layout.desde_json()
      assert {:ok, [%{t: 2, v: %{y: "ab"}}], []} = AnchoFijo.parsear(releido, "2ab\n")
    end
  end

  describe "con el resto de la librería" do
    test "a_mapa/1 y desde_mapa/1 son inversos con campos anidados" do
      mapa = Layout.a_mapa(layout_anidado())
      [_, _, totales, destino] = mapa["campos"]

      assert totales["tipo"] == "grupo" and totales["repetir"] == 3 and
               length(totales["campos"]) == 2

      assert destino["segun"] == "tipo_cuenta" and Map.keys(destino["variantes"]) == ["01", "02"]
      assert Layout.desde_mapa(mapa) == {:ok, layout_anidado()}
      assert layout_anidado() |> Layout.a_json() |> Layout.desde_json() == {:ok, layout_anidado()}
    end

    test "documentar/2 muestra los campos internos con su ruta y posiciones relativas" do
      markdown = AnchoFijo.Documentacion.documentar(layout_anidado())
      assert markdown =~ "| `totales` | 13-51 | 39 | grupo | 3 repeticiones | no |"

      assert markdown =~
               "| `totales[].importe` | 4-13 (relativas) | 10 | decimal | 2 decimales implícitos | no |"

      assert markdown =~ "| `destino` | 52-69 | 18 | variante | según `tipo_cuenta` | no |"
      assert markdown =~ "| `destino{01}.cuenta` | 4-18 (relativas) | 15 | entero |  | no |"
      assert markdown =~ "| `destino{02}.clabe` | 1-18 (relativas) | 18 | texto |  | no |"

      en = AnchoFijo.Documentacion.documentar(layout_anidado(), idioma: :en, formato: :csv)
      assert en =~ "totales;13-51;39;group;3 repetitions;no;;;\n"
    end

    property "los generadores producen registros anidados válidos" do
      check all(registro <- Generadores.registro(layout_anidado())) do
        assert length(registro.totales) == 3
        assert registro.tipo_cuenta in ["01", "02"]
        assert_round_trip(layout_anidado(), registro)
      end
    end
  end
end
