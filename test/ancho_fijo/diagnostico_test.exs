defmodule AnchoFijo.DiagnosticoTest do
  use ExUnit.Case, async: true

  alias AnchoFijo.Diagnostico

  describe "mensaje/1" do
    test "el tono canónico: línea, esperado, recibido, causa" do
      mensaje =
        Diagnostico.mensaje(
          Diagnostico.nuevo(
            tipo: :largo_de_linea,
            linea: 42,
            esperado: "120 caracteres",
            recibido: "118",
            causa_probable: "posible campo faltante o archivo delimitado"
          )
        )

      assert mensaje ==
               "línea 42: se esperaban 120 caracteres, llegaron 118; " <>
                 "posible campo faltante o archivo delimitado"
    end

    test "incluye el campo y su rango de posiciones cuando los hay" do
      mensaje =
        Diagnostico.mensaje(
          Diagnostico.nuevo(tipo: :campo_invalido, linea: 3, campo: :monto, posicion: {21, 32})
        )

      assert mensaje == "línea 3, campo :monto (posiciones 21-32): formato inconsistente"
    end

    test "los diagnósticos de layout no tienen línea y hablan en singular" do
      mensaje =
        Diagnostico.mensaje(
          Diagnostico.nuevo(tipo: :layout, campo: :fecha, esperado: ":formato", recibido: nil)
        )

      assert mensaje == "layout, campo :fecha: se esperaba :formato"
    end

    test "sin causa probable no deja el punto y coma colgando" do
      mensaje = Diagnostico.mensaje(Diagnostico.nuevo(tipo: :entrada, esperado: "un archivo"))

      assert mensaje == "entrada: se esperaba un archivo"
    end

    test "un diagnóstico sin ubicación se atribuye a la entrada" do
      assert Diagnostico.mensaje(Diagnostico.nuevo(recibido: "algo raro")) ==
               "entrada: se recibió algo raro"
    end
  end

  describe "nuevo/1" do
    test "normaliza a texto cualquier valor que llegue" do
      diagnostico = Diagnostico.nuevo(esperado: 120, recibido: {:tupla, 1})

      assert diagnostico.esperado == "120"
      assert diagnostico.recibido == "{:tupla, 1}"
    end

    test "acepta un mapa igual que una keyword list" do
      assert Diagnostico.nuevo(%{tipo: :entrada, linea: 1}) ==
               Diagnostico.nuevo(tipo: :entrada, linea: 1)
    end

    test "el tipo por default es :campo_invalido" do
      assert Diagnostico.nuevo([]).tipo == :campo_invalido
    end
  end

  describe "reporte/1" do
    test "una línea por diagnóstico" do
      diagnosticos = [
        Diagnostico.nuevo(tipo: :largo_de_linea, linea: 3, esperado: "40 bytes", recibido: "38"),
        Diagnostico.nuevo(tipo: :largo_de_linea, linea: 9, esperado: "40 bytes", recibido: "41")
      ]

      assert Diagnostico.reporte(diagnosticos) ==
               "línea 3: se esperaban 40 bytes, llegaron 38\n" <>
                 "línea 9: se esperaban 40 bytes, llegaron 41"
    end

    test "una lista vacía es un reporte vacío" do
      assert Diagnostico.reporte([]) == ""
    end
  end

  describe "interpolación" do
    test "se puede interpolar directo en un string" do
      diagnostico = Diagnostico.nuevo(tipo: :entrada, esperado: "un archivo")

      assert "problema: #{diagnostico}" == "problema: entrada: se esperaba un archivo"
    end
  end

  describe "AnchoFijo.Error" do
    test "el mensaje de la excepción es el reporte completo" do
      excepcion =
        AnchoFijo.Error.exception([
          Diagnostico.nuevo(tipo: :layout, campo: :a, esperado: "un :largo"),
          Diagnostico.nuevo(tipo: :layout, campo: :b, esperado: "un :nombre")
        ])

      assert Exception.message(excepcion) ==
               "layout, campo :a: se esperaba un :largo\nlayout, campo :b: se esperaba un :nombre"
    end

    test "acepta un diagnóstico suelto" do
      excepcion = AnchoFijo.Error.exception(Diagnostico.nuevo(tipo: :entrada, esperado: "algo"))

      assert length(excepcion.diagnosticos) == 1
    end
  end
end
