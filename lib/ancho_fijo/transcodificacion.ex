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

  Los tres encodings rechazan los caracteres de control (0x00–0x1F menos el
  tabulador, y 0x7F; en UTF-8 y latin-1 también 0x80–0x9F). No es purismo:
  el rango 0x80–0x9F es control en latin-1 pero contiene comillas y guiones
  en Windows-1252, así que encontrarlo ahí casi siempre significa que el
  archivo es cp1252 y no latin-1. Preferimos decirlo a devolver basura
  silenciosa.

  ## Windows-1252

  `:cp1252` es latin-1 más los 27 caracteres que Windows pone en 0x80–0x9F
  (el euro, las comillas tipográficas, los guiones largos, los puntos
  suspensivos): es lo que exportan Excel y Notepad. Los cinco bytes que
  Windows-1252 no define (0x81, 0x8D, 0x8F, 0x90, 0x9D) son un diagnóstico.

      iex> AnchoFijo.Transcodificacion.a_utf8(<<74, 79, 83, 201, 32, 0x93, 88, 0x94>>, :cp1252)
      {:ok, "JOSÉ “X”"}
      iex> AnchoFijo.Transcodificacion.de_utf8("€ 10", :cp1252)
      {:ok, <<0x80, 32, 49, 48>>}
  """

  @typedoc """
  Detalle de una falla de decodificación.

  `:posicion` es el offset 0-based en bytes dentro del binario inspeccionado, y
  `:byte` es el byte —o el codepoint, si el problema es un control en UTF-8—
  que la provocó.
  """
  @type detalle :: %{
          motivo:
            :bytes_invalidos
            | :secuencia_incompleta
            | :continuacion_suelta
            | :caracter_de_control
            | :byte_sin_definir,
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

  @type encoding :: :utf8 | :latin1 | :cp1252

  # Windows-1252 en 0x80–0x9F: byte a punto de código. Lo demás es latin-1.
  @cp1252 %{
    0x80 => 0x20AC,
    0x82 => 0x201A,
    0x83 => 0x0192,
    0x84 => 0x201E,
    0x85 => 0x2026,
    0x86 => 0x2020,
    0x87 => 0x2021,
    0x88 => 0x02C6,
    0x89 => 0x2030,
    0x8A => 0x0160,
    0x8B => 0x2039,
    0x8C => 0x0152,
    0x8E => 0x017D,
    0x91 => 0x2018,
    0x92 => 0x2019,
    0x93 => 0x201C,
    0x94 => 0x201D,
    0x95 => 0x2022,
    0x96 => 0x2013,
    0x97 => 0x2014,
    0x98 => 0x02DC,
    0x99 => 0x2122,
    0x9A => 0x0161,
    0x9B => 0x203A,
    0x9C => 0x0153,
    0x9E => 0x017E,
    0x9F => 0x0178
  }
  @cp1252_inversa Map.new(@cp1252, fn {byte, codepoint} -> {codepoint, byte} end)
  @cp1252_sin_definir [0x81, 0x8D, 0x8F, 0x90, 0x9D]

  @doc "Los bytes de 0x80–0x9F que Windows-1252 define, con su punto de código."
  @spec cp1252() :: %{byte() => pos_integer()}
  def cp1252, do: @cp1252

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

  def a_utf8(binario, :cp1252) when is_binary(binario) do
    case control_en_cp1252(binario, 0) do
      nil -> {:ok, cp1252_a_utf8(binario)}
      detalle -> {:error, detalle}
    end
  end

  # `String.valid?/1` es un BIF y decide el caso común (la línea es UTF-8
  # válido) en una fracción de lo que cuesta recorrerla en Elixir; el
  # recorrido que ubica el byte inválido se hace solo cuando lo hay.
  def a_utf8(binario, :utf8) when is_binary(binario) do
    if String.valid?(binario) do
      validar_controles(binario)
    else
      {:error, primer_byte_invalido(binario)}
    end
  end

  # Un binario ASCII es el mismo en los tres encodings; con algo más, cada
  # byte es un carácter: los de 0x80–0x9F por la tabla, el resto como latin-1.
  defp cp1252_a_utf8(binario) do
    if ascii?(binario),
      do: binario,
      else: for(<<byte <- binario>>, into: "", do: <<Map.get(@cp1252, byte, byte)::utf8>>)
  end

  @doc """
  El inverso de `a_utf8/2`: un texto UTF-8 en el encoding pedido, o el primer
  carácter que ese encoding no tiene, con su posición 1-based.

      iex> AnchoFijo.Transcodificacion.de_utf8("año", :latin1)
      {:ok, <<97, 241, 111>>}
      iex> AnchoFijo.Transcodificacion.de_utf8("a → b", :cp1252)
      {:error, %{posicion: 3, caracter: "→"}}
  """
  @spec de_utf8(String.t(), encoding()) ::
          {:ok, binary()} | {:error, %{posicion: pos_integer(), caracter: String.t()}}
  def de_utf8(texto, :utf8) when is_binary(texto), do: {:ok, texto}

  def de_utf8(texto, :latin1) when is_binary(texto) do
    case Enum.find_index(String.to_charlist(texto), &(&1 > 255)) do
      nil -> {:ok, :unicode.characters_to_binary(texto, :utf8, :latin1)}
      indice -> {:error, %{posicion: indice + 1, caracter: caracter_en(texto, indice)}}
    end
  end

  def de_utf8(texto, :cp1252) when is_binary(texto) do
    texto
    |> String.to_charlist()
    |> Enum.reduce_while({:ok, [], 0}, fn codepoint, {:ok, bytes, indice} ->
      case byte_cp1252(codepoint) do
        nil -> {:halt, {:error, %{posicion: indice + 1, caracter: caracter_en(texto, indice)}}}
        byte -> {:cont, {:ok, [byte | bytes], indice + 1}}
      end
    end)
    |> case do
      {:ok, bytes, _indice} -> {:ok, bytes |> Enum.reverse() |> :binary.list_to_bin()}
      error -> error
    end
  end

  defp byte_cp1252(codepoint) when codepoint < 0x80 or codepoint in 0xA0..0xFF, do: codepoint
  defp byte_cp1252(codepoint), do: Map.get(@cp1252_inversa, codepoint)

  defp caracter_en(texto, indice),
    do: texto |> String.to_charlist() |> Enum.at(indice) |> List.wrap() |> List.to_string()

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
  @spec detectar(binary()) :: :ascii | :utf8 | :latin1 | :cp1252
  def detectar(binario) when is_binary(binario) do
    cond do
      ascii?(binario) -> :ascii
      utf8?(binario) -> :utf8
      cp1252?(binario) -> :cp1252
      true -> :latin1
    end
  end

  @doc """
  `true` si el binario trae algún byte de 0x80–0x9F que Windows-1252 define
  (una comilla, un guion largo, el euro): en latin-1 serían controles, así
  que el archivo es cp1252.

      iex> AnchoFijo.Transcodificacion.cp1252?(<<74, 79, 83, 201, 32, 0x93>>)
      true
      iex> AnchoFijo.Transcodificacion.cp1252?(<<74, 79, 83, 201>>)
      false
  """
  @spec cp1252?(binary()) :: boolean()
  def cp1252?(binario) when is_binary(binario) do
    :binary.match(binario, Enum.map(Map.keys(@cp1252), &<<&1>>)) != :nomatch
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

  # Si el binario es ASCII imprimible (más tabulador): cada tramo suyo es
  # UTF-8 válido y latin-1 válido sin un solo carácter de control, así que
  # `a_utf8/2` sobre cualquier campo de esa línea devolvería el tramo tal
  # cual. El parser lo decide una vez por línea en vez de una vez por campo.
  @doc false
  @spec ascii_limpio?(binary()) :: boolean()
  def ascii_limpio?(<<byte, resto::binary>>) when byte >= 32 and byte < 127,
    do: ascii_limpio?(resto)

  def ascii_limpio?(<<?\t, resto::binary>>), do: ascii_limpio?(resto)
  def ascii_limpio?(<<>>), do: true
  def ascii_limpio?(_otro), do: false

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
      {:error, validos, resto} -> detalle(motivo_del_byte(resto), validos, resto)
      {:incomplete, validos, resto} -> detalle(:secuencia_incompleta, validos, resto)
    end
  end

  # Un byte 0x80-0xBF suelto es la continuación de un carácter multibyte que
  # empezó antes: distinto de un byte latin-1 cualquiera, y con otra causa.
  defp motivo_del_byte(<<byte, _::binary>>) when byte in 0x80..0xBF, do: :continuacion_suelta
  defp motivo_del_byte(_resto), do: :bytes_invalidos

  @doc """
  `true` si el binario contiene al menos una secuencia UTF-8 multibyte
  válida, aunque el resto no sea UTF-8. Es la señal de un archivo con
  encodings mezclados por campo: latin-1 en unos, UTF-8 en otros.

      iex> AnchoFijo.Transcodificacion.multibyte_utf8?(<<74, 79, 83, 201, 32>> <> "operación")
      true
      iex> AnchoFijo.Transcodificacion.multibyte_utf8?(<<74, 79, 83, 201>>)
      false
  """
  @spec multibyte_utf8?(binary()) :: boolean()
  def multibyte_utf8?(<<lead, _::binary>> = binario) when lead in 0xC2..0xF4 do
    largo = if lead < 0xE0, do: 2, else: if(lead < 0xF0, do: 3, else: 4)

    if byte_size(binario) >= largo and String.valid?(binary_part(binario, 0, largo)) do
      true
    else
      binario |> binary_part(1, byte_size(binario) - 1) |> multibyte_utf8?()
    end
  end

  def multibyte_utf8?(<<_, resto::binary>>), do: multibyte_utf8?(resto)
  def multibyte_utf8?(<<>>), do: false

  @doc """
  Detecta la doble codificación: UTF-8 que alguien decodificó como latin-1 y
  volvió a codificar, el `operaciÃ³n` de los catálogos que dejan de calzar.
  Devuelve el texto reparado, o `:no` si el texto no tiene esa forma.

  La prueba es exacta y no una lista de pares sospechosos: el texto,
  reinterpretado como bytes latin-1, tiene que ser UTF-8 válido con al
  menos un carácter multibyte, **y todos de dos bytes**. Un texto latino
  (español, portugués, francés) doblemente codificado es siempre `Ã` o `Â`
  seguido de un carácter de continuación, es decir secuencias de dos bytes;
  una secuencia de tres o cuatro (`ñ···`, que reinterpretado es `F1 B7 B7
  B7`, un ideograma válido) es texto latin-1 legítimo con mala suerte, no
  doble codificación. `"JOSÉ"` tampoco lo es (0xC9 seguido de nada que lo
  continúe) y queda como está.

      iex> AnchoFijo.Transcodificacion.doble_codificacion("operaciÃ³n")
      {:ok, "operación"}
      iex> AnchoFijo.Transcodificacion.doble_codificacion("JOSÉ")
      :no
      iex> AnchoFijo.Transcodificacion.doble_codificacion("ñ···")
      :no
      iex> AnchoFijo.Transcodificacion.doble_codificacion("ASCII")
      :no
  """
  @spec doble_codificacion(String.t()) :: {:ok, String.t()} | :no
  def doble_codificacion(texto) when is_binary(texto) do
    if ascii?(texto),
      do: :no,
      else: reinterpretar(:unicode.characters_to_binary(texto, :utf8, :latin1))
  end

  defp reinterpretar(bytes) when is_binary(bytes) do
    if String.valid?(bytes) and multibyte_utf8?(bytes) and solo_secuencias_de_dos_bytes?(bytes),
      do: {:ok, bytes},
      else: :no
  end

  defp reinterpretar(_no_cabe_en_latin1), do: :no

  # Un byte de 0xE0 en adelante inicia una secuencia de tres o cuatro bytes:
  # en texto latino doblemente codificado no aparece nunca.
  defp solo_secuencias_de_dos_bytes?(<<byte, _resto::binary>>) when byte >= 0xE0, do: false

  defp solo_secuencias_de_dos_bytes?(<<_byte, resto::binary>>),
    do: solo_secuencias_de_dos_bytes?(resto)

  defp solo_secuencias_de_dos_bytes?(<<>>), do: true

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
      "0x93 es un carácter de control en latin-1 pero una comilla en Windows-1252; el archivo probablemente es cp1252: declare encoding: :cp1252 en el layout"
  """
  @spec causa_probable(detalle(), encoding()) :: String.t()
  def causa_probable(%{motivo: :secuencia_incompleta}, _encoding) do
    "una secuencia UTF-8 quedó cortada a la mitad; si el archivo trae caracteres " <>
      "multibyte, las posiciones del layout no se pueden contar en bytes: " <>
      "pruebe unidad: :caracteres"
  end

  def causa_probable(%{motivo: :continuacion_suelta, posicion: 0, byte: byte}, _encoding) do
    "el campo empieza con 0x#{hex(byte)}, la continuación de un carácter multibyte que " <>
      "empezó en el campo anterior: las posiciones en bytes cortan el texto UTF-8 a la mitad; " <>
      "pruebe unidad: :caracteres"
  end

  # Un byte suelto de 0x80–0x9F que Windows-1252 define: en un archivo UTF-8
  # sería la continuación de un multibyte sin inicio, pero lo que exportan
  # Excel y Notepad son comillas y guiones.
  def causa_probable(%{motivo: :continuacion_suelta, byte: byte}, :utf8)
      when is_map_key(@cp1252, byte) do
    "el byte 0x#{hex(byte)} es la continuación de un carácter multibyte sin su inicio; o el " <>
      "archivo es Windows-1252, donde ese byte es el euro, una comilla o un guion (lo que " <>
      "exportan Excel y Notepad): declare encoding: :cp1252 en el layout"
  end

  def causa_probable(%{motivo: :continuacion_suelta, byte: byte}, _encoding) do
    "el byte 0x#{hex(byte)} es la continuación de un carácter multibyte sin su inicio; " <>
      "el texto UTF-8 quedó cortado o el campo está corrido"
  end

  def causa_probable(%{motivo: :caracter_de_control, byte: byte}, :latin1)
      when byte in 0x80..0x9F do
    "0x#{hex(byte)} es un carácter de control en latin-1 pero una comilla en Windows-1252; " <>
      "el archivo probablemente es cp1252: declare encoding: :cp1252 en el layout"
  end

  def causa_probable(%{motivo: :byte_sin_definir, byte: byte}, _encoding) do
    "0x#{hex(byte)} no está definido en Windows-1252; el archivo puede ser de otro " <>
      "codepage o traer basura en ese campo"
  end

  def causa_probable(%{motivo: :caracter_de_control, byte: 0x1A}, _encoding) do
    "0x1A es la marca de fin de archivo de DOS (Ctrl-Z); si es la última línea del " <>
      "archivo no es un registro: omitir_vacias: true (el default) la omite"
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

  # En Windows-1252 los controles son los de ASCII y 0x7F; de 0x80–0x9F, los
  # cinco bytes que no define.
  defp control_en_cp1252(<<>>, _posicion), do: nil

  defp control_en_cp1252(<<?\t, resto::binary>>, posicion),
    do: control_en_cp1252(resto, posicion + 1)

  defp control_en_cp1252(<<byte, _resto::binary>>, posicion)
       when byte in 0x00..0x1F or byte == 0x7F,
       do: %{motivo: :caracter_de_control, posicion: posicion, byte: byte}

  defp control_en_cp1252(<<byte, _resto::binary>>, posicion) when byte in @cp1252_sin_definir,
    do: %{motivo: :byte_sin_definir, posicion: posicion, byte: byte}

  defp control_en_cp1252(<<_byte, resto::binary>>, posicion),
    do: control_en_cp1252(resto, posicion + 1)

  # Sobre un binario ya validado como UTF-8, los únicos controles que no son
  # ASCII son U+0080..U+009F, que se codifican como 0xC2 seguido de
  # 0x80..0x9F. Un recorrido por bytes alcanza y cuesta la mitad que
  # decodificar cada punto de código.
  defp control_en_codepoints(<<>>, _posicion), do: nil

  defp control_en_codepoints(<<?\t, resto::binary>>, posicion),
    do: control_en_codepoints(resto, posicion + 1)

  defp control_en_codepoints(<<byte, _resto::binary>>, posicion)
       when byte in 0x00..0x1F or byte == 0x7F do
    %{motivo: :caracter_de_control, posicion: posicion, byte: byte}
  end

  defp control_en_codepoints(<<0xC2, byte, _resto::binary>>, posicion) when byte in 0x80..0x9F do
    %{motivo: :caracter_de_control, posicion: posicion, byte: byte}
  end

  defp control_en_codepoints(<<_byte, resto::binary>>, posicion),
    do: control_en_codepoints(resto, posicion + 1)

  defp hex(byte) do
    byte |> Integer.to_string(16) |> String.pad_leading(2, "0")
  end
end
