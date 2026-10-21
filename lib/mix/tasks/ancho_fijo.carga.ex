defmodule Mix.Tasks.AnchoFijo.Carga do
  @moduledoc false
  # Lo que comparten las tareas Mix: cargar un layout desde un `.exs` y
  # abortar con código 2. Evaluar un archivo es cosa de la terminal, no de la
  # librería, por eso vive acá y no en `AnchoFijo`.

  alias AnchoFijo.Diagnostico

  @doc false
  @spec cargar_layout(String.t()) ::
          {:ok, AnchoFijo.Layout.t() | AnchoFijo.Multiregistro.t()} | {:error, String.t()}
  def cargar_layout(ruta) do
    if String.ends_with?(ruta, ".json"), do: cargar_json(ruta), else: cargar_exs(ruta)
  end

  # Un .json es datos: un multiregistro si trae "registros", un layout si no.
  defp cargar_json(ruta) do
    with {:ok, contenido} <- File.read(ruta),
         {:ok, mapa} <- AnchoFijo.Json.decodificar(contenido),
         {:ok, layout} <- desde_mapa(mapa) do
      {:ok, layout}
    else
      {:error, motivo} when is_atom(motivo) -> {:error, "#{:file.format_error(motivo)}"}
      {:error, motivo} when is_binary(motivo) -> {:error, motivo}
      {:error, diagnosticos} -> {:error, "\n" <> Diagnostico.reporte(diagnosticos)}
    end
  end

  defp desde_mapa(%{"registros" => _} = mapa), do: AnchoFijo.Multiregistro.desde_mapa(mapa)
  defp desde_mapa(mapa) when is_map(mapa), do: AnchoFijo.Layout.desde_mapa(mapa)
  defp desde_mapa(_otro), do: {:error, "el JSON no es un objeto con la definición"}

  defp cargar_exs(ruta) do
    {definicion, _binding} = Code.eval_file(ruta)

    case definicion do
      %AnchoFijo.Multiregistro{} = multi ->
        {:ok, multi}

      definicion ->
        case AnchoFijo.Layout.coercer(definicion) do
          {:ok, layout} -> {:ok, layout}
          {:error, diagnosticos} -> {:error, "\n" <> Diagnostico.reporte(diagnosticos)}
        end
    end
  rescue
    error in [Code.LoadError, File.Error] -> {:error, Exception.message(error)}
    error -> {:error, "el archivo no evalúa: " <> Exception.message(error)}
  end

  # `exit({:shutdown, n})` es la forma en que una tarea Mix fija el código de
  # salida del proceso sin matar la VM, lo que la deja testeable con
  # `catch_exit/1`.
  @doc false
  @spec abortar(String.t()) :: no_return()
  def abortar(mensaje) do
    Mix.shell().error(mensaje)
    exit({:shutdown, 2})
  end
end
