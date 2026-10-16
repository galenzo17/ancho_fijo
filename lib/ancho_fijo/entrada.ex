defmodule AnchoFijo.Entrada do
  @moduledoc false
  # Resuelve el argumento `entrada` que comparten `detectar/2`, `parsear/3` y
  # `stream/3`: puede ser el contenido del archivo, una ruta, o un enumerable de
  # líneas ya abierto por el llamador.

  alias AnchoFijo.Diagnostico

  @limite_ruta 4095
  @muestra_default 64_000
  @bloque 65_536

  @spec leer(term(), keyword()) :: {:ok, binary()} | {:error, [Diagnostico.t()]}
  def leer(entrada, opts \\ [])

  def leer(entrada, opts) when is_binary(entrada) do
    if ruta?(entrada, opts), do: leer_archivo(entrada), else: {:ok, entrada}
  end

  def leer(entrada, _opts), do: {:error, [no_es_entrada(entrada)]}

  @doc false
  @spec leer_muestra(term(), keyword()) :: {:ok, binary(), boolean()} | {:error, [Diagnostico.t()]}
  def leer_muestra(entrada, opts \\ [])

  def leer_muestra(entrada, opts) when is_binary(entrada) do
    limite = Keyword.get(opts, :bytes, @muestra_default)

    if ruta?(entrada, opts) do
      leer_muestra_de_archivo(entrada, limite)
    else
      {:ok, recortar(entrada, limite), byte_size(entrada) > limite}
    end
  end

  def leer_muestra(entrada, _opts), do: {:error, [no_es_entrada(entrada)]}

  @spec lineas(term(), keyword()) :: {:ok, Enumerable.t()} | {:error, [Diagnostico.t()]}
  def lineas(entrada, opts \\ [])

  def lineas(entrada, opts) when is_binary(entrada) do
    if ruta?(entrada, opts) do
      abrir_stream(entrada)
    else
      {:ok, dividir(entrada)}
    end
  end

  def lineas(entrada, _opts) do
    if enumerable?(entrada), do: {:ok, entrada}, else: {:error, [no_es_entrada(entrada)]}
  end

  @spec dividir(binary()) :: [binary()]
  def dividir(binario), do: String.split(binario, ["\r\n", "\n", "\r"])

  # Como `dividir/1`, pero cada línea conserva su terminador, que es lo que
  # hace falta para saber en qué byte empieza la siguiente. Es lo mismo que
  # entrega `File.stream!/1`, así que `stream/3` trata igual a los dos.
  @spec dividir_con_terminador(binary()) :: [binary()]
  def dividir_con_terminador(binario) do
    ~r/\r\n|\n|\r/
    |> Regex.split(binario, include_captures: true)
    |> Enum.chunk_every(2)
    |> Enum.map(&IO.iodata_to_binary/1)
  end

  @spec sin_terminador(binary()) :: binary()
  def sin_terminador(linea) do
    linea |> String.trim_trailing("\n") |> String.trim_trailing("\r")
  end

  defp abrir_stream(ruta) do
    if File.regular?(ruta) do
      {:ok, File.stream!(ruta)}
    else
      {:error, [ilegible(ruta, :enoent)]}
    end
  end

  # Las líneas con su terminador, byte a byte como están en el archivo. Para
  # un binario es `dividir_con_terminador/1`; para una ruta, bloques crudos
  # partidos acá, porque `File.stream!/1` en modo línea convierte CRLF en LF
  # y no corta por CR solo. Un enumerable del llamador se entrega como viene.
  @doc false
  @spec lineas_con_terminador(term(), keyword()) ::
          {:ok, Enumerable.t()} | {:error, [Diagnostico.t()]}
  def lineas_con_terminador(entrada, opts) when is_binary(entrada) do
    if ruta?(entrada, opts) do
      with {:ok, bloques} <- bloques(entrada, opts), do: {:ok, partir_bloques(bloques)}
    else
      {:ok, dividir_con_terminador(entrada)}
    end
  end

  def lineas_con_terminador(entrada, opts), do: lineas(entrada, opts)

  # El contenido en bloques de bytes: uno solo para un binario, los del
  # archivo para una ruta, los que vengan para un enumerable.
  @doc false
  @spec bloques(term(), keyword()) :: {:ok, Enumerable.t()} | {:error, [Diagnostico.t()]}
  def bloques(entrada, opts) when is_binary(entrada) do
    cond do
      not ruta?(entrada, opts) -> {:ok, [entrada]}
      File.regular?(entrada) -> {:ok, stream_de_bloques(entrada)}
      true -> {:error, [ilegible(entrada, :enoent)]}
    end
  end

  def bloques(entrada, opts), do: lineas(entrada, opts)

  # `File.stream!/3` cambió el orden de sus argumentos en Elixir 1.16 y el
  # orden viejo se deprecó; un `Stream.resource/3` sobre `IO.binread/2` es
  # igual de lazy y compila sin avisos en toda la matriz.
  defp stream_de_bloques(ruta) do
    Stream.resource(
      fn -> File.open!(ruta, [:read, :binary, :raw]) end,
      fn dispositivo ->
        case IO.binread(dispositivo, @bloque) do
          datos when is_binary(datos) -> {[datos], dispositivo}
          _eof_o_error -> {:halt, dispositivo}
        end
      end,
      fn dispositivo -> File.close(dispositivo) end
    )
  end

  # Parte un stream de bloques en líneas con terminador, arrastrando el
  # pedazo incompleto de un bloque al siguiente. Un bloque que termina en CR
  # se guarda entero porque puede ser la mitad de un CRLF.
  defp partir_bloques(bloques) do
    Stream.transform(
      bloques,
      fn -> "" end,
      fn bloque, resto -> partir_completas(resto <> bloque) end,
      fn resto -> if resto == "", do: {[], ""}, else: {[resto], ""} end,
      fn _resto -> :ok end
    )
  end

  defp partir_completas(""), do: {[], ""}

  defp partir_completas(datos) do
    {completas, [ultima]} = datos |> dividir_con_terminador() |> Enum.split(-1)

    cond do
      String.ends_with?(ultima, "\r") -> {completas, ultima}
      String.ends_with?(ultima, "\n") -> {completas ++ [ultima], ""}
      true -> {completas, ultima}
    end
  end

  defp leer_archivo(ruta) do
    case File.read(ruta) do
      {:ok, contenido} -> {:ok, contenido}
      {:error, motivo} -> {:error, [ilegible(ruta, motivo)]}
    end
  end

  defp leer_muestra_de_archivo(ruta, limite) do
    case File.open(ruta, [:read, :binary]) do
      {:ok, dispositivo} -> leer_bytes(dispositivo, ruta, limite)
      {:error, motivo} -> {:error, [ilegible(ruta, motivo)]}
    end
  end

  defp leer_bytes(dispositivo, ruta, limite) do
    resultado = IO.binread(dispositivo, limite + 1)
    :ok = File.close(dispositivo)

    case resultado do
      :eof -> {:ok, "", false}
      {:error, motivo} -> {:error, [ilegible(ruta, motivo)]}
      datos -> {:ok, recortar(datos, limite), byte_size(datos) > limite}
    end
  end

  defp recortar(binario, limite) when byte_size(binario) <= limite, do: binario
  defp recortar(binario, limite), do: :binary.part(binario, 0, limite)

  defp ruta?(binario, opts) do
    case Keyword.get(opts, :desde, :auto) do
      :archivo -> true
      :contenido -> false
      :auto -> plausible_como_ruta?(binario) and regular?(binario)
    end
  end

  # Una muestra de archivo y una ruta son ambas binarios, así que hay que
  # decidir. Un nombre de archivo no trae saltos de línea ni bytes nulos y no
  # mide más que el límite del sistema; ante la duda, `desde:` lo zanja.
  defp plausible_como_ruta?(binario) do
    byte_size(binario) in 1..@limite_ruta and
      not String.contains?(binario, ["\n", "\r", <<0>>])
  end

  defp regular?(binario) do
    File.regular?(binario)
  rescue
    ArgumentError -> false
  end

  defp enumerable?(entrada) do
    Enumerable.impl_for(entrada) != nil
  end

  defp ilegible(ruta, motivo) do
    Diagnostico.nuevo(
      tipo: :entrada,
      esperado: "un archivo legible en #{inspect(ruta)}",
      recibido: inspect(motivo),
      causa_probable: descripcion_motivo(motivo)
    )
  end

  defp descripcion_motivo(:enoent), do: "la ruta no existe; revise el directorio de trabajo"
  defp descripcion_motivo(:eacces), do: "el proceso no tiene permisos de lectura sobre el archivo"
  defp descripcion_motivo(:eisdir), do: "la ruta es un directorio, no un archivo"
  defp descripcion_motivo(motivo), do: "error del sistema de archivos: #{inspect(motivo)}"

  defp no_es_entrada(entrada) do
    Diagnostico.nuevo(
      tipo: :entrada,
      esperado: "un binario con el contenido, una ruta a un archivo o un enumerable de líneas",
      recibido: inspect(entrada),
      causa_probable: "el argumento de entrada no es de un tipo que se pueda leer"
    )
  end
end
