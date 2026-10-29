defmodule Mix.Tasks.AnchoFijo.Validar do
  @shortdoc "Valida un archivo contra un layout y dice qué tiene"

  @moduledoc """
  Corre `AnchoFijo.parsear/3` sobre un archivo real, desde la terminal, y
  reporta los diagnósticos como los vería quien tiene que corregirlo.

      $ mix ancho_fijo.validar nomina.txt --layout nomina.exs
      nomina.txt: 3 errores en 3 líneas: el archivo se rechaza
        2 registros leídos, 5 líneas
        línea 2, campo :monto (posiciones 31-40): se esperaban 10 posiciones con un número...
        línea 4, campo :fecha (posiciones 41-48): se esperaba una fecha válida en formato...
        línea 5: se esperaban 48 bytes, llegaron 47; posible campo faltante o archivo delimitado

  Es el tercer comando del día a día: `detectar` responde "¿es de ancho fijo
  y concuerda con el layout?" sin parsear, `documentar` imprime la
  especificación, y este responde "¿este archivo pasa, y qué tiene?", que es
  lo que pregunta el operador que recibió el archivo rechazado y el script de
  validación previa del pipeline.

  ## Opciones

    * `--layout RUTA.exs|RUTA.json` — obligatorio. Un `AnchoFijo.Layout`,
      un `AnchoFijo.Multiregistro` o su definición.
    * `--modo estricto|tolerante` — default `tolerante`: el operador quiere
      la lista completa. Con `estricto` se corta en la primera línea mala.
    * `--lineas N` — cuántos diagnósticos imprimir. Default 50; el resumen
      cuenta todos igual.
    * `--json` — `{archivo, registros, lineas, resumen, diagnosticos}` en una
      línea, con cada diagnóstico como `AnchoFijo.Diagnostico.a_mapa/2`.
    * `--idioma es|en` y `--usuario` — como `AnchoFijo.Diagnostico.mensaje/2`:
      el idioma del marco del mensaje, y la audiencia `:usuario` (sin la
      causa probable ni las opciones del layout).
    * `--revelar` — muestra los valores de los campos sensibles. Por default
      se redactan, como en todas partes.

  El archivo se lee con `stream/3`: no se carga entero, solo se acumulan los
  diagnósticos y las cuentas.

  ## Códigos de salida

    * `0` — el archivo se acepta (sin diagnósticos, o solo advertencias).
    * `1` — el archivo se rechaza: hay al menos un error. El reporte se
      imprimió igual.
    * `2` — no se pudo responder: la ruta no existe o no se puede leer, el
      layout es inválido, o las opciones están mal. El motivo va a stderr.

  ## Colores

  Los colores se emiten solo si la salida es una terminal.
  """

  use Mix.Task

  alias AnchoFijo.Diagnostico
  alias AnchoFijo.Json
  alias Mix.Tasks.AnchoFijo.Carga

  @opciones [
    layout: :string,
    modo: :string,
    lineas: :integer,
    json: :boolean,
    idioma: :string,
    usuario: :boolean,
    revelar: :boolean
  ]

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("loadpaths", [])

    {opts, ruta} = interpretar!(args)
    layout = cargar!(Keyword.get(opts, :layout))
    {registros, lineas, diagnosticos} = recorrer(layout, ruta, Keyword.get(opts, :modo, :tolerante))
    resumen = Diagnostico.resumen(diagnosticos, idioma: Keyword.get(opts, :idioma, :es))

    imprimir(ruta, registros, lineas, resumen, diagnosticos, opts)
    salir(if(resumen.veredicto == :rechazable, do: 1, else: 0))
  end

  defp interpretar!(args) do
    case OptionParser.parse(args, strict: @opciones) do
      {opts, [ruta], []} ->
        if Keyword.has_key?(opts, :layout),
          do: {Enum.map(opts, &normalizar/1), ruta},
          else: abortar("falta --layout\n\n" <> uso())

      {_opts, [], []} ->
        abortar("falta la ruta del archivo\n\n" <> uso())

      {_opts, [_ruta | sobrantes], []} ->
        abortar("se esperaba una sola ruta, sobran: #{Enum.join(sobrantes, " ")}\n\n" <> uso())

      {_opts, _args, invalidas} ->
        detalle = Enum.map_join(invalidas, ", ", fn {flag, _valor} -> flag end)
        abortar("opciones inválidas: #{detalle}\n\n" <> uso())
    end
  end

  defp normalizar({:modo, valor}), do: {:modo, atomo(valor, ["estricto", "tolerante"], "--modo")}
  defp normalizar({:idioma, valor}), do: {:idioma, atomo(valor, ["es", "en"], "--idioma")}
  defp normalizar(opcion), do: opcion

  defp atomo(valor, validos, flag) do
    if valor in validos,
      do: String.to_atom(valor),
      else:
        abortar("#{flag} tiene que ser #{Enum.join(validos, " o ")}, llegó #{valor}\n\n" <> uso())
  end

  defp uso do
    "uso: mix ancho_fijo.validar RUTA --layout RUTA.exs|RUTA.json [--modo estricto|tolerante] " <>
      "[--lineas N] [--json] [--idioma es|en] [--usuario] [--revelar]"
  end

  defp cargar!(ruta) do
    case Carga.cargar_layout(ruta) do
      {:ok, layout} -> layout
      {:error, motivo} -> abortar("no se pudo cargar el layout #{ruta}: #{motivo}")
    end
  end

  # El archivo se recorre con `stream/3` y se acumulan solo las cuentas y los
  # diagnósticos. Un error de entrada antes de la primera línea (la ruta no
  # existe, no se puede leer) es un 2, no un veredicto. En estricto se corta
  # en la primera línea con error, como `parsear/3`.
  defp recorrer(layout, ruta, modo) do
    layout
    |> AnchoFijo.stream(ruta, desde: :archivo)
    |> Enum.reduce_while({0, 0, []}, fn
      {:ok, _registro, advertencias}, {registros, lineas, acumulados} ->
        {:cont, {registros + 1, lineas + 1, Enum.reverse(advertencias, acumulados)}}

      {:error, [%Diagnostico{tipo: :entrada, linea: nil} | _] = diagnosticos}, {0, 0, []} ->
        abortar(Diagnostico.reporte(diagnosticos))

      {:error, diagnosticos}, {registros, lineas, acumulados} ->
        lineas = if Enum.any?(diagnosticos, &(not is_nil(&1.linea))), do: lineas + 1, else: lineas
        acumulados = Enum.reverse(diagnosticos, acumulados)

        if modo == :estricto and Enum.any?(diagnosticos, &(&1.gravedad == :error)),
          do: {:halt, {registros, lineas, acumulados}},
          else: {:cont, {registros, lineas, acumulados}}
    end)
    |> then(fn {registros, lineas, acumulados} -> {registros, lineas, Enum.reverse(acumulados)} end)
  end

  defp imprimir(ruta, registros, lineas, resumen, diagnosticos, opts) do
    opciones_de_mensaje = opciones_de_mensaje(opts)

    if Keyword.get(opts, :json, false) do
      Mix.shell().info(
        Json.codificar(%{
          archivo: ruta,
          registros: registros,
          lineas: lineas,
          resumen: resumen,
          diagnosticos: Enum.map(diagnosticos, &Diagnostico.a_mapa(&1, opciones_de_mensaje))
        })
      )
    else
      maximo = Keyword.get(opts, :lineas, 50)
      Mix.shell().info(encabezado(ruta, resumen))
      Mix.shell().info("  #{registros} registros leídos, #{lineas} líneas")

      diagnosticos
      |> Enum.take(maximo)
      |> Enum.each(&Mix.shell().info("  " <> Diagnostico.mensaje(&1, opciones_de_mensaje)))

      if length(diagnosticos) > maximo,
        do: Mix.shell().info("  … y #{length(diagnosticos) - maximo} más (--lineas N para ver más)")
    end
  end

  defp opciones_de_mensaje(opts) do
    [
      idioma: Keyword.get(opts, :idioma, :es),
      revelar: Keyword.get(opts, :revelar, false),
      audiencia: if(Keyword.get(opts, :usuario, false), do: :usuario, else: :desarrollador)
    ]
  end

  defp encabezado(ruta, %{veredicto: veredicto, texto: texto}) do
    color =
      case veredicto do
        :aceptable -> :green
        :aceptable_con_observaciones -> :yellow
        :rechazable -> :red
      end

    IO.ANSI.format([color, "#{ruta}: #{texto}"])
  end

  @spec abortar(String.t()) :: no_return()
  defp abortar(mensaje), do: Carga.abortar(mensaje)

  defp salir(0), do: :ok
  defp salir(codigo), do: exit({:shutdown, codigo})
end
