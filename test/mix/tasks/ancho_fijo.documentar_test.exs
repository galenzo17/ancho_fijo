defmodule Mix.Tasks.AnchoFijo.DocumentarTest do
  # No es async: `Mix.shell/1` es global.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO
  import AnchoFijo.Fixtures, only: [ruta: 1]

  @tarea "ancho_fijo.documentar"

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

        send(padre, {:errores, errores})
      end)

    codigo = receive do: ({:codigo, c} -> c)
    errores = receive do: ({:errores, e} -> e)
    {codigo, salida, errores}
  end

  test "imprime la especificación del layout en markdown" do
    {0, salida, ""} = correr([ruta("layout_nomina.exs")])

    assert salida =~
             "| Campo | Posiciones | Largo | Tipo | Formato | Opcional | Descripción | Ejemplo |"

    assert salida =~ "| `rut` | 1-10 | 10 |"
  end

  test "un multiregistro, en csv y en inglés" do
    {0, salida, ""} =
      correr([ruta("multiregistro_sin_codigo.exs"), "--formato", "csv", "--idioma", "en"])

    assert salida =~ "Record;Field;Positions;Length;Type;Format;Optional;Description;Example\n"

    assert salida =~
             "detalle;monto;27-36;10;decimal;2 implicit decimals;no;Monto a pagar;0000125000\n"
  end

  test "json decodificable" do
    {0, salida, ""} = correr([ruta("layout_nomina.exs"), "--formato", "json"])
    assert {:ok, %{"campos" => campos}} = Jason.decode(salida)
    assert length(campos) == 4
  end

  test "errores de uso: sin ruta, formato desconocido, layout inválido" do
    {2, "", errores} = correr([])
    assert errores =~ "falta la ruta del layout"

    {2, "", errores} = correr([ruta("layout_nomina.exs"), "--formato", "pdf"])
    assert errores =~ "--formato espera markdown, csv, json; llegó pdf"

    {2, "", errores} = correr(["/no/existe.exs"])
    assert errores =~ "no se pudo cargar el layout"
  end
end
