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

  describe "para el usuario final" do
    @sensible Diagnostico.nuevo(
                campo: :rut,
                linea: 4,
                esperado: "un RUT",
                recibido: ~s("1234A678-5")
              )
              |> Diagnostico.marcar_sensible("1234A678-5")

    test "mensaje/2 en los dos idiomas y las dos audiencias" do
      d =
        Diagnostico.nuevo(
          tipo: :largo_de_linea,
          linea: 42,
          esperado: "120 bytes",
          recibido: "118",
          causa_probable: "posible campo faltante"
        )

      assert Diagnostico.mensaje(d) ==
               "línea 42: se esperaban 120 bytes, llegaron 118; posible campo faltante"

      assert Diagnostico.mensaje(d, idioma: :en) ==
               "line 42: expected 120 bytes, got 118; posible campo faltante"

      assert Diagnostico.mensaje(d, audiencia: :usuario) ==
               "Línea 42: la línea no tiene el largo esperado (se esperaba 120 bytes, llegó 118)."

      assert Diagnostico.mensaje(d, audiencia: :usuario, idioma: :en) ==
               "Line 42: the line does not have the expected length (expected 120 bytes, got 118)."

      sin_ubicacion =
        Diagnostico.nuevo(
          tipo: :estructura,
          esperado: "un registro :trailer en el archivo",
          recibido: "el fin del archivo"
        )

      assert Diagnostico.mensaje(sin_ubicacion, idioma: :en) ==
               "structure: expected un registro :trailer en el archivo, got el fin del archivo"

      assert Diagnostico.mensaje(sin_ubicacion, audiencia: :usuario) ==
               "La estructura del archivo no es la esperada (se esperaba un registro :trailer en el archivo, llegó el fin del archivo)."

      solo_campo = Diagnostico.nuevo(tipo: :layout, campo: :monto, esperado: ":precision declarada")

      assert Diagnostico.mensaje(solo_campo, audiencia: :usuario, idioma: :en) ==
               "Field monto: the format definition is invalid (expected :precision declarada)."
    end

    test "un campo sensible sigue redactado para el usuario y en el mapa" do
      assert Diagnostico.mensaje(@sensible, audiencia: :usuario) =~ "<10 caracteres"
      refute Diagnostico.mensaje(@sensible, audiencia: :usuario, idioma: :en) =~ "1234A678"
      assert Diagnostico.mensaje(@sensible, audiencia: :usuario, revelar: true) =~ "1234A678-5"

      mapa = Diagnostico.a_mapa(@sensible)
      assert mapa.recibido =~ "<10 caracteres"
      assert mapa.contenido == nil
      assert mapa.sensible
      refute mapa.mensaje =~ "1234A678"
      assert Diagnostico.a_mapa(@sensible, revelar: true).recibido == ~s("1234A678-5")
    end

    test "a_mapa/2 y desde_mapa/1 son inversos, salvo el valor sensible" do
      d =
        Diagnostico.nuevo(
          tipo: :campo_invalido,
          linea: 2,
          campo: :monto,
          posicion: {11, 22},
          esperado: "x",
          recibido: "y",
          causa_probable: "z",
          contenido: "c"
        )

      assert Diagnostico.desde_mapa(Diagnostico.a_mapa(d)) == d

      vuelto = Diagnostico.desde_mapa(Diagnostico.a_mapa(@sensible))
      assert vuelto.sensible
      assert vuelto.recibido =~ "<10 caracteres"
      assert Diagnostico.mensaje(vuelto) == Diagnostico.mensaje(@sensible)

      desde_json =
        Diagnostico.desde_mapa(%{
          "tipo" => "estructura",
          "gravedad" => "error",
          "linea" => 1,
          "campo" => "campo_que_no_existe_como_atomo_xyz",
          "posicion" => nil
        })

      assert desde_json.tipo == :estructura
      assert desde_json.campo == "campo_que_no_existe_como_atomo_xyz"
    end

    test "con Jason, un diagnóstico se codifica como su mapa, redactado" do
      json = Jason.encode!(@sensible)
      assert {:ok, decodificado} = Jason.decode(json)
      assert decodificado["tipo"] == "campo_invalido"
      assert decodificado["recibido"] =~ "<10 caracteres"
      refute json =~ "1234A678"

      vuelto = Diagnostico.desde_mapa(decodificado)
      assert vuelto.campo == :rut
      assert Diagnostico.mensaje(vuelto) == Diagnostico.mensaje(@sensible)

      assert Jason.encode!([@sensible]) |> Jason.decode!() |> length() == 1
    end

    test "resumen/2 totaliza, lista las líneas y da el veredicto" do
      diagnosticos = [
        Diagnostico.nuevo(tipo: :campo_invalido, linea: 2, campo: :monto),
        Diagnostico.nuevo(tipo: :campo_invalido, linea: 2, campo: :fecha),
        Diagnostico.nuevo(tipo: :largo_de_linea, linea: 7),
        Diagnostico.nuevo(tipo: :relleno_completado, gravedad: :advertencia, linea: 9),
        Diagnostico.nuevo(tipo: :estructura)
      ]

      resumen = Diagnostico.resumen(diagnosticos, lineas: 2)
      assert resumen.total == 5
      assert resumen.errores == 4
      assert resumen.advertencias == 1

      assert resumen.por_tipo == %{
               campo_invalido: 2,
               largo_de_linea: 1,
               relleno_completado: 1,
               estructura: 1
             }

      assert resumen.por_campo == %{monto: 1, fecha: 1}
      assert resumen.lineas_afectadas == [2, 7]
      assert resumen.lineas_con_error == 2
      assert resumen.veredicto == :rechazable
      assert resumen.texto == "4 errores en 2 líneas y 1 advertencia: el archivo se rechaza"

      solo_advertencias = Diagnostico.resumen([Enum.at(diagnosticos, 3)])
      assert solo_advertencias.veredicto == :aceptable_con_observaciones
      assert solo_advertencias.texto == "1 advertencia: el archivo se acepta con observaciones"

      assert Diagnostico.resumen([Enum.at(diagnosticos, 3)], idioma: :en).texto ==
               "1 warning: the file is accepted with observations"

      assert AnchoFijo.resumen([]).veredicto == :aceptable
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
