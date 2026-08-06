defmodule AnchoFijo.Generadores do
  @moduledoc false
  # Genera layouts junto con un registro válido y su línea serializada. La
  # serialización vive acá y no en la librería a propósito: 0.1 solo lee.

  use ExUnitProperties

  @doc false
  # Devuelve %{layout: t, linea: binario, registro: mapa, campos: [spec]}.
  def layout_con_registro(opts \\ []) do
    maximo = Keyword.get(opts, :campos, 6)

    gen all(especificaciones <- list_of(campo(), min_length: 1, max_length: maximo)) do
      especificaciones =
        especificaciones
        |> Enum.with_index(1)
        |> Enum.map(fn {especificacion, indice} -> nombrar(especificacion, indice) end)

      layout =
        AnchoFijo.Layout.nuevo!(campos: Enum.map(especificaciones, & &1.definicion))

      %{
        layout: layout,
        campos: especificaciones,
        linea: Enum.map_join(especificaciones, & &1.texto),
        registro: Map.new(especificaciones, &{&1.definicion[:nombre], &1.esperado})
      }
    end
  end

  defp campo do
    one_of([texto(), entero(), decimal(), fecha()])
  end

  defp texto do
    gen all(
          largo <- integer(1..12),
          contenido <- string(:alphanumeric, max_length: largo)
        ) do
      %{
        definicion: [largo: largo],
        tipo: :texto,
        esperado: contenido,
        texto: String.pad_trailing(contenido, largo)
      }
    end
  end

  defp entero do
    gen all(
          largo <- integer(1..9),
          valor <- integer(0..(Integer.pow(10, largo) - 1))
        ) do
      %{
        definicion: [largo: largo, tipo: :entero],
        tipo: :entero,
        esperado: valor,
        texto: String.pad_leading(Integer.to_string(valor), largo, "0")
      }
    end
  end

  defp decimal do
    gen all(
          largo <- integer(1..12),
          precision <- integer(0..min(4, largo)),
          unidades <- integer(0..(Integer.pow(10, largo) - 1))
        ) do
      %{
        definicion: [largo: largo, tipo: :decimal, precision: precision],
        tipo: :decimal,
        esperado: {unidades, precision},
        texto: String.pad_leading(Integer.to_string(unidades), largo, "0")
      }
    end
  end

  defp fecha do
    gen all(
          formato <- member_of([:aaaammdd, :ddmmaaaa]),
          dias <- integer(0..36_500)
        ) do
      fecha = Date.add(~D[1950-01-01], dias)

      %{
        definicion: [largo: 8, tipo: :fecha, formato: formato],
        tipo: :fecha,
        esperado: fecha,
        texto: serializar_fecha(fecha, formato)
      }
    end
  end

  defp nombrar(especificacion, indice) do
    nombre = :"campo_#{indice}"
    %{especificacion | definicion: [{:nombre, nombre} | especificacion.definicion]}
  end

  defp serializar_fecha(fecha, :aaaammdd), do: anio(fecha) <> mes(fecha) <> dia(fecha)
  defp serializar_fecha(fecha, :ddmmaaaa), do: dia(fecha) <> mes(fecha) <> anio(fecha)

  defp anio(fecha), do: fecha.year |> Integer.to_string() |> String.pad_leading(4, "0")
  defp mes(fecha), do: fecha.month |> Integer.to_string() |> String.pad_leading(2, "0")
  defp dia(fecha), do: fecha.day |> Integer.to_string() |> String.pad_leading(2, "0")
end
