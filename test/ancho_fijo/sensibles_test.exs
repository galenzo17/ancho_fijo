defmodule AnchoFijo.SensiblesTest do
  # Verifica una ausencia: que el valor de un campo sensible no aparezca en
  # ninguna representación de texto de su diagnóstico, en ningún tipo de
  # campo ni de falla. Y que sí aparezca cuando se pide revelar.
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias AnchoFijo.Campo
  alias AnchoFijo.Diagnostico
  alias AnchoFijo.Layout

  # Un valor que no aparece por casualidad en ningún mensaje.
  @centinela "QZX7"

  # Cada caso: definición del campo, línea que lo hace fallar, qué parte del
  # valor no debe filtrarse, y una pista de por qué falla (para el nombre).
  @casos [
    {"entero con letras", [nombre: :c, largo: 8, tipo: :entero], "00#{@centinela}01", @centinela},
    {"entero con signo mal ubicado", [nombre: :c, largo: 8, tipo: :entero], "0#{@centinela}1-",
     @centinela},
    {"decimal con letras", [nombre: :c, largo: 8, tipo: :decimal, precision: 2],
     "0#{@centinela}120", @centinela},
    {"decimal con separador y decimales de más",
     [nombre: :c, largo: 8, tipo: :decimal, precision: 2, separador: :punto], "1.#{@centinela}00",
     @centinela},
    {"fecha con letras", [nombre: :c, largo: 8, tipo: :fecha, formato: :aaaammdd],
     "2024#{@centinela}", @centinela},
    {"fecha inexistente", [nombre: :c, largo: 8, tipo: :fecha, formato: :aaaammdd], "20241399",
     "20241399"},
    {"rut con formato inválido", [nombre: :c, largo: 10, tipo: :rut], "1234#{@centinela}-5",
     @centinela},
    {"rut con dígito verificador malo", [nombre: :c, largo: 10, tipo: :rut], "12345678-9",
     "12345678"},
    {"rut sin dv declarado :ausente pero con dv", [nombre: :c, largo: 10, tipo: :rut, dv: :ausente],
     "12345678-5", "12345678"},
    {"texto con byte no UTF-8", [nombre: :c, largo: 8], <<"JOS", 201, "QZX7">>, "JOS"}
  ]

  defp campo_sensible(definicion),
    do: Campo.nuevo!(Keyword.merge([posicion: 1, sensible: true], definicion))

  defp representaciones(diagnostico) do
    [
      mensaje: Diagnostico.mensaje(diagnostico),
      reporte: Diagnostico.reporte([diagnostico]),
      to_string: to_string(diagnostico),
      inspect: inspect(diagnostico),
      inspect_lista: inspect([diagnostico], pretty: true)
    ]
  end

  describe "ningún mensaje de un campo sensible contiene el valor" do
    for {nombre, definicion, linea, secreto} <- @casos do
      test nombre do
        campo = campo_sensible(unquote(definicion))
        assert {:error, diagnostico} = Campo.extraer(campo, unquote(linea), %{linea: 1})
        assert diagnostico.sensible

        for {representacion, texto} <- representaciones(diagnostico) do
          refute texto =~ unquote(secreto), "#{representacion} filtra el valor: #{texto}"
        end

        # Cuando el dato está en :recibido, sigue ahí y revelar lo muestra.
        if diagnostico.recibido =~ unquote(secreto) do
          assert Diagnostico.mensaje(diagnostico, revelar: true) =~ unquote(secreto)
          assert Diagnostico.reporte([diagnostico], revelar: true) =~ unquote(secreto)
        end
      end
    end

    test "con el mismo campo sin sensible el valor sí aparece, que es el default" do
      campo = Campo.nuevo!(nombre: :c, posicion: 1, largo: 8, tipo: :entero)
      assert {:error, diagnostico} = Campo.extraer(campo, "00#{@centinela}01", %{linea: 1})

      refute diagnostico.sensible
      assert Diagnostico.mensaje(diagnostico) =~ @centinela
      assert inspect(diagnostico) =~ @centinela
    end

    test "el mensaje redactado muestra la forma, que es lo que sirve para depurar" do
      campo = campo_sensible(nombre: :rut, largo: 10, tipo: :rut)
      assert {:error, diagnostico} = Campo.extraer(campo, "1234A678-5", %{linea: 7})

      assert Diagnostico.mensaje(diagnostico) ==
               "línea 7, campo :rut (posiciones 1-10): se esperaban un RUT con dígito verificador, " <>
                 "llegaron <10 caracteres: 4 dígitos, 1 letra, 3 dígitos, \"-\", 1 dígito>; " <>
                 "se esperaban dígitos, opcionalmente con puntos y guion, y un DV del 0 al 9 o K"

      assert Diagnostico.mensaje(diagnostico, revelar: true) =~ ~s(llegaron "1234A678-5")
    end

    test "inspect redacta recibido y oculta contenido" do
      campo = campo_sensible(nombre: :nombre, largo: 8)
      assert {:error, diagnostico} = Campo.extraer(campo, <<"JOS", 201, "QZX7">>, %{linea: 1})

      texto = inspect(diagnostico)
      assert texto =~ "#AnchoFijo.Diagnostico"
      assert texto =~ ~s(contenido: "**redactado**")
      assert texto =~ "sensible: true"
      refute texto =~ "74, 79, 83"
      assert diagnostico.contenido =~ "74, 79, 83"
    end

    test "un campo en blanco sensible no inventa una forma: el mensaje sigue diciendo que está en blanco" do
      campo = campo_sensible(nombre: :c, largo: 4, tipo: :entero)
      assert {:error, diagnostico} = Campo.extraer(campo, "    ", %{linea: 1})

      assert Diagnostico.mensaje(diagnostico) =~ "llegaron un campo en blanco"
    end

    test "una línea corta en un campo sensible sigue diciendo la medida" do
      campo = campo_sensible(nombre: :c, posicion: 5, largo: 4, tipo: :entero)
      assert {:error, diagnostico} = Campo.extraer(campo, "ab", %{linea: 1})

      assert diagnostico.sensible
      assert Diagnostico.mensaje(diagnostico) =~ "llegaron 2"
    end
  end

  describe "propiedad: para cualquier valor inválido de un campo sensible" do
    property "el valor no aparece en el mensaje ni en inspect, y sí con revelar" do
      campo = campo_sensible(nombre: :c, largo: 6, tipo: :entero)

      check all(
              letras <- string(?A..?Z, min_length: 3, max_length: 3),
              digitos <- string(?0..?9, length: 3)
            ) do
        valor = digitos <> letras
        assert {:error, diagnostico} = Campo.extraer(campo, valor, %{linea: 1})

        refute Diagnostico.mensaje(diagnostico) =~ letras
        refute inspect(diagnostico) =~ letras
        assert Diagnostico.mensaje(diagnostico, revelar: true) =~ valor
      end
    end
  end

  describe "a través de parsear/3" do
    test "los diagnósticos de campos sensibles llegan marcados y el reporte los redacta" do
      layout =
        Layout.nuevo!(
          campos: [
            [nombre: :rut, largo: 10, tipo: :rut],
            [nombre: :nombre, largo: 10, sensible: true],
            [nombre: :monto, largo: 6, tipo: :entero]
          ]
        )

      {:ok, [], diagnosticos} =
        AnchoFijo.parsear(layout, "1234A678-5JUAN PEREZ00QZX7\n", modo: :tolerante)

      assert [%{campo: :rut, sensible: true}, %{campo: :monto, sensible: false}] = diagnosticos

      reporte = Diagnostico.reporte(diagnosticos)
      refute reporte =~ "1234A678"
      assert reporte =~ "QZX7"
      assert Diagnostico.reporte(diagnosticos, revelar: true) =~ "1234A678-5"
    end

    test "una entrada que no es binario se describe por tipo, no se imprime" do
      layout = Layout.nuevo!(campos: [[nombre: :rut, largo: 10, tipo: :rut]])

      assert {:error, [diagnostico]} = AnchoFijo.parsear(layout, ["12345678-5"])
      refute Diagnostico.mensaje(diagnostico) =~ "12345678"
      assert Diagnostico.mensaje(diagnostico) =~ "llegó una lista de 1 elementos"

      assert {:error, [diagnostico]} = AnchoFijo.parsear(layout, %{fila: "12345678-5"})
      refute Diagnostico.mensaje(diagnostico) =~ "12345678"
      assert Diagnostico.mensaje(diagnostico) =~ "llegó un mapa de 1 claves"
    end
  end

  describe "la opción :sensible" do
    test ":rut es sensible por default y se puede apagar" do
      assert Campo.nuevo!(nombre: :r, largo: 10, tipo: :rut).sensible
      refute Campo.nuevo!(nombre: :r, largo: 10, tipo: :rut, sensible: false).sensible
      refute Campo.nuevo!(nombre: :t, largo: 10).sensible
    end

    test "tiene que ser booleana" do
      assert {:error, [diagnostico]} = Campo.nuevo(nombre: :t, largo: 10, sensible: :si)
      assert diagnostico.esperado == ":sensible true o false"
    end
  end

  describe "forma/1" do
    test "describe puntuación literal y repetida" do
      assert Diagnostico.forma("12.345.678-K") ==
               "<12 caracteres: 2 dígitos, \".\", 3 dígitos, \".\", 3 dígitos, \"-\", 1 letra>"

      assert Diagnostico.forma("--") == "<2 caracteres: 2 × \"-\">"
      assert Diagnostico.forma("a\tb") == "<3 caracteres: 1 letra, 1 espacio, 1 letra>"
      assert Diagnostico.forma(<<1, 2>>) == "<2 caracteres: 2 caracteres de control>"
    end
  end
end
