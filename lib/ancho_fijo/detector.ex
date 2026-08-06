defmodule AnchoFijo.Detector do
  @moduledoc """
  Interroga el archivo antes de parsearlo.

  Este es el módulo que justifica la librería. La especificación que manda el
  cliente y el archivo que manda el banco son dos documentos distintos, y la
  diferencia se descubre siempre tarde: después de escribir el parser, en la
  primera corrida con datos reales, un viernes. `detectar/2` mueve ese
  descubrimiento al día uno.

      iex> {:ok, reporte} = AnchoFijo.Detector.detectar("12345678-9JUAN PEREZ  \\n98765432-1ANA SOTO    \\n")
      iex> {reporte.largo_consistente?, reporte.largo_predominante, reporte.terminador}
      {true, 22, :lf}
      iex> reporte.probablemente_ancho_fijo?
      true

  Y el caso que más veces salva el proyecto: el archivo que dijeron que era de
  ancho fijo y no lo es.

      iex> {:ok, reporte} = AnchoFijo.Detector.detectar("juan;100\\nmaria;20000\\n")
      iex> reporte.probablemente_ancho_fijo?
      false
      iex> reporte.delimitador_sugerido
      ";"

  ## El reporte

  Un mapa con estas claves:

    * `:lineas_analizadas` — líneas con contenido consideradas.
    * `:lineas_vacias` — líneas en blanco encontradas y excluidas del análisis.
    * `:muestra_truncada?` — si se leyó solo parte del archivo.
    * `:largos` — frecuencia de cada largo de línea en bytes, `%{120 => 18}`.
    * `:largo_consistente?` — `true` si hay un solo largo.
    * `:largo_predominante` — el largo más frecuente, o `nil` si no hay líneas.
    * `:largos_en_caracteres` — igual que `:largos` pero en caracteres, solo si
      el archivo es UTF-8 con multibyte; `nil` en otro caso.
    * `:encoding_probable` — `:ascii`, `:utf8` o `:latin1`.
    * `:bytes_no_utf8` — hasta cinco bytes que rompen UTF-8, con línea y posición.
    * `:terminador` — `:crlf`, `:lf`, `:cr`, `:mixto` o `:ninguno`.
    * `:termina_con_terminador?` — `nil` si la muestra está truncada.
    * `:delimitadores` — análisis de `;`, `,`, tab y `|`.
    * `:delimitador_sugerido` — el delimitador que sugiere que el archivo es
      delimitado, o `nil`.
    * `:probablemente_ancho_fijo?` — el veredicto, resumido.
    * `:observaciones` — el reporte en prosa, para pegar en un correo.

  ## Opciones

    * `:lineas` — máximo de líneas a analizar. Default 200.
    * `:bytes` — máximo de bytes a leer del archivo. Default 64.000.
    * `:desde` — `:auto` (default), `:archivo` o `:contenido`, para desambiguar
      si el binario es una ruta o el contenido mismo.
    * `:layout` — un `AnchoFijo.Layout` o una definición, para contrastar lo que
      el archivo dice con lo que la especificación declara.
    * `:delimitadores` — lista de candidatos a delimitador. Default `[";", ",", "\\t", "|"]`.
  """

  alias AnchoFijo.Campo
  alias AnchoFijo.Diagnostico
  alias AnchoFijo.Entrada
  alias AnchoFijo.Layout
  alias AnchoFijo.Transcodificacion

  @lineas_default 200
  @delimitadores_default [";", ",", "\t", "|"]
  @maximo_bytes_reportados 5

  @type reporte :: %{
          lineas_analizadas: non_neg_integer(),
          lineas_vacias: non_neg_integer(),
          muestra_truncada?: boolean(),
          largos: %{optional(non_neg_integer()) => pos_integer()},
          largo_consistente?: boolean(),
          largo_predominante: non_neg_integer() | nil,
          largos_en_caracteres: %{optional(non_neg_integer()) => pos_integer()} | nil,
          encoding_probable: :ascii | :utf8 | :latin1,
          bytes_no_utf8: [map()],
          terminador: :crlf | :lf | :cr | :mixto | :ninguno,
          termina_con_terminador?: boolean() | nil,
          delimitadores: %{optional(String.t()) => map()},
          delimitador_sugerido: String.t() | nil,
          probablemente_ancho_fijo?: boolean(),
          observaciones: [String.t()]
        }

  @doc """
  Analiza una muestra y devuelve el reporte.

  Acepta el contenido como binario, una ruta a un archivo o —vía `:desde`— la
  desambiguación explícita entre ambos.

      iex> {:ok, reporte} = AnchoFijo.Detector.detectar("AAAA\\nBBB\\n")
      iex> reporte.largos
      %{3 => 1, 4 => 1}
      iex> reporte.largo_consistente?
      false

  Un archivo en latin-1 se delata solo:

      iex> {:ok, reporte} = AnchoFijo.Detector.detectar(<<74, 79, 83, 201, 10>>)
      iex> reporte.encoding_probable
      :latin1
      iex> hd(reporte.bytes_no_utf8)
      %{linea: 1, posicion: 4, byte: 201}
  """
  @spec detectar(term(), keyword()) :: {:ok, reporte()} | {:error, [Diagnostico.t()]}
  def detectar(entrada, opts \\ []) do
    with {:ok, muestra, truncada?} <- Entrada.leer_muestra(entrada, opts) do
      {:ok, analizar(muestra, truncada?, opts)}
    end
  end

  @doc """
  Contrasta un reporte con un layout y devuelve los desacuerdos como diagnósticos.

  Es la pregunta "¿esto es realmente lo que me dijeron que es?" en forma de
  función. Una lista vacía significa que el archivo y la especificación
  concuerdan en lo que se puede verificar sin parsear.

      iex> {:ok, reporte} = AnchoFijo.Detector.detectar("ABCDEFGH\\nIJKLMNOP\\n")
      iex> layout = AnchoFijo.Layout.nuevo!(campos: [[nombre: :a, largo: 10]])
      iex> [diagnostico] = AnchoFijo.Detector.contrastar(reporte, layout)
      iex> AnchoFijo.Diagnostico.mensaje(diagnostico)
      "entrada: se esperaba un largo de línea de 10 bytes según el layout, llegó 8; el archivo tiene 2 bytes menos por línea: falta un campo, o el layout es de otra versión del formato"

      iex> {:ok, reporte} = AnchoFijo.Detector.detectar("ABCDEFGH\\nIJKLMNOP\\n")
      iex> AnchoFijo.Detector.contrastar(reporte, AnchoFijo.Layout.nuevo!(campos: [[nombre: :a, largo: 8]]))
      []
  """
  @spec contrastar(reporte(), Layout.t() | Enumerable.t()) :: [Diagnostico.t()]
  def contrastar(reporte, layout) do
    case Layout.coercer(layout) do
      {:ok, layout} ->
        Enum.concat([contrastar_largo(reporte, layout), contrastar_encoding(reporte, layout)])

      {:error, diagnosticos} ->
        diagnosticos
    end
  end

  defp analizar(muestra, truncada?, opts) do
    maximo = Keyword.get(opts, :lineas, @lineas_default)
    {piezas, termina_con_terminador?} = piezas(muestra, truncada?)
    {lineas, vacias} = clasificar(piezas, maximo)

    base = %{
      lineas_analizadas: length(lineas),
      lineas_vacias: vacias,
      muestra_truncada?: truncada?,
      terminador: terminador(muestra),
      termina_con_terminador?: termina_con_terminador?
    }

    base
    |> Map.merge(analizar_largos(lineas))
    |> Map.merge(analizar_encoding(lineas))
    |> Map.merge(analizar_delimitadores(lineas, opts))
    |> veredicto()
    |> con_observaciones(opts)
  end

  defp piezas(muestra, true), do: {muestra |> Entrada.dividir() |> Enum.drop(-1), nil}

  defp piezas(muestra, false) do
    piezas = Entrada.dividir(muestra)

    if List.last(piezas) == "" do
      {Enum.drop(piezas, -1), true}
    else
      {piezas, false}
    end
  end

  defp clasificar(piezas, maximo) do
    numeradas = Enum.with_index(piezas, 1)
    {vacias, con_contenido} = Enum.split_with(numeradas, fn {linea, _numero} -> linea == "" end)
    {Enum.take(con_contenido, maximo), length(vacias)}
  end

  defp analizar_largos([]) do
    %{largos: %{}, largo_consistente?: false, largo_predominante: nil, largos_en_caracteres: nil}
  end

  defp analizar_largos(lineas) do
    largos = Enum.frequencies_by(lineas, fn {linea, _numero} -> byte_size(linea) end)

    %{
      largos: largos,
      largo_consistente?: map_size(largos) == 1,
      largo_predominante: predominante(largos),
      largos_en_caracteres: largos_en_caracteres(lineas, largos)
    }
  end

  defp predominante(largos) do
    largos |> Enum.max_by(fn {_largo, veces} -> veces end) |> elem(0)
  end

  # Solo tiene sentido reportar los dos largos cuando pueden diferir: en latin-1
  # un byte es un carácter, y en ASCII la pregunta no existe. Cuando difieren,
  # esa diferencia es la causa raíz de la mitad de los layouts corridos.
  defp largos_en_caracteres(lineas, largos_en_bytes) do
    textos = Enum.map(lineas, fn {linea, _numero} -> linea end)

    if Enum.all?(textos, &Transcodificacion.utf8?/1) and
         Enum.any?(textos, &(not Transcodificacion.ascii?(&1))) do
      en_caracteres = Enum.frequencies_by(textos, &String.length/1)
      if en_caracteres == largos_en_bytes, do: nil, else: en_caracteres
    end
  end

  defp analizar_encoding([]) do
    %{encoding_probable: :ascii, bytes_no_utf8: []}
  end

  defp analizar_encoding(lineas) do
    invalidos =
      lineas
      |> Enum.flat_map(&byte_invalido/1)
      |> Enum.take(@maximo_bytes_reportados)

    %{encoding_probable: encoding_probable(lineas, invalidos), bytes_no_utf8: invalidos}
  end

  defp byte_invalido({linea, numero}) do
    case Transcodificacion.primer_byte_invalido(linea) do
      nil -> []
      detalle -> [%{linea: numero, posicion: detalle.posicion + 1, byte: detalle.byte}]
    end
  end

  defp encoding_probable(_lineas, [_alguno | _resto]), do: :latin1

  defp encoding_probable(lineas, []) do
    if Enum.all?(lineas, fn {linea, _numero} -> Transcodificacion.ascii?(linea) end),
      do: :ascii,
      else: :utf8
  end

  defp terminador(muestra) do
    crlf = contar(muestra, "\r\n")
    lf = contar(muestra, "\n") - crlf
    cr = contar(muestra, "\r") - crlf

    case {crlf, lf, cr} do
      {0, 0, 0} -> :ninguno
      {_crlf, 0, 0} -> :crlf
      {0, _lf, 0} -> :lf
      {0, 0, _cr} -> :cr
      _mezcla -> :mixto
    end
  end

  defp contar(binario, patron), do: length(:binary.matches(binario, patron))

  defp analizar_delimitadores(lineas, opts) do
    candidatos = Keyword.get(opts, :delimitadores, @delimitadores_default)

    analisis =
      candidatos
      |> Enum.map(&{&1, analizar_delimitador(lineas, &1)})
      |> Enum.reject(fn {_delimitador, analisis} -> analisis.total == 0 end)
      |> Map.new()

    %{delimitadores: analisis, delimitador_sugerido: sugerido(analisis)}
  end

  defp analizar_delimitador(lineas, delimitador) do
    posiciones = Enum.map(lineas, fn {linea, _numero} -> posiciones_de(linea, delimitador) end)
    conteos = Enum.map(posiciones, &length/1)
    distintos = Enum.uniq(conteos)

    %{
      total: Enum.sum(conteos),
      lineas: Enum.count(conteos, &(&1 > 0)),
      por_linea: if(match?([_uno], distintos), do: hd(distintos)),
      posiciones_fijas?: match?([_una], Enum.uniq(posiciones)),
      constante?: match?([_uno], distintos) and hd(distintos) > 0
    }
  end

  defp posiciones_de(linea, delimitador) do
    linea |> :binary.matches(delimitador) |> Enum.map(fn {posicion, _largo} -> posicion end)
  end

  # La señal de que un archivo es delimitado no es que tenga comas: un nombre
  # puede traerlas. Es que la cantidad de comas por línea sea idéntica y sus
  # posiciones NO lo sean. Si las posiciones también coinciden, entonces el
  # separador es decorativo y el archivo sí es de ancho fijo.
  defp sugerido(analisis) do
    analisis
    |> Enum.filter(fn {_delimitador, a} -> a.constante? and not a.posiciones_fijas? end)
    |> Enum.max_by(fn {_delimitador, a} -> a.por_linea end, fn -> nil end)
    |> case do
      nil -> nil
      {delimitador, _analisis} -> delimitador
    end
  end

  defp veredicto(reporte) do
    ancho_fijo? =
      reporte.lineas_analizadas > 0 and reporte.largo_consistente? and
        is_nil(reporte.delimitador_sugerido)

    Map.put(reporte, :probablemente_ancho_fijo?, ancho_fijo?)
  end

  defp con_observaciones(reporte, opts) do
    reporte = Map.put(reporte, :observaciones, [])

    observaciones =
      Enum.concat([
        observacion_muestra(reporte),
        observacion_largos(reporte),
        observacion_caracteres(reporte),
        observacion_encoding(reporte),
        observacion_terminador(reporte),
        observacion_delimitador(reporte),
        observacion_layout(reporte, Keyword.get(opts, :layout))
      ])

    %{reporte | observaciones: observaciones}
  end

  defp observacion_muestra(%{lineas_analizadas: 0}) do
    ["la muestra no tiene ninguna línea con contenido; revise si el archivo está vacío"]
  end

  defp observacion_muestra(%{muestra_truncada?: true, lineas_analizadas: cuantas}) do
    ["se analizaron #{cuantas} líneas de una muestra parcial del archivo"]
  end

  defp observacion_muestra(_reporte), do: []

  defp observacion_largos(%{lineas_analizadas: 0}), do: []

  defp observacion_largos(%{largo_consistente?: true} = reporte) do
    ["todas las #{reporte.lineas_analizadas} líneas miden #{reporte.largo_predominante} bytes"]
  end

  defp observacion_largos(reporte) do
    detalle =
      reporte.largos
      |> Enum.sort_by(fn {_largo, veces} -> -veces end)
      |> Enum.map_join(", ", fn {largo, veces} -> "#{largo} (#{lineas(veces)})" end)

    [
      "hay #{map_size(reporte.largos)} largos de línea distintos: #{detalle}; " <>
        "el predominante es #{reporte.largo_predominante}, así que el resto son las filas sospechosas"
    ]
  end

  defp observacion_caracteres(%{largos_en_caracteres: nil}), do: []

  defp observacion_caracteres(%{largos_en_caracteres: en_caracteres}) do
    detalle = en_caracteres |> Map.keys() |> Enum.sort() |> Enum.join(", ")

    [
      "en caracteres los largos son #{detalle}, distintos de los largos en bytes: " <>
        "el archivo trae caracteres multibyte y hay que decidir en qué unidad cuenta el formato " <>
        "(ver unidad: :caracteres)"
    ]
  end

  defp observacion_encoding(%{lineas_analizadas: 0}), do: []

  defp observacion_encoding(%{encoding_probable: :ascii}) do
    ["todos los bytes son ASCII: latin-1 y UTF-8 dan el mismo resultado en este archivo"]
  end

  defp observacion_encoding(%{encoding_probable: :utf8}) do
    ["hay caracteres no ASCII y la muestra es UTF-8 válida; use encoding: :utf8 (el default)"]
  end

  defp observacion_encoding(%{encoding_probable: :latin1, bytes_no_utf8: [primero | _resto]}) do
    [
      "hay bytes que no son UTF-8 válido pero sí caracteres latin-1 " <>
        "(#{Transcodificacion.describir_byte(%{posicion: primero.posicion - 1, byte: primero.byte}, 1)} " <>
        "de la línea #{primero.linea}); declare encoding: :latin1 en el layout"
    ]
  end

  defp observacion_encoding(_reporte), do: []

  defp observacion_terminador(%{terminador: :ninguno}) do
    ["no hay terminadores de línea: el archivo es una sola línea o viene sin saltos"]
  end

  defp observacion_terminador(%{terminador: :mixto}) do
    [
      "hay terminadores de línea mezclados (CRLF y LF en el mismo archivo); " <>
        "suele pasar cuando el archivo se editó a mano después de generarse"
    ]
  end

  defp observacion_terminador(%{terminador: terminador} = reporte) do
    [
      "las líneas terminan en #{nombre_terminador(terminador)}"
      | observacion_terminador_final(reporte)
    ]
  end

  defp observacion_terminador_final(%{termina_con_terminador?: false}) do
    [
      "la última línea no trae terminador; es válido, pero algunos lectores " <>
        "line-by-line la pierden o la reportan corta"
    ]
  end

  defp observacion_terminador_final(_reporte), do: []

  defp nombre_terminador(:crlf), do: "CRLF (\\r\\n), estilo Windows"
  defp nombre_terminador(:lf), do: "LF (\\n), estilo Unix"
  defp nombre_terminador(:cr), do: "CR (\\r) solo, estilo Mac clásico"

  defp observacion_delimitador(%{delimitador_sugerido: nil} = reporte) do
    fijos =
      reporte.delimitadores
      |> Enum.filter(fn {_delimitador, a} -> a.posiciones_fijas? and a.total > 0 end)
      |> Enum.map(fn {delimitador, a} ->
        "el carácter #{inspect(delimitador)} aparece #{veces(a.por_linea)} por línea " <>
          "siempre en las mismas posiciones: es un separador decorativo, no un delimitador"
      end)

    fijos
  end

  defp observacion_delimitador(%{delimitador_sugerido: delimitador} = reporte) do
    analisis = Map.fetch!(reporte.delimitadores, delimitador)

    [
      "el carácter #{inspect(delimitador)} aparece #{veces(analisis.por_linea)} en todas las líneas " <>
        "y en posiciones variables: esto parece un archivo delimitado, no de ancho fijo"
    ]
  end

  defp observacion_layout(_reporte, nil), do: []

  defp observacion_layout(reporte, layout) do
    Enum.map(contrastar(reporte, layout), &Diagnostico.mensaje/1)
  end

  defp contrastar_largo(%{largo_predominante: nil}, _layout), do: []

  defp contrastar_largo(reporte, layout) do
    esperado = Layout.largo(layout)
    encontrado = largo_comparable(reporte, layout)

    if encontrado == esperado do
      []
    else
      [desajuste_de_largo(esperado, encontrado, layout)]
    end
  end

  defp largo_comparable(reporte, %Layout{unidad: :caracteres} = _layout) do
    case reporte.largos_en_caracteres do
      nil -> reporte.largo_predominante
      en_caracteres -> predominante(en_caracteres)
    end
  end

  defp largo_comparable(reporte, _layout), do: reporte.largo_predominante

  defp desajuste_de_largo(esperado, encontrado, layout) do
    unidad = Campo.nombre_unidad(layout.unidad)
    diferencia = abs(esperado - encontrado)

    causa =
      if encontrado < esperado do
        "el archivo tiene #{diferencia} #{unidad} menos por línea: falta un campo, " <>
          "o el layout es de otra versión del formato"
      else
        "el archivo tiene #{diferencia} #{unidad} más por línea: sobra un campo declarado, " <>
          "hay relleno no declarado al final, o el terminador quedó dentro de la línea"
      end

    Diagnostico.nuevo(
      tipo: :entrada,
      esperado: "un largo de línea de #{esperado} #{unidad} según el layout",
      recibido: encontrado,
      causa_probable: causa
    )
  end

  defp contrastar_encoding(%{encoding_probable: :latin1} = reporte, %Layout{encoding: :utf8}) do
    [
      Diagnostico.nuevo(
        tipo: :entrada,
        esperado: "bytes UTF-8 válidos, porque el layout declara encoding: :utf8",
        recibido: "#{length(reporte.bytes_no_utf8)} bytes que no lo son",
        causa_probable: "el archivo parece latin-1; declare encoding: :latin1 en el layout"
      )
    ]
  end

  defp contrastar_encoding(_reporte, _layout), do: []

  defp lineas(1), do: "1 línea"
  defp lineas(cuantas), do: "#{cuantas} líneas"

  defp veces(1), do: "1 vez"
  defp veces(cuantas), do: "#{cuantas} veces"
end
