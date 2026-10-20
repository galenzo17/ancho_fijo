defmodule AnchoFijo.ErrorTest do
  use ExUnit.Case, async: true

  alias AnchoFijo.Diagnostico
  alias AnchoFijo.Error
  alias AnchoFijo.Layout

  @layout [campos: [[nombre: :codigo, largo: 3, tipo: :entero]]]

  describe "la excepción" do
    test "envuelve una lista de diagnósticos y su mensaje es el reporte" do
      diagnosticos = [
        Diagnostico.nuevo(tipo: :largo_de_linea, linea: 3, esperado: "40 bytes", recibido: "38"),
        Diagnostico.nuevo(tipo: :largo_de_linea, linea: 9, esperado: "40 bytes", recibido: "41")
      ]

      error = Error.exception(diagnosticos)

      assert error.diagnosticos == diagnosticos
      assert Exception.message(error) == Diagnostico.reporte(diagnosticos)
    end

    test "acepta un diagnóstico suelto" do
      diagnostico = Diagnostico.nuevo(tipo: :entrada, esperado: "un archivo")

      assert Error.exception(diagnostico).diagnosticos == [diagnostico]
    end

    test "el mensaje se lee en la consola sin desarmar nada" do
      error =
        assert_raise Error, fn ->
          AnchoFijo.parsear!(@layout, "001\nAB2\n")
        end

      assert Exception.message(error) =~ "línea 2, campo :codigo"
      assert Exception.message(error) =~ "hay caracteres no numéricos"
    end
  end

  describe "parsear!/3" do
    test "devuelve solo los registros cuando todo se leyó" do
      assert AnchoFijo.parsear!(@layout, "001\n002\n") == [%{codigo: 1}, %{codigo: 2}]
    end

    test "en estricto levanta con el primer error" do
      error = assert_raise Error, fn -> AnchoFijo.parsear!(@layout, "001\nAB2\n003\nXYZ\n") end

      assert Enum.map(error.diagnosticos, & &1.linea) == [2]
    end

    test "en tolerante levanta con todos los errores" do
      error =
        assert_raise Error, fn ->
          AnchoFijo.parsear!(@layout, "001\nAB2\n003\nXYZ\n", modo: :tolerante)
        end

      assert Enum.map(error.diagnosticos, & &1.linea) == [2, 4]
    end

    test "las advertencias no levantan ni se devuelven" do
      layout = [
        relleno_final: :tolerar,
        campos: [[nombre: :codigo, largo: 3, tipo: :entero], [nombre: :glosa, largo: 5]]
      ]

      assert {:ok, _registros, [%Diagnostico{gravedad: :advertencia}]} =
               AnchoFijo.parsear(layout, "001AB\n")

      assert AnchoFijo.parsear!(layout, "001AB\n") == [%{codigo: 1, glosa: "AB"}]
    end

    test "en tolerante con advertencias y errores, la excepción trae solo los errores" do
      layout = [
        relleno_final: :tolerar,
        campos: [[nombre: :codigo, largo: 3, tipo: :entero], [nombre: :glosa, largo: 5]]
      ]

      error =
        assert_raise Error, fn ->
          AnchoFijo.parsear!(layout, "001AB\nXYZ\n", modo: :tolerante)
        end

      assert Enum.map(error.diagnosticos, &{&1.linea, &1.gravedad}) == [{2, :error}]
    end

    test "un layout inválido levanta la misma excepción" do
      error = assert_raise Error, fn -> AnchoFijo.parsear!([campos: []], "001\n") end

      assert [%Diagnostico{tipo: :layout}] = error.diagnosticos
    end

    test "un archivo ilegible levanta la misma excepción" do
      error =
        assert_raise Error, fn -> AnchoFijo.parsear!(@layout, "/no/existe", desde: :archivo) end

      assert [%Diagnostico{tipo: :entrada}] = error.diagnosticos
    end
  end

  describe "detectar!/2" do
    test "devuelve el reporte" do
      assert AnchoFijo.detectar!("ABC\nDEF\n").largo_predominante == 3
    end

    test "un archivo que no parece de ancho fijo no es un error" do
      assert AnchoFijo.detectar!("juan;100\nmaria;20000\n").probablemente_ancho_fijo? == false
    end

    test "una ruta ilegible levanta" do
      error = assert_raise Error, fn -> AnchoFijo.detectar!("/no/existe", desde: :archivo) end

      assert [%Diagnostico{tipo: :entrada}] = error.diagnosticos
    end

    test "un layout inválido en :layout levanta" do
      error = assert_raise Error, fn -> AnchoFijo.detectar!("ABC\n", layout: [campos: []]) end

      assert [%Diagnostico{tipo: :layout}] = error.diagnosticos
    end
  end

  describe "las otras funciones con !" do
    test "Layout.nuevo!/1 levanta AnchoFijo.Error, no otra cosa" do
      assert_raise Error, fn -> Layout.nuevo!(campos: [[nombre: :a, largo: 0]]) end
      assert_raise Error, fn -> Layout.nuevo!(42) end
    end

    test "Campo.nuevo!/1 levanta AnchoFijo.Error, no otra cosa" do
      assert_raise Error, fn -> AnchoFijo.Campo.nuevo!(nombre: :a) end
      assert_raise Error, fn -> AnchoFijo.Campo.nuevo!(:a) end
    end

    test "stream/3 levanta AnchoFijo.Error ante un layout inválido" do
      assert_raise Error, fn -> AnchoFijo.stream([campos: []], "001\n") end
    end
  end
end
