defmodule Mix.Tasks.AnchoFijo.ValidarTest do
  # No es async: `Mix.shell/1` es global.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO
  import AnchoFijo.Fixtures, only: [ruta: 1]

  @tarea "ancho_fijo.validar"

  setup do
    shell = Mix.shell()
    Mix.shell(Mix.Shell.IO)
    on_exit(fn -> Mix.shell(shell) end)
    :ok
  end

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

  # Un layout con un RUT de verdad (sensible por default) y un archivo con
  # tres filas malas entre cinco, en archivos temporales.
  defp temporal(nombre, contenido) do
    ruta = Path.join(System.tmp_dir!(), "#{nombre}_#{System.unique_integer([:positive])}")
    File.write!(ruta, contenido)
    on_exit(fn -> File.rm(ruta) end)
    ruta
  end

  defp layout_con_rut do
    temporal(
      "layout_validar.exs",
      "[campos: [[nombre: :rut, largo: 10, tipo: :rut], [nombre: :nombre, largo: 20], " <>
        "[nombre: :monto, largo: 10, tipo: :decimal, precision: 2], " <>
        "[nombre: :fecha, largo: 8, tipo: :fecha, formato: :aaaammdd]]]"
    )
  end

  @buena "12345678-5JUAN PEREZ          000012500020240115\n"
  @dv_malo "12345678-9JUAN PEREZ          000012500020240115\n"
  @monto_malo "98765432-5ANA SOTO            0000ABC00020240115\n"
  @corta "11111111-1PEDRO GONZALEZ      00000000452024011\n"

  describe "salida legible" do
    test "un archivo correcto termina con 0 y se acepta" do
      {codigo, salida, ""} =
        correr([ruta("nomina_correcta.txt"), "--layout", ruta("layout_nomina.exs")])

      assert codigo == 0
      assert salida =~ "nomina_correcta.txt: sin observaciones: el archivo se acepta\n"
      assert salida =~ "  3 registros leídos, 3 líneas\n"
    end

    test "tres filas malas: código 1, el resumen las cuenta y se ven las tres" do
      archivo = temporal("nomina.txt", @buena <> @dv_malo <> @monto_malo <> @buena <> @corta)
      {codigo, salida, ""} = correr([archivo, "--layout", layout_con_rut()])

      assert codigo == 1
      assert salida =~ ": 3 errores en 3 líneas: el archivo se rechaza\n"
      assert salida =~ "  2 registros leídos, 5 líneas\n"
      assert salida =~ "línea 2, campo :rut"
      assert salida =~ "línea 3, campo :monto"
      assert salida =~ "línea 5: se esperaban 48 bytes, llegaron 47"

      # El RUT con el DV malo viaja redactado, salvo con --revelar.
      refute salida =~ "12345678-9"
      assert salida =~ ~s(<10 caracteres: 8 dígitos, "-", 1 dígito>)

      {1, revelada, ""} = correr([archivo, "--layout", layout_con_rut(), "--revelar"])
      assert revelada =~ "12345678-9"
    end

    test "--modo estricto corta en la primera línea mala" do
      archivo = temporal("nomina.txt", @buena <> @dv_malo <> @monto_malo)
      {1, salida, ""} = correr([archivo, "--layout", layout_con_rut(), "--modo", "estricto"])

      assert salida =~ ": 1 error en 1 línea: el archivo se rechaza\n"
      assert salida =~ "  1 registros leídos, 2 líneas\n"
      refute salida =~ "línea 3"
    end

    test "--lineas N limita lo que se imprime, no lo que se cuenta" do
      archivo = temporal("nomina.txt", @dv_malo <> @monto_malo <> @corta)
      {1, salida, ""} = correr([archivo, "--layout", layout_con_rut(), "--lineas", "1"])

      assert salida =~ "3 errores en 3 líneas"
      assert salida =~ "línea 1, campo :rut"
      refute salida =~ "línea 2"
      assert salida =~ "… y 2 más (--lineas N para ver más)"
    end

    test "--idioma en y --usuario cambian el marco y la audiencia del mensaje" do
      archivo = temporal("nomina.txt", @monto_malo)

      {1, salida, ""} =
        correr([archivo, "--layout", layout_con_rut(), "--idioma", "en", "--usuario"])

      assert salida =~ "1 error in 1 line: the file is rejected"
      assert salida =~ "Line 1, field monto: the value is not valid"
      refute salida =~ "campo corrido"
    end

    test "las advertencias se aceptan con observaciones y salen con 0" do
      layout =
        temporal(
          "layout_tolerar.exs",
          "[relleno_final: :tolerar, campos: [[nombre: :a, largo: 4], [nombre: :g, largo: 4]]]"
        )

      archivo = temporal("corta.txt", "abcd\n")
      {0, salida, ""} = correr([archivo, "--layout", layout])

      assert salida =~ "1 advertencia: el archivo se acepta con observaciones"
      assert salida =~ "relleno"
    end

    test "con un multiregistro, los diagnósticos de cierre también cuentan" do
      layout =
        temporal(
          "multi.exs",
          "AnchoFijo.Multiregistro.nuevo!(discriminador: [largo: 1], registros: [" <>
            "h: [valor: \"H\", cantidad: :uno, layout: [campos: [[nombre: :t, largo: 1]]]], " <>
            "d: [valor: \"D\", cantidad: :varios, layout: [campos: [[nombre: :t, largo: 1], [nombre: :x, largo: 2]]]]])"
        )

      {0, salida, ""} = correr([temporal("ok.txt", "H\nDab\n"), "--layout", layout])
      assert salida =~ "2 registros leídos, 2 líneas"

      {1, salida, ""} = correr([temporal("sin_header.txt", "Dab\n"), "--layout", layout])
      assert salida =~ "el archivo se rechaza"
    end
  end

  describe "--json" do
    test "es JSON válido con las claves de a_mapa/2 y el resumen" do
      archivo = temporal("nomina.txt", @buena <> @dv_malo)
      {1, salida, ""} = correr([archivo, "--layout", layout_con_rut(), "--json"])

      assert {:ok, json} = Jason.decode(salida)
      assert json["archivo"] == archivo
      assert json["registros"] == 1
      assert json["lineas"] == 2
      assert json["resumen"]["veredicto"] == "rechazable"
      assert json["resumen"]["errores"] == 1
      assert [d] = json["diagnosticos"]
      assert d["tipo"] == "campo_invalido"
      assert d["campo"] == "rut"
      assert d["linea"] == 2
      assert d["posicion"] == [1, 10]
      assert d["sensible"] == true
      refute d["recibido"] =~ "12345678-9"
      assert is_binary(d["mensaje"])
    end
  end

  describe "errores de uso: código 2 y el motivo en stderr" do
    test "sin --layout, sin ruta, con sobrantes o con opciones inválidas" do
      {2, "", errores} = correr([ruta("nomina_correcta.txt")])
      assert errores =~ "falta --layout"

      {2, "", errores} = correr(["--layout", ruta("layout_nomina.exs")])
      assert errores =~ "falta la ruta del archivo"

      {2, "", errores} =
        correr([ruta("nomina_correcta.txt"), "otra", "--layout", ruta("layout_nomina.exs")])

      assert errores =~ "sobran: otra"

      {2, "", errores} =
        correr([
          ruta("nomina_correcta.txt"),
          "--layout",
          ruta("layout_nomina.exs"),
          "--modo",
          "rapido"
        ])

      assert errores =~ "--modo tiene que ser estricto o tolerante"

      {2, "", errores} =
        correr([ruta("nomina_correcta.txt"), "--layout", ruta("layout_nomina.exs"), "--zzz"])

      assert errores =~ "opciones inválidas: --zzz"
    end

    test "una ruta que no existe o un layout inválido" do
      {2, "", errores} = correr(["/no/existe.txt", "--layout", ruta("layout_nomina.exs")])
      assert errores =~ "la ruta no existe"

      layout = temporal("malo.exs", "[campos: [[nombre: :a, largo: 0]]]")
      {2, "", errores} = correr([ruta("nomina_correcta.txt"), "--layout", layout])
      assert errores =~ "no se pudo cargar el layout"
    end
  end
end
