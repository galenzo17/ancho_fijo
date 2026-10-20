defmodule AnchoFijo.MontoTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias AnchoFijo.Campo
  alias AnchoFijo.Diagnostico
  alias AnchoFijo.Layout
  alias AnchoFijo.Monto

  describe "moneda: en el layout" do
    test "sin moneda el valor sigue siendo la tupla de siempre" do
      layout = Layout.nuevo!(campos: [[nombre: :monto, largo: 10, tipo: :decimal, precision: 2]])
      assert {:ok, [%{monto: {125_000, 2}}], []} = AnchoFijo.parsear(layout, "0000125000\n")
    end

    test "con moneda el valor es un Monto y la precisión sale de la tabla" do
      layout = Layout.nuevo!(campos: [[nombre: :monto, largo: 10, tipo: :decimal, moneda: :clp]])
      assert Layout.campo(layout, :monto).precision == 0

      assert {:ok, [%{monto: monto}], []} = AnchoFijo.parsear(layout, "0000125000\n")
      assert monto == Monto.nuevo(125_000, :clp)
      assert monto.precision == 0

      usd =
        Layout.nuevo!(
          campos: [[nombre: :monto, largo: 10, tipo: :decimal, moneda: :usd, signo: :final]]
        )

      assert {:ok, [%{monto: monto}], []} = AnchoFijo.parsear(usd, "000012500-\n")
      assert monto == Monto.nuevo(-12_500, :usd)
      assert inspect(monto) == "#AnchoFijo.Monto<-125,00 USD>"
    end

    test "moneda: :clp con precision: 2 es un layout inválido que explica por qué" do
      assert {:error, [diagnostico]} =
               Layout.nuevo(
                 campos: [[nombre: :monto, largo: 10, tipo: :decimal, moneda: :clp, precision: 2]]
               )

      assert diagnostico.tipo == :layout
      assert diagnostico.esperado == "precision: 0 para CLP, que es su escala ISO 4217"
      assert diagnostico.recibido == "2"
      assert diagnostico.causa_probable =~ "CLP no tiene decimales"

      assert {:error, [diagnostico]} =
               Layout.nuevo(
                 campos: [[nombre: :monto, largo: 10, tipo: :decimal, moneda: :kwd, precision: 2]]
               )

      assert diagnostico.causa_probable =~ "KWD tiene 3 decimales"
    end

    test "la precisión coincidente con la tabla se acepta" do
      assert {:ok, _} =
               Layout.nuevo(
                 campos: [[nombre: :m, largo: 10, tipo: :decimal, moneda: :usd, precision: 2]]
               )
    end

    test "una moneda fuera de la tabla: con precisión es advertencia, sin precisión es error" do
      assert {:ok, layout} =
               Layout.nuevo(
                 campos: [[nombre: :m, largo: 10, tipo: :decimal, moneda: :xyz, precision: 3]]
               )

      assert [%Diagnostico{tipo: :layout, campo: :m}] = layout.advertencias
      assert Diagnostico.mensaje(hd(layout.advertencias)) =~ "no se pudo verificar"

      assert {:ok, [%{m: monto}], []} = AnchoFijo.parsear(layout, "0000001234\n")
      assert monto == Monto.nuevo(1234, 3, :xyz)

      assert {:error, [diagnostico]} =
               Layout.nuevo(campos: [[nombre: :m, largo: 10, tipo: :decimal, moneda: :xyz]])

      assert diagnostico.causa_probable =~ "sin :precision no se sabe la escala"
    end

    test "moneda solo aplica a :decimal y tiene que ser un átomo" do
      assert {:error, [diagnostico]} =
               Campo.nuevo(nombre: :m, largo: 10, tipo: :entero, moneda: :clp)

      assert diagnostico.esperado == ":moneda solo en campos :decimal"

      assert {:error, [diagnostico]} =
               Campo.nuevo(nombre: :m, largo: 10, tipo: :decimal, precision: 2, moneda: "CLP")

      assert diagnostico.esperado =~ "una :moneda como átomo ISO 4217"
    end
  end

  describe "aritmética" do
    test "sumar exige la misma moneda y devuelve diagnóstico, no excepción" do
      assert {:ok, total} = Monto.sumar(Monto.nuevo(1000, :clp), Monto.nuevo(250, :clp))
      assert total == Monto.nuevo(1250, :clp)

      assert {:error, diagnostico} = Monto.sumar(Monto.nuevo(1000, :clp), Monto.nuevo(250, :usd))
      assert diagnostico.tipo == :moneda
      assert Diagnostico.mensaje(diagnostico) =~ "llegó CLP y USD"

      assert_raise AnchoFijo.Error, ~r/monedas distintas/, fn ->
        Monto.sumar!(Monto.nuevo(1, :clp), Monto.nuevo(1, :usd))
      end
    end

    test "la misma moneda con escalas distintas también es un diagnóstico" do
      assert {:error, diagnostico} =
               Monto.sumar(Monto.nuevo(100, 2, :xyz), Monto.nuevo(100, 3, :xyz))

      assert diagnostico.causa_probable =~ "escalas distintas"
    end

    test "restar, negar, cero y total" do
      assert {:ok, Monto.nuevo(-50, :usd)} ==
               Monto.restar(Monto.nuevo(100, :usd), Monto.nuevo(150, :usd))

      assert Monto.negar(Monto.nuevo(5, :eur)) == Monto.nuevo(-5, :eur)
      assert Monto.cero(:jpy) == Monto.nuevo(0, :jpy)

      montos = Enum.map(1..100, &Monto.nuevo(&1, :clp))
      assert {:ok, Monto.nuevo(5050, :clp)} == Monto.total(montos)
      assert {:ok, Monto.nuevo(0, :clp)} == Monto.total([], :clp)
      assert {:error, %Diagnostico{tipo: :moneda}} = Monto.total([])

      assert {:error, %Diagnostico{tipo: :moneda}} =
               Monto.total([Monto.nuevo(1, :clp), Monto.nuevo(1, :usd)])
    end

    test "el total de una nómina parseada se reduce sin pasar por floats" do
      layout = Layout.nuevo!(campos: [[nombre: :monto, largo: 12, tipo: :decimal, moneda: :clp]])
      contenido = Enum.map_join(1..1000, "\n", &String.pad_leading("#{&1 * 1000}", 12, "0")) <> "\n"

      {:ok, registros, []} = AnchoFijo.parsear(layout, contenido)
      assert {:ok, total} = registros |> Enum.map(& &1.monto) |> Monto.total()
      assert total == Monto.nuevo(500_500_000, :clp)
      assert Monto.formatear(total) == "500.500.000 CLP"
    end
  end

  describe "formatear/2 y a_decimal/1" do
    test "formatea con la escala de la moneda" do
      assert Monto.formatear(Monto.nuevo(0, :clp)) == "0 CLP"
      assert Monto.formatear(Monto.nuevo(-5, :usd)) == "-0,05 USD"
      assert Monto.formatear(Monto.nuevo(1_000_000, :jpy)) == "1.000.000 JPY"
      assert Monto.formatear(Monto.nuevo(1_234_567, :kwd)) == "1.234,567 KWD"
      assert to_string(Monto.nuevo(99, :eur)) == "0,99 EUR"
    end

    test "a_decimal da el Decimal exacto" do
      assert Decimal.equal?(Monto.a_decimal(Monto.nuevo(-123_456, :usd)), Decimal.new("-1234.56"))
      assert Decimal.equal?(Monto.a_decimal(Monto.nuevo(125_000, :clp)), Decimal.new("125000"))
    end
  end

  describe "propiedades" do
    defp monto(moneda) do
      gen all(unidades <- integer(-1_000_000_000_000..1_000_000_000_000)) do
        Monto.nuevo(unidades, moneda)
      end
    end

    property "ninguna operación introduce un float, y sumar es exacta" do
      check all(moneda <- member_of([:clp, :usd, :kwd]), a <- monto(moneda), b <- monto(moneda)) do
        {:ok, suma} = Monto.sumar(a, b)
        assert is_integer(suma.unidades)
        assert suma.unidades == a.unidades + b.unidades

        {:ok, resta} = Monto.restar(suma, b)
        assert resta == a

        assert is_integer(Monto.negar(a).unidades)

        assert Decimal.equal?(
                 Monto.a_decimal(suma),
                 Decimal.add(Monto.a_decimal(a), Monto.a_decimal(b))
               )
      end
    end

    property "formatear es reversible: los dígitos del texto son las unidades" do
      check all(moneda <- member_of([:clp, :usd, :kwd]), m <- monto(moneda)) do
        texto = Monto.formatear(m, codigo: false)
        digitos = texto |> String.replace(~r/[^\d]/, "") |> String.to_integer()
        assert digitos == abs(m.unidades)
        assert String.starts_with?(texto, "-") == m.unidades < 0
      end
    end

    property "un decimal con moneda parseado vuelve a sus unidades sin perder nada" do
      check all(moneda <- member_of([:clp, :usd, :kwd]), unidades <- integer(0..999_999_999)) do
        layout = Layout.nuevo!(campos: [[nombre: :m, largo: 12, tipo: :decimal, moneda: moneda]])
        linea = String.pad_leading(Integer.to_string(unidades), 12, "0") <> "\n"

        assert {:ok, [%{m: monto}], []} = AnchoFijo.parsear(layout, linea)
        assert monto == Monto.nuevo(unidades, moneda)
      end
    end
  end
end
