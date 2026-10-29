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
    * `:unidad_probable` — `:bytes` si los largos son consistentes en bytes y
      no en caracteres, `:caracteres` al revés; `nil` cuando da lo mismo o
      no se puede decidir.
    * `:encoding_probable` — `:ascii`, `:utf8`, `:latin1`, `:mixto` (bytes
      latin-1 y secuencias UTF-8 en el mismo archivo, que es lo que pasa
      cuando el texto libre viene en UTF-8 y el resto no), `:utf16` (el
      "Unicode" de Notepad y Excel: hay que convertirlo antes) o `:ebcdic`
      (un archivo de mainframe transferido en binario: ídem).
    * `:bom` — `:utf8` (`EF BB BF`, lo que dejan Notepad y Excel "CSV
      UTF-8"), `:utf16le`, `:utf16be` o `nil`. Los largos se cuentan sin él.
    * `:marca_final_dos?` — si el archivo termina con `0x1A`, la marca de
      fin de archivo de DOS, que no es un registro. Los largos se cuentan
      sin ella.
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

  Una opción que no existe o un valor de otro tipo es un `ArgumentError`. Un
  `:layout` inválido es `{:error, diagnosticos}`, igual que en `parsear/3`.
  """

  alias AnchoFijo.Campo
  alias AnchoFijo.Diagnostico
  alias AnchoFijo.Entrada
  alias AnchoFijo.Layout
  alias AnchoFijo.Multiregistro
  alias AnchoFijo.Opciones
  alias AnchoFijo.Telemetria
  alias AnchoFijo.Tipo.Constante
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
          unidad_probable: :bytes | :caracteres | nil,
          encoding_probable: :ascii | :utf8 | :latin1 | :mixto | :utf16 | :ebcdic,
          bom: :utf8 | :utf16le | :utf16be | nil,
          marca_final_dos?: boolean(),
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
    opts = Opciones.validar!(opts, opciones_de_detectar(), "AnchoFijo.detectar/2")

    Telemetria.span(:detectar, %{desde: Entrada.origen(entrada, opts)}, fn ->
      with {:ok, layout} <- coercer_layout(Keyword.get(opts, :layout)),
           {:ok, muestra, truncada?} <- Entrada.leer_muestra(entrada, opts) do
        reporte = analizar(muestra, truncada?, Keyword.put(opts, :layout, layout))

        {{:ok, reporte}, %{lineas: reporte.lineas_analizadas, bytes: byte_size(muestra)},
         %{resultado: :ok, probablemente_ancho_fijo?: reporte.probablemente_ancho_fijo?}}
      else
        {:error, diagnosticos} ->
          {{:error, diagnosticos}, %{lineas: 0, bytes: 0},
           %{resultado: :error, probablemente_ancho_fijo?: nil}}
      end
    end)
  end

  @doc """
  Igual que `detectar/2`, pero devuelve el reporte o levanta `AnchoFijo.Error`.

  Lo que puede fallar en `detectar/2` es la entrada —una ruta que no existe, un
  argumento que no es binario— o el layout de la opción `:layout`. El reporte
  mismo nunca es un error: un archivo que no parece de ancho fijo es un
  resultado, con `probablemente_ancho_fijo?: false`.

      iex> AnchoFijo.Detector.detectar!("ABC\\nDEF\\n").largo_predominante
      3

      iex> AnchoFijo.Detector.detectar!("/no/existe.txt", desde: :archivo)
      ** (AnchoFijo.Error) entrada: se esperaba un archivo legible en "/no/existe.txt", llegó :enoent; la ruta no existe; revise el directorio de trabajo
  """
  @spec detectar!(term(), keyword()) :: reporte()
  def detectar!(entrada, opts \\ []) do
    case detectar(entrada, opts) do
      {:ok, reporte} -> reporte
      {:error, diagnosticos} -> raise AnchoFijo.Error, diagnosticos
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
  @spec contrastar(reporte(), Layout.t() | Multiregistro.t() | Enumerable.t()) :: [Diagnostico.t()]
  def contrastar(%{largo_predominante: _, encoding_probable: _}, %Multiregistro{}), do: []

  def contrastar(%{largo_predominante: _, encoding_probable: _} = reporte, layout) do
    case Layout.coercer(layout) do
      {:ok, layout} ->
        Enum.concat([
          contrastar_largo(reporte, layout),
          contrastar_encoding(reporte, layout),
          contrastar_unidad(reporte, layout)
        ])

      {:error, diagnosticos} ->
        diagnosticos
    end
  end

  defp opciones_de_detectar do
    [
      {:lineas, &(is_integer(&1) and &1 > 0), "un entero mayor que cero"},
      {:bytes, &(is_integer(&1) and &1 > 0), "un entero mayor que cero"},
      {:desde, &(&1 in [:auto, :archivo, :contenido]), ":auto, :archivo o :contenido"},
      {:layout,
       &(is_struct(&1, Layout) or is_struct(&1, Multiregistro) or is_list(&1) or is_map(&1)),
       "un AnchoFijo.Layout o su definición, o un AnchoFijo.Multiregistro"},
      {:delimitadores, &delimitadores?/1, "una lista de binarios no vacíos"}
    ]
  end

  defp delimitadores?(lista) when is_list(lista) do
    Enum.all?(lista, &(is_binary(&1) and &1 != ""))
  end

  defp delimitadores?(_otro), do: false

  # El layout se valida antes de leer la muestra: una definición inválida es
  # `{:error, diagnosticos}` como en `parsear/3`, no una observación en prosa
  # dentro de un reporte que dice `:ok`.
  defp coercer_layout(nil), do: {:ok, nil}
  defp coercer_layout(%Multiregistro{} = multi), do: {:ok, multi}
  defp coercer_layout(layout), do: Layout.coercer(layout)

  defp analizar(muestra, truncada?, opts) do
    maximo = Keyword.get(opts, :lineas, @lineas_default)
    {bom, muestra} = bom(muestra)
    {muestra, marca_dos?} = marca_final_dos(muestra, truncada?)
    {piezas, termina_con_terminador?} = piezas(muestra, truncada?)
    {lineas, vacias} = clasificar(piezas, maximo)

    base = %{
      lineas_analizadas: length(lineas),
      lineas_vacias: vacias,
      muestra_truncada?: truncada?,
      terminador: terminador(muestra),
      termina_con_terminador?: termina_con_terminador?,
      bom: bom,
      marca_final_dos?: marca_dos?
    }

    base
    |> Map.merge(analizar_largos(lineas))
    |> Map.merge(analizar_encoding(lineas, bom, muestra))
    |> Map.merge(analizar_delimitadores(lineas, opts))
    |> veredicto()
    |> con_observaciones(lineas, opts)
    |> con_multiregistro(lineas, Keyword.get(opts, :layout))
  end

  # Las marcas que Windows y los mainframes dejan en el archivo y que no son
  # datos: el BOM al principio y el 0x1A (Ctrl-Z, fin de archivo de DOS) al
  # final. Se sacan antes de contar, y se reportan aparte.
  defp bom(<<0xEF, 0xBB, 0xBF, resto::binary>>), do: {:utf8, resto}
  defp bom(<<0xFF, 0xFE, resto::binary>>), do: {:utf16le, resto}
  defp bom(<<0xFE, 0xFF, resto::binary>>), do: {:utf16be, resto}
  defp bom(muestra), do: {nil, muestra}

  defp marca_final_dos(muestra, false) when byte_size(muestra) > 0 do
    if :binary.last(muestra) == 0x1A,
      do: {binary_part(muestra, 0, byte_size(muestra) - 1), true},
      else: {muestra, false}
  end

  defp marca_final_dos(muestra, _truncada_o_vacia), do: {muestra, false}

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
    %{
      largos: %{},
      largo_consistente?: false,
      largo_predominante: nil,
      largos_en_caracteres: nil,
      unidad_probable: nil
    }
  end

  defp analizar_largos(lineas) do
    largos = Enum.frequencies_by(lineas, fn {linea, _numero} -> byte_size(linea) end)
    en_caracteres = largos_en_caracteres(lineas, largos)

    %{
      largos: largos,
      largo_consistente?: map_size(largos) == 1,
      largo_predominante: predominante(largos),
      largos_en_caracteres: en_caracteres,
      unidad_probable: unidad_probable(largos, en_caracteres)
    }
  end

  # Cuando los largos difieren por unidad, la unidad en la que son
  # consistentes es la del formato: un archivo UTF-8 que mide igual en bytes
  # y distinto en caracteres se midió en bytes al generarse.
  defp unidad_probable(_largos, nil), do: nil

  defp unidad_probable(largos, en_caracteres) do
    cond do
      map_size(largos) == 1 and map_size(en_caracteres) > 1 -> :bytes
      map_size(en_caracteres) == 1 and map_size(largos) > 1 -> :caracteres
      true -> nil
    end
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

  # UTF-16 y EBCDIC no son encodings que el layout pueda declarar: el
  # archivo hay que convertirlo. Se reconocen antes de mirar los bytes
  # inválidos, porque en los dos casos casi todo byte lo sería.
  defp analizar_encoding(_lineas, bom, _muestra) when bom in [:utf16le, :utf16be],
    do: %{encoding_probable: :utf16, bytes_no_utf8: []}

  defp analizar_encoding(lineas, _bom, muestra) do
    cond do
      utf16_sin_bom?(muestra) -> %{encoding_probable: :utf16, bytes_no_utf8: []}
      ebcdic?(muestra) -> %{encoding_probable: :ebcdic, bytes_no_utf8: []}
      true -> analizar_encoding(lineas)
    end
  end

  # UTF-16 sin BOM: texto latino en UTF-16 tiene un byte nulo cada dos.
  defp utf16_sin_bom?(muestra) when byte_size(muestra) >= 4 do
    length(:binary.matches(muestra, <<0>>)) * 4 >= byte_size(muestra)
  end

  defp utf16_sin_bom?(_muestra), do: false

  # EBCDIC (cp037, cp500): casi ningún byte donde ASCII pone letras y
  # dígitos (las letras y los dígitos EBCDIC van de 0x81 a 0xF9; en
  # 0x30..0x7A solo cae puntuación, y el espacio es 0x40, el `@` de ASCII),
  # el espacio EBCDIC entre los tres bytes más frecuentes, y no es UTF-8
  # válido. Un archivo latin-1 de verdad es letras y dígitos ASCII en su
  # mayor parte.
  defp ebcdic?(muestra) when byte_size(muestra) >= 8 do
    not String.valid?(muestra) and
      letras_y_digitos_ascii(muestra) * 10 < byte_size(muestra) and
      0x40 in mas_frecuentes(muestra, 3)
  end

  defp ebcdic?(_muestra), do: false

  defp letras_y_digitos_ascii(muestra) do
    for <<byte <- muestra>>, byte in ?0..?9 or byte in ?A..?Z or byte in ?a..?z, reduce: 0 do
      n -> n + 1
    end
  end

  defp mas_frecuentes(muestra, cuantos) do
    muestra
    |> :binary.bin_to_list()
    |> Enum.frequencies()
    |> Enum.sort_by(fn {_byte, veces} -> -veces end)
    |> Enum.take(cuantos)
    |> Enum.map(fn {byte, _veces} -> byte end)
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

  # Bytes que no son UTF-8 y, en el mismo archivo, secuencias UTF-8 válidas:
  # no es latin-1, es una mezcla por campo.
  defp encoding_probable(lineas, [_alguno | _resto]) do
    if Enum.any?(lineas, fn {linea, _numero} -> Transcodificacion.multibyte_utf8?(linea) end),
      do: :mixto,
      else: :latin1
  end

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
        is_nil(reporte.delimitador_sugerido) and
        reporte.encoding_probable not in [:utf16, :ebcdic]

    Map.put(reporte, :probablemente_ancho_fijo?, ancho_fijo?)
  end

  defp con_observaciones(reporte, lineas, opts) do
    reporte = Map.put(reporte, :observaciones, [])
    layout = Keyword.get(opts, :layout)

    observaciones =
      Enum.concat([
        observacion_marcas(reporte),
        observacion_muestra(reporte),
        observacion_largos(reporte, layout),
        observacion_caracteres(reporte),
        observacion_encoding(reporte),
        observacion_terminador(reporte),
        observacion_delimitador(reporte),
        observacion_layout(reporte, layout),
        observacion_constantes(lineas, layout)
      ])

    %{reporte | observaciones: observaciones}
  end

  # Los literales que el layout declara, contados en la muestra: es la forma
  # más barata de confirmar que el archivo es del formato que uno cree, y en
  # un multiregistro, de ver cuántas líneas son de cada tipo. Se compara en
  # bytes sobre la línea cruda, como lo hace el discriminador.
  defp observacion_constantes(_lineas, nil), do: []
  defp observacion_constantes([], _layout), do: []
  defp observacion_constantes(_lineas, %Multiregistro{}), do: []

  defp observacion_constantes(lineas, %Layout{} = layout) do
    total = length(lineas)

    layout.campos
    |> Enum.filter(&Campo.constante?/1)
    |> Enum.map(fn campo ->
      esperado = Constante.esperado(campo)
      desde = campo.posicion - 1

      coinciden =
        Enum.count(lineas, fn {linea, _numero} ->
          byte_size(linea) >= desde + campo.largo and
            Constante.coincide?(
              binary_part(linea, desde, campo.largo),
              esperado,
              campo.relleno
            )
        end)

      {desde, hasta} = Campo.rango(campo)

      donde =
        "el literal #{inspect(campo.valor)} del campo #{inspect(campo.nombre)} (posiciones #{desde}-#{hasta})"

      cond do
        coinciden == total ->
          "#{donde} aparece en las #{total} líneas"

        coinciden == 0 ->
          "#{donde} no aparece en ninguna de las #{total} líneas: el archivo no es del formato " <>
            "declarado, o el literal cambió"

        true ->
          "#{donde} aparece en #{coinciden} de #{total} líneas; si es un código de tipo de " <>
            "registro, el archivo es multiregistro y las demás líneas son de otro tipo"
      end
    end)
  end

  defp observacion_muestra(%{lineas_analizadas: 0}) do
    ["la muestra no tiene ninguna línea con contenido; revise si el archivo está vacío"]
  end

  defp observacion_muestra(%{muestra_truncada?: true, lineas_analizadas: cuantas}) do
    ["se analizaron #{cuantas} líneas de una muestra parcial del archivo"]
  end

  defp observacion_muestra(_reporte), do: []

  defp observacion_largos(%{lineas_analizadas: 0}, _layout), do: []

  defp observacion_largos(%{largo_consistente?: true} = reporte, _layout) do
    ["todas las #{reporte.lineas_analizadas} líneas miden #{reporte.largo_predominante} bytes"]
  end

  # Con un multiregistro, varios largos no son sospechosos: son los tipos.
  defp observacion_largos(reporte, %Multiregistro{}) do
    ["hay #{map_size(reporte.largos)} largos de línea distintos: #{detalle_de_largos(reporte)}"]
  end

  defp observacion_largos(reporte, _layout) do
    [
      "hay #{map_size(reporte.largos)} largos de línea distintos: #{detalle_de_largos(reporte)}; " <>
        "el predominante es #{reporte.largo_predominante}, así que el resto son las filas sospechosas"
    ]
  end

  defp detalle_de_largos(reporte) do
    reporte.largos
    |> Enum.sort_by(fn {_largo, veces} -> -veces end)
    |> Enum.map_join(", ", fn {largo, veces} -> "#{largo} (#{lineas(veces)})" end)
  end

  defp observacion_caracteres(%{largos_en_caracteres: nil}), do: []

  defp observacion_caracteres(%{largos_en_caracteres: en_caracteres} = reporte) do
    detalle = en_caracteres |> Map.keys() |> Enum.sort() |> Enum.join(", ")

    veredicto =
      case reporte.unidad_probable do
        :bytes ->
          "los largos son consistentes en bytes y no en caracteres: el formato mide en bytes " <>
            "y el texto es UTF-8; deje unidad: :bytes (el default) con encoding: :utf8"

        :caracteres ->
          "los largos son consistentes en caracteres y no en bytes: el formato mide en " <>
            "caracteres; declare unidad: :caracteres"

        nil ->
          "el archivo trae caracteres multibyte y hay que decidir en qué unidad cuenta el " <>
            "formato (ver unidad: :caracteres)"
      end

    ["en caracteres los largos son #{detalle}, distintos de los largos en bytes: " <> veredicto]
  end

  defp observacion_encoding(%{lineas_analizadas: 0}), do: []

  defp observacion_encoding(%{encoding_probable: :ascii}) do
    ["todos los bytes son ASCII: latin-1 y UTF-8 dan el mismo resultado en este archivo"]
  end

  defp observacion_encoding(%{encoding_probable: :utf8}) do
    ["hay caracteres no ASCII y la muestra es UTF-8 válida; use encoding: :utf8 (el default)"]
  end

  defp observacion_encoding(%{encoding_probable: :mixto, bytes_no_utf8: [primero | _resto]}) do
    [
      "hay bytes latin-1 " <>
        "(#{Transcodificacion.describir_byte(%{posicion: primero.posicion - 1, byte: primero.byte}, 1)} " <>
        "de la línea #{primero.linea}) y también secuencias UTF-8 válidas: los encodings están " <>
        "mezclados por campo; declare encoding: :latin1 en el layout y encoding: :utf8 en los " <>
        "campos que traen UTF-8 (el texto libre, casi siempre)"
    ]
  end

  defp observacion_encoding(%{encoding_probable: :latin1, bytes_no_utf8: [primero | _resto]}) do
    [
      "hay bytes que no son UTF-8 válido pero sí caracteres latin-1 " <>
        "(#{Transcodificacion.describir_byte(%{posicion: primero.posicion - 1, byte: primero.byte}, 1)} " <>
        "de la línea #{primero.linea}); declare encoding: :latin1 en el layout"
    ]
  end

  defp observacion_encoding(%{encoding_probable: :utf16} = reporte) do
    {nombre, iconv} =
      case reporte.bom do
        :utf16le -> {"UTF-16 LE (empieza con el BOM FF FE)", "UTF-16LE"}
        :utf16be -> {"UTF-16 BE (empieza con el BOM FE FF)", "UTF-16BE"}
        nil -> {"UTF-16 sin BOM (un byte nulo cada dos)", "UTF-16"}
      end

    [
      "el archivo es #{nombre}, el \"Unicode\" de Notepad y de Excel: ningún layout lo lee " <>
        "así; conviértalo a UTF-8 antes, por ejemplo con iconv -f #{iconv} -t UTF-8"
    ]
  end

  defp observacion_encoding(%{encoding_probable: :ebcdic}) do
    [
      "parece EBCDIC (cp037 o cp500, un archivo de mainframe transferido en binario): casi " <>
        "ningún byte es una letra o un dígito ASCII y el espacio EBCDIC (0x40) es de los más " <>
        "frecuentes; " <>
        "conviértalo antes, por ejemplo con iconv -f IBM037 -t UTF-8"
    ]
  end

  defp observacion_encoding(_reporte), do: []

  # Las marcas van primero: explican los largos que siguen.
  defp observacion_marcas(reporte) do
    bom =
      case reporte.bom do
        :utf8 ->
          [
            "el archivo empieza con un BOM UTF-8 (EF BB BF), lo que dejan Notepad y Excel: la " <>
              "primera línea mide 3 bytes más de lo que parece; bom: :ignorar en parsear/3 lo salta"
          ]

        _otro ->
          []
      end

    marca =
      if reporte.marca_final_dos?,
        do: [
          "el archivo termina con 0x1A, la marca de fin de archivo de DOS (Ctrl-Z): no es un " <>
            "registro; parsear/3 la omite con omitir_vacias: true (el default) y lo advierte"
        ],
        else: []

    bom ++ marca
  end

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

  # Con un multiregistro el veredicto es otro: un archivo con tres largos de
  # línea es de ancho fijo si cada línea es de un tipo y mide lo que ese
  # tipo declara. Se dice qué criterio discrimina, cuántas líneas son de
  # cada tipo, cuántas no son de ninguno y cuántas no miden lo que su tipo
  # declara. Con una función es lo único que se puede saber: la función no
  # se contrasta, se cuenta lo que devuelve.
  defp con_multiregistro(reporte, lineas, %Multiregistro{} = multi) when lineas != [] do
    total = length(lineas)

    {cuentas, desajustes} =
      lineas
      |> Enum.with_index(1)
      |> Enum.reduce({%{}, 0}, fn {{linea, numero}, indice}, {cuentas, desajustes} ->
        case Multiregistro.discriminar(multi, linea, numero, ubicacion(indice, total)) do
          {:ok, tipo, %{layout: layout}} ->
            cabe? = Multiregistro.largo_de(linea, layout) == layout.largo

            {Map.update(cuentas, tipo, 1, &(&1 + 1)),
             if(cabe?, do: desajustes, else: desajustes + 1)}

          {:error, _diagnosticos} ->
            {Map.update(cuentas, :sin_tipo, 1, &(&1 + 1)), desajustes}
        end
      end)

    por_tipo =
      Enum.map_join(multi.registros, ", ", fn {tipo, _} ->
        "#{Map.get(cuentas, tipo, 0)} #{inspect(tipo)}"
      end)

    sin_tipo = Map.get(cuentas, :sin_tipo, 0)

    observacion =
      "multiregistro con discriminador #{criterio(multi.discriminador)}: de #{total} líneas, " <>
        "#{por_tipo}, #{sin_tipo} sin tipo" <>
        if(sin_tipo > 0,
          do: "; las líneas sin tipo son un diagnóstico de estructura al parsear",
          else: ""
        ) <>
        if(desajustes > 0,
          do: "; #{lineas(desajustes)} no miden lo que su tipo declara",
          else: ""
        )

    %{
      reporte
      | observaciones: reporte.observaciones ++ [observacion],
        probablemente_ancho_fijo?:
          sin_tipo == 0 and desajustes == 0 and is_nil(reporte.delimitador_sugerido)
    }
  end

  defp con_multiregistro(reporte, _lineas, _layout), do: reporte

  defp ubicacion(1, _total), do: :primera
  defp ubicacion(total, total), do: :ultima
  defp ubicacion(_indice, _total), do: :resto

  defp criterio(%{por: :largo}), do: "por largo de línea"
  defp criterio(%{por: :posicion_en_archivo}), do: "por posición en el archivo"
  defp criterio(%{por: :funcion}), do: "por función (no contrastable: se cuenta lo que devuelve)"

  defp criterio(%{posicion: posicion, largo: largo}),
    do: "por código en las posiciones #{posicion}-#{posicion + largo - 1}"

  defp observacion_layout(_reporte, nil), do: []
  defp observacion_layout(_reporte, %Multiregistro{}), do: []

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

  defp contrastar_encoding(%{encoding_probable: :mixto} = reporte, %Layout{encoding: :utf8}) do
    [
      Diagnostico.nuevo(
        tipo: :entrada,
        esperado: "bytes UTF-8 válidos, porque el layout declara encoding: :utf8",
        recibido: "#{length(reporte.bytes_no_utf8)} bytes latin-1 junto con secuencias UTF-8",
        causa_probable:
          "los encodings están mezclados por campo; declare encoding: :latin1 en el layout " <>
            "y encoding: :utf8 en los campos que traen UTF-8"
      )
    ]
  end

  defp contrastar_encoding(%{encoding_probable: :mixto}, %Layout{encoding: :latin1} = layout) do
    if Enum.any?(layout.campos, &(&1.encoding == :utf8)) do
      []
    else
      [
        Diagnostico.nuevo(
          tipo: :entrada,
          esperado: "algún campo con encoding: :utf8, porque el archivo trae secuencias UTF-8",
          recibido: "un layout latin-1 en todos los campos",
          causa_probable:
            "los campos UTF-8 se leerían con doble codificación (operaciÃ³n); " <>
              "declare encoding: :utf8 en los campos que traen UTF-8"
        )
      ]
    end
  end

  defp contrastar_encoding(_reporte, _layout), do: []

  defp contrastar_unidad(%{unidad_probable: :bytes}, %Layout{unidad: :caracteres}) do
    [
      Diagnostico.nuevo(
        tipo: :entrada,
        esperado: "largos consistentes en caracteres, porque el layout declara unidad: :caracteres",
        recibido: "largos consistentes en bytes y distintos en caracteres",
        causa_probable: "el formato mide en bytes; deje unidad: :bytes con encoding: :utf8"
      )
    ]
  end

  defp contrastar_unidad(%{unidad_probable: :caracteres}, %Layout{unidad: :bytes}) do
    [
      Diagnostico.nuevo(
        tipo: :entrada,
        esperado: "largos consistentes en bytes, porque el layout mide en bytes",
        recibido: "largos consistentes en caracteres y distintos en bytes",
        causa_probable: "el formato mide en caracteres; declare unidad: :caracteres"
      )
    ]
  end

  defp contrastar_unidad(_reporte, _layout), do: []

  defp lineas(1), do: "1 línea"
  defp lineas(cuantas), do: "#{cuantas} líneas"

  defp veces(1), do: "1 vez"
  defp veces(cuantas), do: "#{cuantas} veces"
end
