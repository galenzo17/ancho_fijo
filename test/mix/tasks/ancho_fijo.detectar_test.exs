defmodule Mix.Tasks.AnchoFijo.DetectarTest do
  # No es async: `Mix.shell/1` es global.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO
  import AnchoFijo.Fixtures, only: [ruta: 1]

  @tarea "ancho_fijo.detectar"

  setup do
    shell = Mix.shell()
    Mix.shell(Mix.Shell.IO)
    on_exit(fn -> Mix.shell(shell) end)
    :ok
  end

  # Corre la tarea capturando stdout y stderr por separado y devuelve también
  # el código de salida: 0 si retornó, el que pasó a `exit/1` si no.
  defp correr(args) do
    padre = self()

    salida =
      capture_io(fn ->
        errores =
          capture_io(:stderr, fn ->
            codigo =
              try do
                Mix.Task.rerun(@tarea, args)
                0
              catch
                :exit, {:shutdown, codigo} -> codigo
              end

            send(padre, {:codigo, codigo})
          end)

        send(padre, {:stderr, errores})
      end)

    assert_received {:codigo, codigo}
    assert_received {:stderr, errores}
    {codigo, salida, errores}
  end

  describe "salida legible" do
    test "explica que el CSV no es de ancho fijo y sale con 1" do
      {codigo, salida, ""} = correr([ruta("nomina_en_realidad_csv.csv")])

      assert codigo == 1
      assert salida =~ "nomina_en_realidad_csv.csv: probablemente NO es de ancho fijo"
      assert salida =~ "largo predominante 28 bytes, 4 largos distintos"
      assert salida =~ "- el carácter \";\" aparece 3 veces en todas las líneas"
      assert salida =~ "parece un archivo delimitado, no de ancho fijo"
    end

    test "un archivo de ancho fijo sale con 0 y resume la muestra" do
      {codigo, salida, ""} = correr([ruta("nomina_correcta.txt")])

      assert codigo == 0
      assert salida =~ "nomina_correcta.txt: probablemente de ancho fijo\n"
      assert salida =~ "  3 líneas · largo 48 bytes, consistente · ascii · LF\n"
      assert salida =~ "  - todas las 3 líneas miden 48 bytes\n"
    end

    test "sin terminal no hay códigos ANSI" do
      {_codigo, salida, ""} = correr([ruta("nomina_correcta.txt")])

      refute salida =~ "\e["
    end

    test "--lineas y --bytes acotan la muestra" do
      {_codigo, salida, ""} = correr([ruta("nomina_correcta.txt"), "--lineas", "2"])
      assert salida =~ "2 líneas"

      {_codigo, salida, ""} = correr([ruta("nomina_correcta.txt"), "--bytes", "60"])
      assert salida =~ "(muestra parcial)"
    end
  end

  describe "--layout" do
    test "un layout que concuerda deja el código en 0" do
      {codigo, salida, ""} =
        correr([ruta("nomina_correcta.txt"), "--layout", ruta("layout_nomina.exs")])

      assert codigo == 0
      refute salida =~ "desacuerdo"
    end

    test "un multiregistro en --layout cuenta las líneas por tipo" do
      {0, salida, ""} =
        correr([ruta("nomina_sin_codigo.txt"), "--layout", ruta("multiregistro_sin_codigo.exs")])

      assert salida =~ "multiregistro con discriminador por largo de línea: de 5 líneas"
    end

    test "un layout que no concuerda se reporta y sale con 1" do
      layout = Path.join(System.tmp_dir!(), "layout_60_#{System.unique_integer([:positive])}.exs")
      File.write!(layout, "[campos: [[nombre: :todo, largo: 60]]]")
      on_exit(fn -> File.rm(layout) end)

      {codigo, salida, ""} = correr([ruta("nomina_correcta.txt"), "--layout", layout])

      assert codigo == 1
      assert salida =~ "probablemente de ancho fijo, con 1 desacuerdo con el layout"

      assert salida =~
               "- entrada: se esperaba un largo de línea de 60 bytes según el layout, llegó 48"
    end

    test "un layout inválido es un error de uso: código 2 y el diagnóstico en stderr" do
      layout = Path.join(System.tmp_dir!(), "layout_malo_#{System.unique_integer([:positive])}.exs")
      File.write!(layout, "[campos: [[nombre: :a, largo: 0]]]")
      on_exit(fn -> File.rm(layout) end)

      {codigo, "", errores} = correr([ruta("nomina_correcta.txt"), "--layout", layout])

      assert codigo == 2
      assert errores =~ "no se pudo cargar el layout"
      assert errores =~ "se esperaba un :largo entero mayor que cero, llegó 0"
    end

    test "un .exs que no existe es código 2" do
      {2, "", errores} = correr([ruta("nomina_correcta.txt"), "--layout", "/no/existe.exs"])

      assert errores =~ "no se pudo cargar el layout /no/existe.exs"
    end
  end

  describe "--json" do
    test "produce JSON parseable con el reporte completo" do
      {codigo, salida, ""} = correr([ruta("nomina_latin1.txt"), "--json"])

      assert codigo == 0
      assert {:ok, json} = Jason.decode(salida)
      assert json["archivo"] == ruta("nomina_latin1.txt")
      assert json["probablemente_ancho_fijo?"] == true
      assert json["encoding_probable"] == "latin1"
      assert json["largos"] == %{"48" => 2}

      assert json["bytes_no_utf8"] == [
               %{"byte" => 201, "linea" => 1, "posicion" => 14},
               %{"byte" => 205, "linea" => 2, "posicion" => 14}
             ]

      assert json["delimitadores"] == %{}
      assert is_list(json["observaciones"])
    end

    test "escapa comillas, barras y controles en los textos" do
      {_codigo, salida, ""} = correr([ruta("nomina_en_realidad_csv.csv"), "--json"])

      assert {:ok, json} = Jason.decode(salida)
      assert Enum.any?(json["observaciones"], &(&1 =~ ~s(el carácter ";" aparece)))
      assert json["delimitador_sugerido"] == ";"
      assert %{"constante?" => true, "por_linea" => 3} = json["delimitadores"][";"]
    end

    test "el código de salida es el mismo que sin --json" do
      assert {1, _salida, ""} = correr([ruta("nomina_en_realidad_csv.csv"), "--json"])
    end
  end

  describe "errores de uso: código 2 y el motivo en stderr" do
    test "sin ruta" do
      {2, "", errores} = correr([])

      assert errores =~ "falta la ruta del archivo"
      assert errores =~ "uso: mix ancho_fijo.detectar RUTA"
    end

    test "más de una ruta" do
      {2, "", errores} = correr(["a.txt", "b.txt"])

      assert errores =~ "se esperaba una sola ruta, sobran: b.txt"
    end

    test "opción desconocida o con valor de otro tipo" do
      {2, "", errores} = correr([ruta("nomina_correcta.txt"), "--muestra", "5"])
      assert errores =~ "opciones inválidas: --muestra"

      {2, "", errores} = correr([ruta("nomina_correcta.txt"), "--lineas", "muchas"])
      assert errores =~ "opciones inválidas: --lineas"
    end

    test "una ruta que no existe" do
      {2, "", errores} = correr(["/no/existe.txt"])

      assert errores =~ "se esperaba un archivo legible en \"/no/existe.txt\", llegó :enoent"
    end
  end

  test "aparece en mix help con su shortdoc" do
    assert Mix.Task.shortdoc(Mix.Tasks.AnchoFijo.Detectar) ==
             "Interroga un archivo de ancho fijo antes de escribir el layout"
  end
end
