defmodule AnchoFijo.Entrada do
  @moduledoc false
  # Resuelve el argumento `entrada` que comparten `detectar/2`, `parsear/3` y
  # `stream/3`: puede ser el contenido del archivo, una ruta, o un enumerable de
  # líneas ya abierto por el llamador.

  alias AnchoFijo.Diagnostico

  @limite_ruta 4095
  @muestra_default 64_000

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
