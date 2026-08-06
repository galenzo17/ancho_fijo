defmodule AnchoFijo.Transcodificacion do
  @moduledoc """
  Decodifica bytes a UTF-8 y, cuando no puede, explica por qué.

  El encoding es el primer sospechoso de cualquier integración bancaria: los
  mainframes emiten latin-1, los ERP modernos UTF-8, y nadie lo declara en el
  archivo. Este módulo convierte y diagnostica; nunca levanta una excepción por
  un byte raro.

      iex> AnchoFijo.Transcodificacion.a_utf8(<<74, 79, 83, 201>>, :latin1)
      {:ok, "JOSÉ"}

      iex> {:error, detalle} = AnchoFijo.Transcodificacion.a_utf8(<<74, 79, 83, 201, 32>>, :utf8)
      iex> detalle.motivo
      :bytes_invalidos
      iex> AnchoFijo.Transcodificacion.causa_probable(detalle, :utf8)
      "el byte 0xC9 no es UTF-8 válido pero sí es un carácter latin-1; declare encoding: :latin1 en el layout"

  ## Caracteres de control

  Ambos encodings rechazan los caracteres de control (0x00–0x1F menos el
  tabulador, y 0x7F–0x9F). No es purismo: el rango 0x80–0x9F es control en
  latin-1 pero contiene comillas y guiones en Windows-1252, así que encontrarlo
  ahí casi siempre significa que el archivo es cp1252 y no latin-1. Preferimos
  decirlo a devolver basura silenciosa.
  """

  @typedoc """
  Detalle de una falla de decodificación.

  `:posicion` es el offset 0-based en bytes dentro del binario inspeccionado, y
  `:byte` es el byte —o el codepoint, si el problema es un control en UTF-8—
  que la provocó.
  """
  @type detalle :: %{
          motivo: :bytes_invalidos | :secuencia_incompleta | :caracter_de_control,
          posicion: non_neg_integer(),
          byte: non_neg_integer()
        }

  @typedoc """
  Lo mínimo que necesita `describir_byte/2`: un offset y el byte que lo ocupa.

  Todo `t:detalle/0` sirve, pero también un mapa armado a mano por quien ya
  guardó esos dos datos en otra parte.
  """
  @type ubicacion :: %{
          required(:posicion) => non_neg_integer(),
          required(:byte) => non_neg_integer(),
          optional(atom()) => term()
        }

  @type encoding :: :utf8 | :latin1

  @doc """
  Convierte un binario a UTF-8 según el encoding declarado.

      iex> AnchoFijo.Transcodificacion.a_utf8("MARIA", :utf8)
      {:ok, "MARIA"}

      iex> AnchoFijo.Transcodificacion.a_utf8("MARÍA", :utf8)
      {:ok, "MARÍA"}

      iex> {:error, detalle} = AnchoFijo.Transcodificacion.a_utf8(<<77, 65, 0, 65>>, :latin1)
      iex> {detalle.motivo, detalle.posicion, detalle.byte}
      {:caracter_de_control, 2, 0}
  """
  @spec a_utf8(binary(), encoding()) :: {:ok, String.t()} | {:error, detalle()}
  def a_utf8(binario, :latin1) when is_binary(binario) do
    case control_en_bytes(binario, 0) do
      nil -> {:ok, :unicode.characters_to_binary(binario, :latin1, :utf8)}
      detalle -> {:error, detalle}
    end
  end

  def a_utf8(binario, :utf8) when is_binary(binario) do
    case primer_byte_invalido(binario) do
      nil -> validar_controles(binario)
      detalle -> {:error, detalle}
    end
  end

  @doc """
  Encoding más probable de un binario.

  `:ascii` significa que ambos encodings dan el mismo resultado, así que la
  pregunta no importa para ese archivo.

      iex> AnchoFijo.Transcodificacion.detectar("SOLO ASCII")
      :ascii
      iex> AnchoFijo.Transcodificacion.detectar("JOSÉ")
      :utf8
      iex> AnchoFijo.Transcodificacion.detectar(<<74, 79, 83, 201>>)
      :latin1
  """
  @spec detectar(binary()) :: :ascii | :utf8 | :latin1
  def detectar(binario) when is_binary(binario) do
    cond do
      ascii?(binario) -> :ascii
      utf8?(binario) -> :utf8
      true -> :latin1
    end
  end

  @doc """
  `true` si todos los bytes están bajo 128.

      iex> AnchoFijo.Transcodificacion.ascii?("ABC")
      true
      iex> AnchoFijo.Transcodificacion.ascii?("ABÇ")
      false
  """
  @spec ascii?(binary()) :: boolean()
  def ascii?(binario) when is_binary(binario) do
    for(<<byte <- binario>>, byte > 127, do: byte) == []
  end

  @doc """
  `true` si el binario es UTF-8 válido.

      iex> AnchoFijo.Transcodificacion.utf8?(<<74, 79, 83, 201>>)
      false
  """
  @spec utf8?(binary()) :: boolean()
  def utf8?(binario) when is_binary(binario), do: String.valid?(binario)

  @doc """
  Ubica el primer byte que rompe UTF-8, o `nil` si el binario está sano.

      iex> AnchoFijo.Transcodificacion.primer_byte_invalido(<<65, 66, 241, 67>>)
      %{motivo: :bytes_invalidos, posicion: 2, byte: 241}

      iex> AnchoFijo.Transcodificacion.primer_byte_invalido("ABC")
      nil
  """
  @spec primer_byte_invalido(binary()) :: detalle() | nil
  def primer_byte_invalido(binario) when is_binary(binario) do
    case :unicode.characters_to_binary(binario, :utf8, :utf8) do
      resultado when is_binary(resultado) -> nil
      {:error, validos, resto} -> detalle(:bytes_invalidos, validos, resto)
      {:incomplete, validos, resto} -> detalle(:secuencia_incompleta, validos, resto)
    end
  end

  @doc """
  Redacta el byte problemático con su posición absoluta en la línea.

  `base` es la posición 1-based donde empieza el binario inspeccionado, de modo
  que el número que sale en el diagnóstico sea el que el usuario puede contar en
  su editor.

      iex> detalle = %{motivo: :bytes_invalidos, posicion: 2, byte: 241}
      iex> AnchoFijo.Transcodificacion.describir_byte(detalle, 11)
      "el byte 0xF1 en la posición 13"
  """
  @spec describir_byte(ubicacion(), pos_integer()) :: String.t()
  def describir_byte(%{posicion: posicion, byte: byte}, base) do
    "el byte 0x#{hex(byte)} en la posición #{base + posicion}"
  end

  @doc """
  Hipótesis de por qué falló la decodificación, según el byte y el encoding declarado.

      iex> detalle = %{motivo: :caracter_de_control, posicion: 4, byte: 0x93}
      iex> AnchoFijo.Transcodificacion.causa_probable(detalle, :latin1)
      "0x93 es un carácter de control en latin-1 pero una comilla en Windows-1252; el archivo probablemente es cp1252"
  """
  @spec causa_probable(detalle(), encoding()) :: String.t()
  def causa_probable(%{motivo: :secuencia_incompleta}, _encoding) do
    "una secuencia UTF-8 quedó cortada a la mitad; si el archivo trae caracteres " <>
      "multibyte, las posiciones del layout no se pueden contar en bytes: " <>
      "pruebe unidad: :caracteres"
  end

  def causa_probable(%{motivo: :caracter_de_control, byte: byte}, :latin1)
      when byte in 0x80..0x9F do
    "0x#{hex(byte)} es un carácter de control en latin-1 pero una comilla en Windows-1252; " <>
      "el archivo probablemente es cp1252"
  end

  def causa_probable(%{motivo: :caracter_de_control, byte: byte}, _encoding) do
    "0x#{hex(byte)} es un carácter de control; puede ser un archivo binario, " <>
      "un terminador de línea inesperado o un campo corrido"
  end

  def causa_probable(%{byte: byte}, :utf8) when byte in 0xA0..0xFF do
    "el byte 0x#{hex(byte)} no es UTF-8 válido pero sí es un carácter latin-1; " <>
      "declare encoding: :latin1 en el layout"
  end

  def causa_probable(%{byte: byte}, encoding) do
    "el byte 0x#{hex(byte)} no corresponde a #{encoding}; revise el encoding declarado"
  end

  defp validar_controles(texto) do
    case control_en_codepoints(texto, 0) do
      nil -> {:ok, texto}
      detalle -> {:error, detalle}
    end
  end

  defp detalle(motivo, validos, resto) do
    %{motivo: motivo, posicion: byte_size(validos), byte: :binary.first(resto)}
  end

  defp control_en_bytes(<<>>, _posicion), do: nil
  defp control_en_bytes(<<?\t, resto::binary>>, posicion), do: control_en_bytes(resto, posicion + 1)

  defp control_en_bytes(<<byte, _resto::binary>>, posicion)
       when byte in 0x00..0x1F or byte in 0x7F..0x9F do
    %{motivo: :caracter_de_control, posicion: posicion, byte: byte}
  end

  defp control_en_bytes(<<_byte, resto::binary>>, posicion),
    do: control_en_bytes(resto, posicion + 1)

  defp control_en_codepoints(<<>>, _posicion), do: nil

  defp control_en_codepoints(<<?\t, resto::binary>>, posicion),
    do: control_en_codepoints(resto, posicion + 1)

  defp control_en_codepoints(<<punto::utf8, _resto::binary>>, posicion)
       when punto in 0x00..0x1F or punto in 0x7F..0x9F do
    %{motivo: :caracter_de_control, posicion: posicion, byte: punto}
  end

  defp control_en_codepoints(<<punto::utf8, resto::binary>>, posicion) do
    control_en_codepoints(resto, posicion + byte_size(<<punto::utf8>>))
  end

  defp hex(byte) do
    byte |> Integer.to_string(16) |> String.pad_leading(2, "0")
  end
end
