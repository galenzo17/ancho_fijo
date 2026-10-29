defmodule AnchoFijo.SeguridadTest do
  # SECURITY.md promete qué series tienen soporte. La tabla se olvidó al
  # publicar la 0.4.0; este test la ata a `@version` para que falle en el PR
  # de versión y no después del tag (release.yml hace el mismo chequeo).
  use ExUnit.Case, async: true

  test "la tabla de versiones con soporte nombra la serie de @version con correcciones y seguridad" do
    version = Mix.Project.config()[:version]
    [mayor, menor, _parche] = String.split(version, ".")
    serie = "#{mayor}.#{menor}.x"

    filas =
      "SECURITY.md"
      |> File.read!()
      |> String.split("\n")
      |> Enum.filter(&String.starts_with?(&1, "| "))

    fila = Enum.find(filas, &String.starts_with?(&1, "| #{serie}"))
    assert fila, "SECURITY.md no tiene una fila para la serie #{serie}"
    assert fila =~ "Correcciones y seguridad"
  end

  test "la serie anterior queda solo con seguridad y una fecha, y las más viejas sin soporte" do
    contenido = File.read!("SECURITY.md")
    assert contenido =~ ~r/\| 0\.3\.x +\| Solo seguridad, hasta el \d{4}-\d{2}-\d{2}/
    assert contenido =~ ~r/\| < 0\.3 +\| Sin soporte/
  end
end
