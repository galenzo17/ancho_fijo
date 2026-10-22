defmodule AnchoFijo.ReadmeEnTest do
  # La guía en inglés y el README en español se separan sin que nadie se
  # entere: el glosario tiene que ser el mismo en los dos, y la tabla
  # generada en inglés tiene que ser la que imprime documentar/2.
  use ExUnit.Case, async: true

  import AnchoFijo.Fixtures, only: [ruta: 1]

  @es File.read!("README.md")
  @en File.read!("README.en.md")

  defp glosario(readme) do
    [_, tabla] = Regex.run(~r/(\| Español \| English \|\n\| --- \| --- \|\n(?:\|.*\|\n)+)/, readme)
    tabla |> String.split("\n", trim: true) |> Enum.drop(2)
  end

  test "el glosario es el mismo en los dos README" do
    assert glosario(@es) == glosario(@en)
    assert length(glosario(@es)) > 40
  end

  test "la tabla en inglés del README.en.md es la que genera documentar/2, sin edición manual" do
    multi = elem(Code.eval_file(ruta("multiregistro_sin_codigo.exs")), 0)
    assert String.contains?(@en, AnchoFijo.Documentacion.documentar(multi, idioma: :en))
  end

  test "la guía en inglés cubre lo mismo que la española: cada sección principal tiene su par" do
    secciones = fn readme ->
      ~r/^## .+$/m |> Regex.scan(readme) |> length()
    end

    # Las mismas secciones de nivel 2, más el glosario en los dos.
    assert secciones.(@en) == secciones.(@es)

    for nombre <- ~w(detectar/2 parsear/3 escribir/3 stream/3 Multiregistro Tipo huella identidad
                     Test.Generadores a_mapa/1 documentar) do
      assert @en =~ nombre, "README.en.md no menciona #{nombre}"
    end
  end
end
