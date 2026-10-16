defmodule Mix.Tasks.AnchoFijo.Detectar do
  @shortdoc "Interroga un archivo de ancho fijo antes de escribir el layout"

  @moduledoc """
  Corre `AnchoFijo.detectar/2` sobre un archivo, desde la terminal.

      $ mix ancho_fijo.detectar nomina.txt
      nomina.txt: probablemente de ancho fijo
        3 líneas · largo 48 bytes, consistente · ascii · LF
        - todas las 3 líneas miden 48 bytes
        - todos los bytes son ASCII: latin-1 y UTF-8 dan el mismo resultado en este archivo
        - las líneas terminan en LF (\\n), estilo Unix

  Es `detectar/2` para el día uno de la integración, cuando el archivo llegó por
  correo y todavía no hay proyecto, layout ni `iex` abierto: la pregunta "¿esto
  es realmente lo que me dijeron que es?" en un comando.

  ## Opciones

    * `--lineas N` — máximo de líneas a analizar. Default 200.
    * `--bytes N` — máximo de bytes a leer del archivo. Default 64.000.
    * `--layout RUTA.exs` — contrasta el archivo con un layout. El archivo
      `.exs` se evalúa y tiene que devolver un `AnchoFijo.Layout` o su
      definición (keyword list o mapa). Los desacuerdos salen como diagnósticos
      y afectan el código de salida.
    * `--json` — imprime el reporte como JSON en una línea, para procesarlo
      con `jq` o desde otro programa. Sin colores ni resumen.

  Las opciones se llaman igual que las de `AnchoFijo.detectar/2` a propósito:
  lo que se aprende en una terminal sirve en el código.

  ## Códigos de salida

  Para usar la tarea como validación previa en un script, el código de salida
  sigue la convención de `grep` y `diff`:

    * `0` — el archivo parece de ancho fijo y, si se dio un layout, concuerda.
    * `1` — el archivo no parece de ancho fijo, o no concuerda con el layout.
      El reporte se imprimió igual: el `1` es el veredicto, no una falla.
    * `2` — no se pudo responder: la ruta no existe o no se puede leer, el
      layout es inválido, o las opciones están mal. El motivo va a stderr.

  ## Colores

  Los colores se emiten solo si la salida es una terminal. Redirigida a un
  archivo o a un pipe, la salida es texto plano.
  """

  use Mix.Task

  alias AnchoFijo.Diagnostico

  @opciones [lineas: :integer, bytes: :integer, layout: :string, json: :boolean]

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("loadpaths", [])

    {opts, ruta} = interpretar!(args)

    case AnchoFijo.detectar(ruta, opciones_de_detectar(opts)) do
      {:ok, reporte} ->
        imprimir(ruta, reporte, opts)
        salir(codigo_de_salida(reporte))

      {:error, diagnosticos} ->
        abortar(Diagnostico.reporte(diagnosticos))
    end
  end

  defp interpretar!(args) do
    case OptionParser.parse(args, strict: @opciones) do
      {opts, [ruta], []} ->
        {opts, ruta}

      {_opts, [], []} ->
        abortar("falta la ruta del archivo\n\n" <> uso())

      {_opts, [_ruta | sobrantes], []} ->
        abortar("se esperaba una sola ruta, sobran: #{Enum.join(sobrantes, " ")}\n\n" <> uso())

      {_opts, _args, invalidas} ->
        detalle = Enum.map_join(invalidas, ", ", fn {flag, _valor} -> flag end)
        abortar("opciones inválidas: #{detalle}\n\n" <> uso())
    end
  end

  defp uso do
    "uso: mix ancho_fijo.detectar RUTA [--lineas N] [--bytes N] [--layout RUTA.exs] [--json]"
  end

  # El layout se carga acá y no en `detectar/2` porque evaluar un archivo es
  # cosa de la terminal, no de la librería. Un `.exs` que no devuelve un layout
  # es un error de uso, con código 2.
  defp opciones_de_detectar(opts) do
    opts
    |> Keyword.take([:lineas, :bytes])
    |> Keyword.put(:desde, :archivo)
    |> agregar_layout(Keyword.get(opts, :layout))
  end

  defp agregar_layout(opts, nil), do: opts

  defp agregar_layout(opts, ruta) do
    case cargar_layout(ruta) do
      {:ok, layout} -> Keyword.put(opts, :layout, layout)
      {:error, motivo} -> abortar("no se pudo cargar el layout #{ruta}: #{motivo}")
    end
  end

  defp cargar_layout(ruta) do
    {definicion, _binding} = Code.eval_file(ruta)

    case AnchoFijo.Layout.coercer(definicion) do
      {:ok, layout} -> {:ok, layout}
      {:error, diagnosticos} -> {:error, "\n" <> Diagnostico.reporte(diagnosticos)}
    end
  rescue
    error in [Code.LoadError, File.Error] -> {:error, Exception.message(error)}
    error -> {:error, "el archivo no evalúa: " <> Exception.message(error)}
  end

  defp imprimir(ruta, reporte, opts) do
    if Keyword.get(opts, :json, false) do
      Mix.shell().info(a_json(Map.put(reporte, :archivo, ruta)))
    else
      Mix.shell().info(encabezado(ruta, reporte))
      Mix.shell().info("  " <> resumen(reporte))
      Enum.each(reporte.observaciones, &Mix.shell().info("  - " <> &1))
    end
  end

  defp encabezado(ruta, %{probablemente_ancho_fijo?: true} = reporte) do
    IO.ANSI.format([:green, "#{ruta}: probablemente de ancho fijo" <> sufijo_layout(reporte)])
  end

  defp encabezado(ruta, reporte) do
    IO.ANSI.format([:red, "#{ruta}: probablemente NO es de ancho fijo" <> sufijo_layout(reporte)])
  end

  # Las observaciones del layout son las últimas de la lista y empiezan con
  # "entrada:" porque son mensajes de diagnóstico; se cuentan para el veredicto
  # del encabezado y del código de salida.
  defp sufijo_layout(reporte) do
    case desacuerdos_con_layout(reporte) do
      0 -> ""
      1 -> ", con 1 desacuerdo con el layout"
      n -> ", con #{n} desacuerdos con el layout"
    end
  end

  defp desacuerdos_con_layout(reporte) do
    Enum.count(reporte.observaciones, &String.starts_with?(&1, "entrada:"))
  end

  defp resumen(reporte) do
    [
      lineas(reporte),
      largo(reporte),
      Atom.to_string(reporte.encoding_probable),
      terminador(reporte.terminador)
    ]
    |> Enum.join(" · ")
  end

  defp lineas(%{lineas_analizadas: n, muestra_truncada?: true}), do: "#{n} líneas (muestra parcial)"
  defp lineas(%{lineas_analizadas: n}), do: "#{n} líneas"

  defp largo(%{largo_predominante: nil}), do: "sin líneas"

  defp largo(%{largo_consistente?: true, largo_predominante: n}),
    do: "largo #{n} bytes, consistente"

  defp largo(%{largo_predominante: n, largos: largos}),
    do: "largo predominante #{n} bytes, #{map_size(largos)} largos distintos"

  defp terminador(:crlf), do: "CRLF"
  defp terminador(:lf), do: "LF"
  defp terminador(:cr), do: "CR"
  defp terminador(:mixto), do: "terminadores mezclados"
  defp terminador(:ninguno), do: "sin terminador"

  defp codigo_de_salida(reporte) do
    if reporte.probablemente_ancho_fijo? and desacuerdos_con_layout(reporte) == 0, do: 0, else: 1
  end

  # `exit({:shutdown, n})` es la forma en que una tarea Mix fija el código de
  # salida del proceso sin matar la VM, lo que la deja testeable con
  # `catch_exit/1`. `Mix.raise/2` con `:exit_status` existe recién en Elixir
  # 1.14.0 y de todos modos imprime el mensaje con formato de excepción.
  @spec abortar(String.t()) :: no_return()
  defp abortar(mensaje) do
    Mix.shell().error(mensaje)
    exit({:shutdown, 2})
  end

  defp salir(0), do: :ok
  defp salir(codigo), do: exit({:shutdown, codigo})

  # JSON a mano, sin dependencia: el reporte tiene una forma conocida (mapas,
  # listas, binarios, átomos, enteros, booleanos y nil) y un encoder para eso
  # son treinta líneas. Agregar Jason al paquete para un flag de una tarea
  # sería la primera dependencia de runtime de la librería, por un caso que
  # el usuario puede no usar nunca. El test valida la salida con un decoder de
  # verdad, que sí es una dependencia de test.
  defp a_json(valor) when is_map(valor) do
    valor
    |> Enum.sort()
    |> Enum.map_join(",", fn {clave, valor} -> a_json(clave_json(clave)) <> ":" <> a_json(valor) end)
    |> then(&("{" <> &1 <> "}"))
  end

  defp a_json(valor) when is_list(valor), do: "[" <> Enum.map_join(valor, ",", &a_json/1) <> "]"
  defp a_json(nil), do: "null"
  defp a_json(true), do: "true"
  defp a_json(false), do: "false"
  defp a_json(valor) when is_atom(valor), do: a_json(Atom.to_string(valor))
  defp a_json(valor) when is_integer(valor), do: Integer.to_string(valor)
  defp a_json(valor) when is_binary(valor), do: "\"" <> escapar(valor) <> "\""

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
