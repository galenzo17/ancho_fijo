defmodule AnchoFijo.LayoutTest do
  use ExUnit.Case, async: true

  alias AnchoFijo.Diagnostico
  alias AnchoFijo.Layout

  describe "construcción" do
    test "encadena las posiciones omitidas" do
      layout =
        Layout.nuevo!(
          campos: [
            [nombre: :a, largo: 3],
            [nombre: :b, largo: 10],
            [nombre: :c, largo: 2]
          ]
        )

      assert Enum.map(layout.campos, &{&1.nombre, &1.posicion, &1.largo}) == [
               {:a, 1, 3},
               {:b, 4, 10},
               {:c, 14, 2}
             ]

      assert Layout.largo(layout) == 15
      assert layout.advertencias == []
    end

    test "mezcla posiciones explícitas con encadenadas" do
      layout =
        Layout.nuevo!(campos: [[nombre: :a, posicion: 1, largo: 5], [nombre: :b, largo: 5]])

      assert Layout.campo(layout, :b).posicion == 6
    end

    test "ordena los campos por posición" do
      layout =
        Layout.nuevo!(
          campos: [
            [nombre: :ultimo, posicion: 11, largo: 5],
            [nombre: :primero, posicion: 1, largo: 10]
          ]
        )

      assert Layout.nombres(layout) == [:primero, :ultimo]
    end

    test "acepta structs de Campo ya construidos" do
      campo = AnchoFijo.Campo.nuevo!(nombre: :a, largo: 4)

      assert %Layout{} = Layout.nuevo!(campos: [campo])
    end

    test "acepta mapas como definición de campo" do
      assert %Layout{} = Layout.nuevo!(%{campos: [%{nombre: :a, largo: 4}]})
    end

    test "coercer/1 acepta layouts y definiciones" do
      {:ok, layout} = Layout.coercer(campos: [[nombre: :a, largo: 2]])

      assert Layout.coercer(layout) == {:ok, layout}
    end
  end

  describe "validación de la definición" do
    test "rechaza campos solapados" do
      {:error, [diagnostico]} =
        Layout.nuevo(
          campos: [
            [nombre: :rut, posicion: 1, largo: 10],
            [nombre: :nombre, posicion: 5, largo: 20]
          ]
        )

      assert diagnostico.tipo == :layout
      assert diagnostico.campo == :nombre
      assert diagnostico.causa_probable =~ "se solapa con el campo :rut"
    end

    test "rechaza nombres duplicados explicando la consecuencia" do
      {:error, [diagnostico]} =
        Layout.nuevo(campos: [[nombre: :monto, largo: 5], [nombre: :monto, largo: 5]])

      assert diagnostico.causa_probable =~ "sobrescribiría al primero"
    end

    test "rechaza un largo total declarado menor que los campos" do
      {:error, [diagnostico]} =
        Layout.nuevo(campos: [[nombre: :a, largo: 30]], largo: 20)

      assert Diagnostico.mensaje(diagnostico) =~ "se esperaba un :largo de al menos 30 bytes"
    end

    test "acumula todos los errores de campo, no solo el primero" do
      {:error, diagnosticos} =
        Layout.nuevo(
          campos: [
            [nombre: :a, largo: 5, tipo: :decimal],
            [nombre: :b, largo: 8, tipo: :fecha],
            [nombre: :c, largo: -1]
          ]
        )

      assert length(diagnosticos) == 3
      assert Enum.map(diagnosticos, & &1.campo) == [:a, :b, :c]
    end

    test "rechaza un layout sin campos" do
      {:error, [diagnostico]} = Layout.nuevo(campos: [])

      assert diagnostico.causa_probable =~ "no puede leer nada"
    end

    test "rechaza encoding y unidad desconocidos" do
      {:error, diagnosticos} =
        Layout.nuevo(campos: [[nombre: :a, largo: 1]], encoding: :cp1252, unidad: :palabras)

      assert length(diagnosticos) == 2
    end

    test "nuevo!/1 levanta con el reporte completo" do
      excepcion =
        assert_raise AnchoFijo.Error, fn ->
          Layout.nuevo!(campos: [[nombre: :a, largo: 0], [nombre: :b, largo: 0]])
        end

      assert length(excepcion.diagnosticos) == 2
      assert Exception.message(excepcion) =~ "campo :a"
      assert Exception.message(excepcion) =~ "campo :b"
    end

    test "rechaza opciones que no aplican al tipo del campo" do
      {:error, [diagnostico]} =
        Layout.nuevo(campos: [[nombre: :nombre, largo: 10, precision: 2]])

      assert diagnostico.causa_probable =~ "sería ignorada en silencio"
    end
  end

  describe "advertencias" do
    # Un hueco es casi siempre una zona reservada del formato. Es información,
    # no una falla: bloquear el parseo por eso obligaría a declarar campos
    # basura solo para satisfacer al validador.
    test "un hueco entre campos advierte pero no impide parsear" do
      {:ok, layout} =
        Layout.nuevo(
          campos: [
            [nombre: :a, posicion: 1, largo: 5],
            [nombre: :b, posicion: 10, largo: 5]
          ]
        )

      assert [advertencia] = layout.advertencias
      assert advertencia.causa_probable =~ "4 posiciones sin declarar"
      assert {:ok, [%{a: "AAAAA", b: "BBBBB"}]} = AnchoFijo.parsear(layout, "AAAAA----BBBBB")
    end

    test "advierte cuando el primer campo no empieza en 1" do
      {:ok, layout} = Layout.nuevo(campos: [[nombre: :a, posicion: 4, largo: 5]])

      assert [advertencia] = layout.advertencias
      assert advertencia.causa_probable =~ "primeras 3 posiciones"
    end

    test "advierte del relleno final cuando el largo declarado sobra" do
      {:ok, layout} = Layout.nuevo(campos: [[nombre: :a, largo: 10]], largo: 20)

      assert [advertencia] = layout.advertencias
      assert advertencia.causa_probable =~ "últimas 10 posiciones"
      assert Layout.largo(layout) == 20
    end
  end

  describe "consultas" do
    setup do
      {:ok, layout: Layout.nuevo!(campos: [[nombre: :a, largo: 3], [nombre: :b, largo: 4]])}
    end

    test "campo/2 encuentra por nombre", %{layout: layout} do
      assert Layout.campo(layout, :b).largo == 4
      assert Layout.campo(layout, :z) == nil
    end

    test "contexto/2 arma lo que necesita cada campo", %{layout: layout} do
      assert Layout.contexto(layout, 7) == %{encoding: :utf8, unidad: :bytes, linea: 7}
    end
  end
end
