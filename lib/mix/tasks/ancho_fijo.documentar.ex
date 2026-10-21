defmodule Mix.Tasks.AnchoFijo.Documentar do
  @shortdoc "Genera la especificación de un layout desde su definición"

  @moduledoc """
  Imprime la especificación de un layout o un multiregistro, para pegarla
  en el documento que se le manda al cliente o al banco, en una wiki o en
  el README. Es `AnchoFijo.Documentacion.documentar/2` desde la terminal.

      $ mix ancho_fijo.documentar layout_nomina.exs
      ## nómina de fixtures

      48 posiciones · UTF-8 · medido en bytes

      | Campo | Posiciones | Largo | Tipo | Formato | Opcional | Descripción | Ejemplo |
      | --- | --- | --- | --- | --- | --- | --- | --- |
      ...

  El archivo `.exs` se evalúa y tiene que devolver un `AnchoFijo.Layout`, su
  definición (keyword list o mapa) o un `AnchoFijo.Multiregistro`, igual
  que `--layout` en `mix ancho_fijo.detectar`.

  ## Opciones

    * `--formato markdown|csv|json` — default `markdown`.
    * `--idioma es|en` — default `es`. Traduce los encabezados y los nombres
      de tipo; los nombres de los campos son del formato y no se tocan.

  ## Códigos de salida

    * `0` — se imprimió la especificación.
    * `2` — la ruta no existe, el layout es inválido o las opciones están
      mal. El motivo va a stderr.
  """

  use Mix.Task

  alias AnchoFijo.Documentacion
  alias Mix.Tasks.AnchoFijo.Carga

  @opciones [formato: :string, idioma: :string]

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("loadpaths", [])
    {opts, ruta} = interpretar!(args)

    layout =
      case Carga.cargar_layout(ruta) do
        {:ok, layout} -> layout
        {:error, motivo} -> Carga.abortar("no se pudo cargar el layout #{ruta}: #{motivo}")
      end

    Mix.shell().info(Documentacion.documentar(layout, opts))
  end

  defp interpretar!(args) do
    case OptionParser.parse(args, strict: @opciones) do
      {opts, [ruta], []} ->
        {opciones(opts), ruta}

      {_opts, [], []} ->
        Carga.abortar("falta la ruta del layout\n\n" <> uso())

      {_opts, [_ | sobran], []} ->
        Carga.abortar("sobran argumentos: #{Enum.join(sobran, " ")}\n\n" <> uso())

      {_opts, _args, invalidas} ->
        Carga.abortar(
          "opciones inválidas: #{Enum.map_join(invalidas, ", ", &elem(&1, 0))}\n\n" <>
            uso()
        )
    end
  end

  defp opciones(opts) do
    Enum.map(opts, fn
      {:formato, valor} -> {:formato, atomo(valor, ["markdown", "csv", "json"], "--formato")}
      {:idioma, valor} -> {:idioma, atomo(valor, ["es", "en"], "--idioma")}
    end)
  end

  defp atomo(valor, validos, flag) do
    if valor in validos,
      do: String.to_atom(valor),
      else: Carga.abortar("#{flag} espera #{Enum.join(validos, ", ")}; llegó #{valor}\n\n" <> uso())
  end

  defp uso do
    "uso: mix ancho_fijo.documentar RUTA.exs [--formato markdown|csv|json] [--idioma es|en]"
  end
end
