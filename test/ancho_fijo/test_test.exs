defmodule AnchoFijo.TestTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  import AnchoFijo.Fixtures
  import AnchoFijo.Test

  alias AnchoFijo.Test.Generadores

  defp sin_codigo, do: elem(Code.eval_file(ruta("multiregistro_sin_codigo.exs")), 0)

  @con_todo AnchoFijo.Layout.nuevo!(
              identidad: [campos: [:lote]],
              campos: [
                [nombre: :lote, largo: 4, tipo: :entero, signo: :final],
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
                [
                  nombre: :cuando,
                  largo: 12,
                  tipo: :fecha_hora,
                  formato: :aaaammddhhmm,
                  opcional: true
                ],
                [nombre: :rut, largo: 9, tipo: :rut, dv: :ausente],
                [nombre: :rut_largo, largo: 12, tipo: :rut],
                [nombre: :tipo, largo: 2, tipo: :constante, valor: "01"],
                [nombre: :filler, largo: 3, tipo: :relleno, relleno: "0"],
                [nombre: :fijo, largo: 5, trim: false, relleno: "*"],
                [nombre: :glosa, largo: 6, opcional: true]
              ]
            )

  describe "assert_parsea/4" do
    test "devuelve los registros cuando coinciden, con o sin terminador" do
      esperado = %{
        rut: "12345678-9",
        beneficiario: "JUAN PEREZ SOTO",
        monto: {125_000, 2},
        fecha: ~D[2024-01-15]
      }

      assert [^esperado] =
               assert_parsea(
                 layout_nomina(),
                 leer("nomina_correcta.txt") |> String.split("\n") |> hd(),
                 esperado
               )

      assert [_, _, _] =
               assert_parsea(
                 layout_nomina(),
                 leer("nomina_correcta.txt"),
                 AnchoFijo.parsear!(layout_nomina(), ruta("nomina_correcta.txt"))
               )
    end

    test "falla con los diagnósticos en el mensaje" do
      error =
        assert_raise ExUnit.AssertionError, fn -> assert_parsea(layout_nomina(), "corta", %{}) end

      assert error.message =~ "no se pudo parsear"
      assert error.message =~ "línea 1: se esperaban 48 bytes, llegaron 5"

      error =
        assert_raise ExUnit.AssertionError, fn ->
          assert_parsea([campos: [[nombre: :a, largo: 2]]], "xy", %{a: "zz"})
        end

      assert error.message =~ "los registros no son los esperados"
      assert error.message =~ "obtenido: [%{a: \"xy\"}]"
    end
  end

  describe "assert_diagnostico/2" do
    test "encuentra el que cumple los filtros, desde cualquier forma de resultado" do
      resultado =
        AnchoFijo.parsear(layout_nomina(), ruta("nomina_fila_corta.txt"), modo: :tolerante)

      d = assert_diagnostico(resultado, tipo: :largo_de_linea, linea: 2, causa: "campo faltante")
      assert d.linea == 2

      assert %{campo: :rut} =
               assert_diagnostico(AnchoFijo.Layout.nuevo(campos: [[nombre: :rut, largo: 0]]),
                 campo: :rut,
                 esperado: ~r/largo entero/
               )

      assert_diagnostico([d], gravedad: :error, recibido: "46")
      assert_diagnostico(d, tipo: :largo_de_linea)
    end

    test "falla listando los diagnósticos que había" do
      resultado =
        AnchoFijo.parsear(layout_nomina(), ruta("nomina_fila_corta.txt"), modo: :tolerante)

      error =
        assert_raise ExUnit.AssertionError, fn -> assert_diagnostico(resultado, campo: :monto) end

      assert error.message =~ "ningún diagnóstico cumple [campo: :monto]"
      assert error.message =~ "línea 2:"

      assert_raise ExUnit.AssertionError, ~r/no es un resultado con diagnósticos/, fn ->
        assert_diagnostico(:ok, campo: :a)
      end
    end
  end

  describe "assert_round_trip/3 y assert_escribe/4" do
    test "con un layout y con un multiregistro" do
      {:ok, [registro | _], []} = AnchoFijo.parsear(layout_nomina(), ruta("nomina_correcta.txt"))
      assert assert_round_trip(layout_nomina(), registro) =~ "12345678-9"

      {:ok, registros, []} = AnchoFijo.parsear(sin_codigo(), ruta("nomina_sin_codigo.txt"))

      sin_controles =
        Enum.map(registros, fn
          {:trailer, m} -> {:trailer, Map.drop(m, [:cantidad, :total])}
          otro -> otro
        end)

      assert assert_round_trip(sin_codigo(), sin_controles) == leer("nomina_sin_codigo.txt")

      assert_escribe([campos: [[nombre: :a, largo: 3, tipo: :entero]]], %{a: 7}, "007")
    end

    test "falla cuando no se puede escribir o cuando lo leído difiere" do
      error =
        assert_raise ExUnit.AssertionError, fn ->
          assert_round_trip([campos: [[nombre: :a, largo: 2, tipo: :entero]]], %{a: 123})
        end

      assert error.message =~ "no se pudo escribir"
      assert error.message =~ "no cabe en el campo"

      error =
        assert_raise ExUnit.AssertionError, fn ->
          assert_escribe([campos: [[nombre: :a, largo: 3, tipo: :entero]]], %{a: 7}, "7  ")
        end

      assert error.message =~ "la línea escrita no es la esperada"
    end
  end

  describe "Generadores" do
    test "están disponibles en este build" do
      assert Generadores.disponible?()
    end

    property "parsear(escribir(registro)) == registro para los layouts de los fixtures y uno con todo" do
      check all(
              layout <-
                member_of([layout_nomina(), layout_glosa(), layout_respuesta_mixta(), @con_todo]),
              registro <- Generadores.registro(layout)
            ) do
        assert_round_trip(layout, registro)
      end
    end

    property "lo mismo para los multiregistros: NACHA, el fixture sin código y uno por posición" do
      por_posicion =
        AnchoFijo.Multiregistro.nuevo!(
          discriminador: [por: :posicion_en_archivo],
          registros: [
            h: [
              ubicacion: :primera,
              cantidad: :uno,
              layout: [campos: [[nombre: :t, largo: 1], [nombre: :n, largo: 3, tipo: :entero]]]
            ],
            d: [
              ubicacion: :resto,
              layout: [campos: [[nombre: :moneda, largo: 3], [nombre: :m, largo: 6, tipo: :entero]]]
            ],
            t: [
              ubicacion: :ultima,
              cantidad: :uno,
              layout: [campos: [[nombre: :total, largo: 8, tipo: :entero]]]
            ]
          ],
          controles: [[en: :t, campo: :total, suma: {:d, :m}], [en: :h, campo: :n, cuenta: :d]]
        )

      check all(
              multi <- member_of([AnchoFijo.Formatos.nacha(), sin_codigo(), por_posicion]),
              registros <- Generadores.registro(multi)
            ) do
        assert_round_trip(multi, registros)
      end
    end

    property "una línea inválida se diagnostica en el campo roto" do
      check all(
              layout <- member_of([layout_nomina(), layout_respuesta_mixta(), @con_todo]),
              %{linea: linea, campo: campo, registro: registro} <-
                Generadores.linea_invalida(layout)
            ) do
        assert is_map(registro)
        layout |> AnchoFijo.parsear(linea <> "\n") |> assert_diagnostico(campo: campo, linea: 1)
      end
    end

    property "linea/1 es lo que escribir/3 produce y se lee sin diagnósticos" do
      check all(linea <- Generadores.linea(@con_todo)) do
        assert byte_size(linea) == @con_todo.largo
        assert {:ok, [_], []} = AnchoFijo.parsear(@con_todo, linea <> "\n")
      end
    end

    test "un tipo propio sin generador/1 y un layout sin campos que romper lo dicen" do
      sin_generador = [campos: [[nombre: :x, largo: 3, tipo: AnchoFijo.TipoSoloLectura]]]

      assert_raise ArgumentError,
                   ~r/:x es de tipo AnchoFijo.TipoSoloLectura, que no implementa generador\/1/,
                   fn ->
                     Generadores.registro(sin_generador) |> Enum.take(1)
                   end

      assert_raise ArgumentError, ~r/no tiene campos numéricos/, fn ->
        Generadores.linea_invalida(campos: [[nombre: :a, largo: 2]])
      end
    end
  end
end
