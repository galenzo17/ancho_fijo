defmodule AnchoFijo.ReglasTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  import AnchoFijo.Test

  alias AnchoFijo.Campo
  alias AnchoFijo.Diagnostico
  alias AnchoFijo.Documentacion
  alias AnchoFijo.Layout
  alias AnchoFijo.Multiregistro
  alias AnchoFijo.Test.Generadores

  # Un layout con una regla de cada clase: catálogo, rango, patrón y las dos
  # condiciones cruzadas. 30 posiciones.
  defp layout(opts \\ []) do
    Layout.nuevo!(
      Keyword.merge(
        [
          campos: [
            [nombre: :tipo, largo: 2, en: ["01", "02"]],
            [
              nombre: :monto,
              largo: 8,
              tipo: :decimal,
              precision: 2,
              rango: {{0, 0}, {1_000_000, 2}}
            ],
            [
              nombre: :fecha,
              largo: 8,
              tipo: :fecha,
              formato: :aaaammdd,
              rango: {~D[2000-01-01], nil}
            ],
            [nombre: :codigo, largo: 4, patron: ~r/^[A-Z]{2}\d{2}$/],
            [
              nombre: :banco,
              largo: 3,
              tipo: :entero,
              opcional: true,
              requerido_si: [campo: :tipo, en: ["02"]]
            ],
            [nombre: :glosa, largo: 5, opcional: true, prohibido_si: [campo: :banco]]
          ]
        ],
        opts
      )
    )
  end

  # El mismo layout, con el generador que el patrón de :codigo necesita.
  defp con_generador_de_codigo do
    letras = StreamData.string(?A..?Z, length: 2)
    digitos = StreamData.string(?0..?9, length: 2)
    codigo = StreamData.map({letras, digitos}, fn {l, d} -> l <> d end)

    campos =
      Enum.map(layout().campos, fn
        %Campo{nombre: :codigo} = campo -> %{campo | generador: codigo}
        campo -> campo
      end)

    %{layout() | campos: campos}
  end

  defp linea(sobre) do
    base = %{
      tipo: "01",
      monto: "00012500",
      fecha: "20240515",
      codigo: "AB12",
      banco: "   ",
      glosa: "     "
    }

    m = Map.merge(base, sobre)
    m.tipo <> m.monto <> m.fecha <> m.codigo <> m.banco <> m.glosa <> "\n"
  end

  describe "al leer" do
    test "una línea que cumple todas las reglas no trae diagnósticos" do
      assert {:ok, [registro], []} = AnchoFijo.parsear(layout(), linea(%{}))
      assert registro.tipo == "01" and registro.monto == {12_500, 2}
    end

    test "un valor fuera del catálogo es un diagnóstico :regla con la posición del campo" do
      assert {:error, [d]} = AnchoFijo.parsear(layout(), linea(%{tipo: "09"}))
      assert %Diagnostico{tipo: :regla, campo: :tipo, linea: 1, posicion: {1, 2}} = d
      assert d.esperado == ~s(un valor en "01", "02")
      assert d.recibido == ~s("09")
      assert Diagnostico.mensaje(d) =~ "catálogo"
    end

    test "el rango se evalúa sobre el valor convertido: decimal con tupla y fecha" do
      assert {:error, [d]} = AnchoFijo.parsear(layout(), linea(%{monto: "99999999"}))
      assert %Diagnostico{tipo: :regla, campo: :monto} = d
      assert d.esperado == "un valor entre {0, 0} y {1000000, 2}"

      assert {:error, [d]} = AnchoFijo.parsear(layout(), linea(%{fecha: "19991231"}))
      assert %Diagnostico{tipo: :regla, campo: :fecha} = d
      assert d.esperado == "un valor de ~D[2000-01-01] en adelante"
    end

    test "el patrón se exige al texto" do
      assert {:error, [d]} = AnchoFijo.parsear(layout(), linea(%{codigo: "ab12"}))
      assert %Diagnostico{tipo: :regla, campo: :codigo, posicion: {19, 22}} = d
      assert d.esperado =~ "~r/^[A-Z]{2}\\d{2}$/"
    end

    test "en: con función" do
      layout =
        Layout.nuevo!(campos: [[nombre: :n, largo: 3, tipo: :entero, en: &(rem(&1, 2) == 0)]])

      assert {:ok, [%{n: 4}], []} = AnchoFijo.parsear(layout, "004\n")
      assert {:error, [%Diagnostico{tipo: :regla, campo: :n}]} = AnchoFijo.parsear(layout, "005\n")
    end

    test "un opcional en blanco no se valida contra en:, rango: ni patron:" do
      layout = Layout.nuevo!(campos: [[nombre: :c, largo: 4, opcional: true, patron: ~r/^\d+$/]])
      assert {:ok, [%{c: nil}], []} = AnchoFijo.parsear(layout, "    \n")
    end

    test "requerido_si: reclama el campo cuando la condición se cumple y está en blanco" do
      assert {:ok, [_], []} = AnchoFijo.parsear(layout(), linea(%{tipo: "02", banco: "012"}))
      assert {:error, [d]} = AnchoFijo.parsear(layout(), linea(%{tipo: "02"}))
      assert %Diagnostico{tipo: :regla, campo: :banco, posicion: {23, 25}} = d
      assert d.esperado == ~s(un valor, porque :tipo es "02")
      assert d.recibido == "nil"
    end

    test "prohibido_si: reclama el campo cuando viene con valor y el otro también" do
      assert {:ok, [_], []} = AnchoFijo.parsear(layout(), linea(%{glosa: "hola "}))
      assert {:error, [d]} = AnchoFijo.parsear(layout(), linea(%{banco: "012", glosa: "hola "}))
      assert %Diagnostico{tipo: :regla, campo: :glosa} = d
      assert d.esperado == "ningún valor, porque :banco tiene valor (12)"
    end

    test "en modo tolerante el registro se entrega igual y la regla queda como error en los diagnósticos" do
      assert {:ok, [%{tipo: "09"}], [d]} =
               AnchoFijo.parsear(layout(), linea(%{tipo: "09"}), modo: :tolerante)

      assert d.tipo == :regla and d.gravedad == :error
    end

    test "en un multiregistro estricto la regla corta igual que un error de tipo" do
      multi =
        Multiregistro.nuevo!(
          discriminador: [posicion: 1, largo: 2],
          registros: [
            uno: [
              valor: "01",
              layout: [
                campos: [
                  [nombre: :tipo, largo: 2],
                  [nombre: :n, largo: 2, tipo: :entero, rango: {1, 10}]
                ]
              ]
            ]
          ]
        )

      assert {:ok, [uno: %{n: 5}], []} = AnchoFijo.parsear(multi, "0105\n")

      assert {:error, [%Diagnostico{tipo: :regla, campo: :n, linea: 2}]} =
               AnchoFijo.parsear(multi, "0105\n0199\n")

      assert {:ok, [_, _], [%Diagnostico{tipo: :regla}]} =
               AnchoFijo.parsear(multi, "0105\n0199\n", modo: :tolerante)
    end

    test "un campo sensible redacta el valor que incumple la regla" do
      layout = Layout.nuevo!(campos: [[nombre: :c, largo: 4, sensible: true, patron: ~r/^\d+$/]])
      assert {:error, [d]} = AnchoFijo.parsear(layout, "QZX7\n")
      assert d.sensible
      refute Diagnostico.mensaje(d) =~ "QZX7"
      refute inspect(d) =~ "QZX7"
      assert Diagnostico.mensaje(d, revelar: true) =~ "QZX7"
    end
  end

  describe "al escribir" do
    test "las mismas reglas rechazan el registro, con el mismo diagnóstico" do
      bueno = %{
        tipo: "01",
        monto: {12_500, 2},
        fecha: ~D[2024-05-15],
        codigo: "AB12",
        banco: nil,
        glosa: nil
      }

      assert {:ok, linea, []} = AnchoFijo.escribir(layout(), [bueno])
      assert linea == linea(%{})

      assert {:error, [%Diagnostico{tipo: :regla, campo: :tipo}]} =
               AnchoFijo.escribir(layout(), [%{bueno | tipo: "09"}])

      assert {:error, [%Diagnostico{tipo: :regla, campo: :monto}]} =
               AnchoFijo.escribir(layout(), [%{bueno | monto: {200_000_000, 2}}])

      assert {:error, [%Diagnostico{tipo: :regla, campo: :codigo}]} =
               AnchoFijo.escribir(layout(), [%{bueno | codigo: "ab12"}])

      assert {:error, [%Diagnostico{tipo: :regla, campo: :banco}]} =
               AnchoFijo.escribir(layout(), [%{bueno | tipo: "02"}])

      assert {:error, [%Diagnostico{tipo: :regla, campo: :glosa}]} =
               AnchoFijo.escribir(layout(), [%{bueno | banco: 12, glosa: "x"}])
    end
  end

  describe "en el layout" do
    test "las reglas mal escritas son diagnósticos de layout" do
      assert {:error, [d]} = Campo.nuevo(nombre: :a, largo: 2, en: [])
      assert d.esperado =~ "en: una lista de valores admitidos, no vacía"

      assert {:error, [d]} = Campo.nuevo(nombre: :a, largo: 2, rango: {1, 2})
      assert d.esperado =~ ":rango solo en campos"

      assert {:error, [d]} = Campo.nuevo(nombre: :a, largo: 2, tipo: :entero, rango: {5, 1})
      assert d.esperado == "un :rango con el mínimo antes que el máximo"

      assert {:error, [d]} = Campo.nuevo(nombre: :a, largo: 2, tipo: :entero, rango: {nil, nil})
      assert d.esperado == "un :rango con al menos un extremo"

      assert {:error, [d]} = Campo.nuevo(nombre: :a, largo: 2, tipo: :entero, patron: ~r/x/)
      assert d.esperado == ":patron solo en campos :texto"

      assert {:error, [d]} = Campo.nuevo(nombre: :a, largo: 2, patron: "x")
      assert d.esperado =~ "expresión regular"

      assert {:error, [d]} = Campo.nuevo(nombre: :a, largo: 2, requerido_si: :otro)
      assert d.esperado == ":requerido_si como [campo: nombre] o [campo: nombre, en: [valores]]"
    end

    test "una condición que nombra un campo que no existe es un error del layout" do
      assert {:error, [d]} =
               Layout.nuevo(campos: [[nombre: :a, largo: 2, prohibido_si: [campo: :zzz]]])

      assert %Diagnostico{tipo: :layout, campo: :a} = d
      assert d.esperado == ":prohibido_si con un campo de este layout"
      assert d.recibido == ":zzz"
    end
  end

  describe "serialización y documentación" do
    test "a_mapa/1 y desde_mapa/1 conservan patrón, rangos y condiciones" do
      layout = layout(nombre: "con reglas")
      mapa = Layout.a_mapa(layout)
      [tipo, monto, fecha, codigo, banco, glosa] = mapa["campos"]

      assert tipo["en"] == ["01", "02"]
      assert monto["rango"] == [[0, 0], [1_000_000, 2]]
      assert fecha["rango"] == ["2000-01-01", nil]
      assert codigo["patron"] == %{"patron" => "^[A-Z]{2}\\d{2}$", "opciones" => ""}
      assert banco["requerido_si"] == %{"campo" => "tipo", "en" => ["02"]}
      assert glosa["prohibido_si"] == %{"campo" => "banco"}

      assert {:ok, vuelta} = Layout.desde_mapa(mapa)
      assert vuelta == layout
      assert {:ok, ^layout} = layout |> Layout.a_json() |> Layout.desde_json()
    end

    test "un en: con función no se puede serializar" do
      layout = Layout.nuevo!(campos: [[nombre: :n, largo: 3, tipo: :entero, en: &(&1 > 0)]])
      assert_raise ArgumentError, ~r/función/, fn -> Layout.a_mapa(layout) end
    end

    test "documentar/2 muestra las reglas en su columna, en los dos idiomas" do
      es = Documentacion.documentar(layout())
      assert es =~ ~s(| `tipo` | 1-2 | 2 | texto |  | no | uno de "01", "02" |)
      assert es =~ "| rango {0, 0}..{1000000, 2} |"
      assert es =~ "| rango ≥ ~D[2000-01-01] |"
      assert es =~ "| patrón ~r/^[A-Z]{2}\\d{2}$/ |"
      assert es =~ ~s(| requerido si `tipo` ∈ "02" |)
      assert es =~ "| prohibido si `banco` |"

      en = Documentacion.documentar(layout(), idioma: :en, formato: :csv)
      assert en =~ ~s(tipo;1-2;2;text;;no;"one of ""01"", ""02""";;\n)
      assert en =~ ~s("required if `tipo` ∈ ""02""")
      assert en =~ "forbidden if `banco`"
    end
  end

  describe "generadores" do
    property "los registros generados cumplen las reglas y hacen el viaje de ida y vuelta" do
      layout = con_generador_de_codigo()

      check all(registro <- Generadores.registro(layout)) do
        assert registro.tipo in ["01", "02"]
        assert registro.codigo =~ ~r/^[A-Z]{2}\d{2}$/
        assert {:ok, _, []} = AnchoFijo.escribir(layout, [registro])
        assert_round_trip(layout, registro)
      end
    end

    property "generador: manda sobre lo que se deduciría del tipo" do
      layout =
        Layout.nuevo!(
          campos: [
            [
              nombre: :c,
              largo: 4,
              patron: ~r/^[A-Z]{2}\d{2}$/,
              generador: StreamData.constant("AB12")
            ],
            [nombre: :n, largo: 3, tipo: :entero, rango: {10, 20}]
          ]
        )

      check all(registro <- Generadores.registro(layout)) do
        assert registro.c == "AB12"
        assert registro.n in 10..20
        assert_round_trip(layout, registro)
      end
    end

    test "el layout entero sin generador: para el patrón no se puede generar, y lo dice" do
      assert_raise ArgumentError, ~r/:codigo tiene un :patron/, fn ->
        Generadores.registro(layout())
      end
    end

    test "un patrón o un en: con función sin generador: no se pueden generar" do
      con_patron = Layout.nuevo!(campos: [[nombre: :c, largo: 4, patron: ~r/^\d+$/]])
      assert_raise ArgumentError, ~r/generador:/, fn -> Generadores.registro(con_patron) end

      con_fun = Layout.nuevo!(campos: [[nombre: :n, largo: 3, tipo: :entero, en: &(&1 > 0)]])
      assert_raise ArgumentError, ~r/generador:/, fn -> Generadores.registro(con_fun) end
    end
  end
end
