defmodule AnchoFijo.InspectTest do
  # Lo que se ve de un layout, un campo y un multiregistro es lo declarado,
  # en una línea; lo completo sigue disponible a pedido.
  use ExUnit.Case, async: true

  alias AnchoFijo.Campo
  alias AnchoFijo.Layout
  alias AnchoFijo.Multiregistro

  describe "Campo" do
    test "nombre, posiciones, tipo y solo las opciones que difieren del default" do
      campo =
        Campo.nuevo!(
          nombre: :monto,
          posicion: 11,
          largo: 10,
          tipo: :decimal,
          precision: 2,
          moneda: :usd
        )

      assert inspect(campo) == "#AnchoFijo.Campo<:monto 11-20 :decimal precision: 2, moneda: :usd>"

      assert inspect(Campo.nuevo!(nombre: :n, largo: 3, tipo: :entero)) ==
               "#AnchoFijo.Campo<:n largo 3 :entero>"

      assert inspect(Campo.nuevo!(nombre: :r, posicion: 1, largo: 10, tipo: :rut, sensible: false)) ==
               "#AnchoFijo.Campo<:r 1-10 :rut sensible: false>"

      assert inspect(Campo.nuevo!(nombre: :t, posicion: 1, largo: 4, en: ["01", "02"], trim: false)) ==
               ~s(#AnchoFijo.Campo<:t 1-4 :texto trim: false, en: ["01", "02"]>)

      assert inspect(
               Campo.nuevo!(
                 nombre: :f,
                 posicion: 1,
                 largo: 8,
                 tipo: :fecha,
                 formato: :aaaammdd,
                 opcional: true
               )
             ) ==
               "#AnchoFijo.Campo<:f 1-8 :fecha opcional: true, formato: :aaaammdd>"
    end

    test "un grupo lleva sus campos adentro, con sus posiciones relativas" do
      grupo =
        Campo.nuevo!(
          nombre: :g,
          posicion: 1,
          tipo: :grupo,
          repetir: 2,
          campos: [[nombre: :a, largo: 2], [nombre: :b, largo: 3]]
        )

      assert inspect(grupo) ==
               "#AnchoFijo.Campo<:g 1-10 :grupo repetir: 2, campos: [#AnchoFijo.Campo<:a 1-2 :texto>, #AnchoFijo.Campo<:b 3-5 :texto>]>"
    end

    test "structs: false y completo: true muestran todas las claves" do
      campo = Campo.nuevo!(nombre: :n, largo: 3, tipo: :entero)

      assert inspect(campo, structs: false) =~ "__struct__: AnchoFijo.Campo"
      assert inspect(campo, structs: false) =~ "separador: :implicito"
      assert inspect(campo, custom_options: [completo: true]) =~ "%AnchoFijo.Campo{nombre: :n"
      assert inspect(campo, custom_options: [completo: true]) =~ "modulo: AnchoFijo.Tipo.Entero"
    end
  end

  describe "Layout" do
    test "una línea con lo declarado" do
      layout =
        Layout.nuevo!(
          nombre: "nómina banco X",
          encoding: :latin1,
          relleno_final: :tolerar,
          identidad: [campos: [:rut]],
          campos: [
            [nombre: :rut, largo: 10, tipo: :rut],
            [nombre: :nombre, largo: 20],
            [nombre: :monto, largo: 10, tipo: :decimal, precision: 2],
            [nombre: :fecha, largo: 8, tipo: :fecha, formato: :aaaammdd]
          ]
        )

      assert inspect(layout) ==
               ~s(#AnchoFijo.Layout<"nómina banco X", 4 campos, 48 bytes, latin1, relleno_final: :tolerar, identidad: [:rut]>)

      assert inspect(Layout.nuevo!(campos: [[nombre: :a, largo: 4]])) ==
               "#AnchoFijo.Layout<1 campo, 4 bytes>"

      assert inspect(
               Layout.nuevo!(
                 unidad: :caracteres,
                 campos: [[nombre: :a, largo: 4], [nombre: :b, largo: 2]]
               )
             ) ==
               "#AnchoFijo.Layout<2 campos, 6 caracteres>"

      con_advertencia = Layout.nuevo!(campos: [[nombre: :a, largo: 4, relleno: "·"]])
      assert inspect(con_advertencia) == "#AnchoFijo.Layout<1 campo, 4 bytes, 1 advertencia>"
    end

    test "structs: false y completo: true muestran todo, y lo que se ve coincide con lo declarado" do
      layout = Layout.nuevo!(campos: [[nombre: :a, largo: 4], [nombre: :b, largo: 2]])

      assert inspect(layout, structs: false) =~ "relleno_final: :estricto"
      assert inspect(layout, custom_options: [completo: true]) =~ "%AnchoFijo.Layout{"

      for campo <- layout.campos do
        assert inspect(campo) =~ Kernel.inspect(campo.nombre)
        assert inspect(campo) =~ "#{campo.posicion}-#{Campo.fin(campo)}"
      end

      # Un layout dentro de un mapa o un mensaje usa el resumen, y la
      # igualdad no cambia por el Inspect.
      assert inspect(%{layout: layout}) == "%{layout: #AnchoFijo.Layout<2 campos, 6 bytes>}"
      assert layout == Layout.nuevo!(campos: [[nombre: :a, largo: 4], [nombre: :b, largo: 2]])
    end
  end

  describe "Multiregistro" do
    test "una línea con el nombre, los tipos, el discriminador y el orden" do
      multi =
        Multiregistro.nuevo!(
          nombre: "NACHA",
          discriminador: [posicion: 1, largo: 2],
          orden: :libre,
          registros: [
            h: [valor: "01", cantidad: :uno, layout: [campos: [[nombre: :t, largo: 2]]]],
            d: [
              valor: "02",
              layout: [campos: [[nombre: :t, largo: 2], [nombre: :n, largo: 3, tipo: :entero]]]
            ],
            z: [
              valor: "09",
              cantidad: :uno,
              layout: [campos: [[nombre: :t, largo: 2], [nombre: :c, largo: 3, tipo: :entero]]]
            ]
          ],
          controles: [[en: :z, campo: :c, cuenta: :d]]
        )

      assert inspect(multi) ==
               ~s(#AnchoFijo.Multiregistro<"NACHA", 3 tipos, por código en 1-2, orden libre, 1 control>)

      por_largo =
        Multiregistro.nuevo!(
          discriminador: [por: :largo],
          registros: [
            a: [layout: [campos: [[nombre: :t, largo: 2]]]],
            b: [layout: [campos: [[nombre: :t, largo: 3]]]]
          ]
        )

      assert inspect(por_largo) == "#AnchoFijo.Multiregistro<2 tipos, por largo de línea>"
      assert inspect(por_largo, structs: false) =~ "orden: :estricto"
      assert inspect(por_largo, custom_options: [completo: true]) =~ "%AnchoFijo.Multiregistro{"
    end
  end
end
