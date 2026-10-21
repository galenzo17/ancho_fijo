defmodule AnchoFijo.DocumentacionTest do
  use ExUnit.Case, async: true

  import AnchoFijo.Fixtures, only: [ruta: 1, layout_nomina: 1]

  alias AnchoFijo.Documentacion
  alias AnchoFijo.Layout

  defp sin_codigo, do: elem(Code.eval_file(ruta("multiregistro_sin_codigo.exs")), 0)

  describe "markdown" do
    test "la tabla del multiregistro es la que está en el README, sin edición manual" do
      generado = Documentacion.documentar(sin_codigo())
      assert String.contains?(File.read!("README.md"), generado)
    end

    test "una tabla por tipo, el discriminador y los controles" do
      markdown = Documentacion.documentar(sin_codigo())

      assert markdown =~
               "## nómina sin código de tipo\n\nTipo de registro por el largo de la línea\n\n### header (exactamente uno)"

      assert markdown =~ "### detalle (al menos uno)"

      assert markdown =~
               "| `monto` | 27-36 | 10 | decimal | 2 decimales implícitos | no | Monto a pagar | `0000125000` |"

      assert markdown =~
               "### Controles\n\n- `trailer.cantidad` = cantidad de `detalle`\n- `trailer.total` = suma de `detalle.monto`\n"

      refute markdown =~ "\n\n\n"
    end

    test "en inglés se traducen los encabezados y los tipos, no los nombres de campo" do
      en = Documentacion.documentar(sin_codigo(), idioma: :en)
      assert en =~ "Record type by line length"
      assert en =~ "### header (exactly one)"

      assert en =~
               "| Field | Positions | Length | Type | Format | Optional | Description | Example |"

      assert en =~ "| `fecha` | 11-18 | 8 | date | AAAAMMDD | no | Fecha de pago |  |"
      assert en =~ "| `empresa` | 1-10 | 10 | RUT | check digit validated | no |"
      assert en =~ "- `trailer.cantidad` = count of `detalle`"
    end

    test "el formato describe lo que define al campo, y los nombres de tipo salen traducidos" do
      layout =
        Layout.nuevo!(
          encoding: :latin1,
          campos: [
            [nombre: :a, largo: 4, tipo: :hora, formato: :hhmm],
            [
              nombre: :b,
              largo: 14,
              tipo: :fecha_hora,
              formato: "AAMMDDHHMMSS",
              pivote: 1970,
              opcional: true
            ],
            [nombre: :c, largo: 8, tipo: :decimal, moneda: :usd, signo: :final],
            [nombre: :d, largo: 8, tipo: :decimal, precision: 2, separador: :coma],
            [nombre: :e, largo: 2, tipo: :constante, valor: "01"],
            [nombre: :f, largo: 3, tipo: :relleno, relleno: "0"],
            [nombre: :g, largo: 9, tipo: :rut, dv: :ausente],
            [nombre: :h, largo: 5, encoding: :utf8, descripcion: "con | barra"],
            [nombre: :i, largo: 4, tipo: AnchoFijo.TipoHora]
          ]
        )

      es = Documentacion.documentar(layout)
      assert es =~ "## Layout\n\n57 posiciones · latin-1 · medido en bytes"
      assert es =~ "| `a` | 1-4 | 4 | hora | HHMM | no |"
      assert es =~ "| `b` | 5-18 | 14 | fecha y hora | AAMMDDHHMMSS, pivote 1970 | sí |"
      assert es =~ "| `c` | 19-26 | 8 | decimal | USD (2 decimales), signo al final | no |"
      assert es =~ "| `d` | 27-34 | 8 | decimal | 2 decimales implícitos, separador coma | no |"
      assert es =~ "| `e` | 35-36 | 2 | constante | literal \"01\" | no |"
      assert es =~ "| `f` | 37-39 | 3 | relleno | relleno de \"0\" | no |"
      assert es =~ "| `g` | 40-48 | 9 | RUT | sin dígito verificador | no |"
      assert es =~ "| `h` | 49-53 | 5 | texto | UTF-8 | no | con \\| barra |"
      assert es =~ "| `i` | 54-57 | 4 | AnchoFijo.TipoHora |  | no |"

      en = Documentacion.documentar(layout, idioma: :en)
      assert en =~ "| `b` | 5-18 | 14 | datetime | AAMMDDHHMMSS, pivot 1970 | yes |"
      assert en =~ "| `f` | 37-39 | 3 | filler | padded with \"0\" | no |"
    end
  end

  describe "csv y json" do
    test "csv con punto y coma, una fila por campo y el tipo de registro en un multiregistro" do
      csv =
        Documentacion.documentar(
          layout_nomina(
            campos: [
              [nombre: :a, largo: 2, descripcion: "con; punto y coma"],
              [nombre: :b, largo: 3, tipo: :entero]
            ]
          ),
          formato: :csv
        )

      assert csv ==
               "Campo;Posiciones;Largo;Tipo;Formato;Opcional;Descripción;Ejemplo\na;1-2;2;texto;;no;\"con; punto y coma\";\nb;3-5;3;entero;;no;;\n"

      csv = Documentacion.documentar(sin_codigo(), formato: :csv, idioma: :en)

      assert csv =~
               "Record;Field;Positions;Length;Type;Format;Optional;Description;Example\nheader;empresa;1-10;10;RUT;check digit validated;no;RUT de la empresa pagadora;76543210-3\n"

      assert csv =~ "\ntrailer;total;7-20;14;decimal;2 implicit decimals;no;Suma de los montos;\n"
    end

    test "json con la forma de a_mapa/2, decodificable" do
      json = Documentacion.documentar(sin_codigo(), formato: :json)
      assert {:ok, decodificado} = Jason.decode(json)
      assert decodificado["nombre"] == "nómina sin código de tipo"
      assert [header, _detalle, trailer] = decodificado["registros"]
      assert header["tipo"] == "header"
      assert header["cantidad"] == "exactamente uno"
      assert hd(header["campos"])["nombre"] == "empresa"
      assert hd(header["campos"])["ejemplo"] == "76543210-3"
      assert trailer["largo"] == 20

      assert decodificado["controles"] == [
               "`trailer.cantidad` = cantidad de `detalle`",
               "`trailer.total` = suma de `detalle.monto`"
             ]

      assert Documentacion.a_mapa(campos: [[nombre: :a, largo: 2]]).campos == [
               %{
                 nombre: :a,
                 desde: 1,
                 hasta: 2,
                 largo: 2,
                 tipo: "texto",
                 formato: nil,
                 opcional: false,
                 descripcion: nil,
                 ejemplo: nil,
                 relativa: false
               }
             ]
    end
  end

  describe "opciones y errores" do
    test "formato o idioma inválidos son ArgumentError; un layout inválido levanta AnchoFijo.Error" do
      assert_raise ArgumentError, ~r/documentar\/2/, fn ->
        Documentacion.documentar(sin_codigo(), formato: :pdf)
      end

      assert_raise ArgumentError, ~r/documentar\/2/, fn ->
        Documentacion.documentar(sin_codigo(), idioma: :fr)
      end

      assert_raise AnchoFijo.Error, fn -> Documentacion.documentar(campos: []) end
    end

    test "Layout.documentar/2 y Multiregistro.documentar/2 delegan" do
      assert Layout.documentar(layout_nomina([])) == Documentacion.documentar(layout_nomina([]))

      assert AnchoFijo.Multiregistro.documentar(sin_codigo(), idioma: :en) ==
               Documentacion.documentar(sin_codigo(), idioma: :en)
    end

    test "descripcion y ejemplo se ignoran al parsear y se validan como texto" do
      layout = Layout.nuevo!(campos: [[nombre: :a, largo: 2, descripcion: "la a", ejemplo: "xy"]])
      assert {:ok, [%{a: "xy"}], []} = AnchoFijo.parsear(layout, "xy\n")

      assert {:error, [d]} = AnchoFijo.Campo.nuevo(nombre: :a, largo: 2, descripcion: 42)
      assert d.esperado == ":descripcion como texto, o ninguno"
    end
  end
end
