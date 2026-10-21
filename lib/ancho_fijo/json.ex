defmodule AnchoFijo.Json do
  @moduledoc false
  # JSON a mano, sin dependencia: lo que se codifica tiene una forma conocida
  # (mapas, listas, binarios, átomos, enteros, booleanos y nil) y un encoder
  # para eso son treinta líneas. Agregar Jason al paquete por dos tareas Mix
  # sería la primera dependencia de runtime de la librería. Los tests validan
  # la salida con un decoder de verdad, que sí es una dependencia de test.

  @spec codificar(term()) :: String.t()
  def codificar(valor) when is_map(valor) and not is_struct(valor) do
    valor
    |> Enum.sort()
    |> Enum.map_join(",", fn {clave, valor} ->
      codificar(clave_json(clave)) <> ":" <> codificar(valor)
    end)
    |> then(&("{" <> &1 <> "}"))
  end

  def codificar(valor) when is_list(valor),
    do: "[" <> Enum.map_join(valor, ",", &codificar/1) <> "]"

  def codificar(nil), do: "null"
  def codificar(true), do: "true"
  def codificar(false), do: "false"
  def codificar(valor) when is_atom(valor), do: codificar(Atom.to_string(valor))
  def codificar(valor) when is_integer(valor), do: Integer.to_string(valor)
  def codificar(valor) when is_binary(valor), do: "\"" <> escapar(valor) <> "\""
  def codificar(valor), do: codificar(inspect(valor))

  defp clave_json(clave) when is_binary(clave), do: clave
  defp clave_json(clave) when is_atom(clave), do: Atom.to_string(clave)
  defp clave_json(clave) when is_integer(clave), do: Integer.to_string(clave)

  defp escapar(texto) do
    texto
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
    |> String.replace("\r", "\\r")
    |> String.replace("\t", "\\t")
    |> String.replace(~r/[\x00-\x1F]/, fn <<c>> ->
      "\\u" <> String.pad_leading(Integer.to_string(c, 16), 4, "0")
    end)
  end
end
