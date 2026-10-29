defmodule AnchoFijo.Json do
  @moduledoc false
  # JSON a mano, sin dependencia: lo que se codifica tiene una forma conocida
  # (mapas, listas, binarios, átomos, enteros, booleanos y nil) y un encoder
  # para eso son treinta líneas. Agregar Jason al paquete por dos tareas Mix
  # sería la primera dependencia de runtime de la librería. Los tests validan
  # la salida con un decoder de verdad, que sí es una dependencia de test.

  @spec codificar(term()) :: String.t()
  def codificar(valor) when is_map(valor) and not is_struct(valor) do
    valor
    |> Enum.sort()
    |> Enum.map_join(",", fn {clave, valor} ->
      codificar(clave_json(clave)) <> ":" <> codificar(valor)
    end)
    |> then(&("{" <> &1 <> "}"))
  end

  def codificar(valor) when is_list(valor),
    do: "[" <> Enum.map_join(valor, ",", &codificar/1) <> "]"

  def codificar(nil), do: "null"
  def codificar(true), do: "true"
  def codificar(false), do: "false"
  def codificar(valor) when is_atom(valor), do: codificar(Atom.to_string(valor))
  def codificar(valor) when is_integer(valor), do: Integer.to_string(valor)
  def codificar(valor) when is_binary(valor), do: "\"" <> escapar(valor) <> "\""
  def codificar(valor), do: codificar(inspect(valor))

  @doc false
  # El decodificador, para leer un layout en JSON desde las tareas Mix y
  # desde `Layout.desde_json/1` sin dependencia. Es JSON completo (objetos,
  # listas, strings con escapes y \\uXXXX, números, true/false/null), sin
  # extensiones: un error dice en qué byte y por qué.
  @spec decodificar(binary()) :: {:ok, term()} | {:error, String.t()}
  def decodificar(texto) when is_binary(texto) do
    case valor(saltar(texto)) do
      {:ok, v, resto} ->
        case saltar(resto) do
          "" ->
            {:ok, v}

          sobra ->
            {:error,
             "texto después del valor JSON: #{inspect(binary_part(sobra, 0, min(byte_size(sobra), 20)))}"}
        end

      {:error, _} = error ->
        error
    end
  end

  defp saltar(<<c, resto::binary>>) when c in [?\s, ?\t, ?\n, ?\r], do: saltar(resto)
  defp saltar(resto), do: resto

  defp valor("null" <> resto), do: {:ok, nil, resto}
  defp valor("true" <> resto), do: {:ok, true, resto}
  defp valor("false" <> resto), do: {:ok, false, resto}
  defp valor(<<?", resto::binary>>), do: cadena(resto, [])
  defp valor(<<?[, resto::binary>>), do: lista(saltar(resto), [])
  defp valor(<<?{, resto::binary>>), do: objeto(saltar(resto), %{})
  defp valor(""), do: {:error, "JSON incompleto: se esperaba un valor"}
  defp valor(texto), do: numero(texto)

  defp cadena(<<?", resto::binary>>, acumulado),
    do: {:ok, acumulado |> Enum.reverse() |> IO.iodata_to_binary(), resto}

  defp cadena(<<?\\, ?", resto::binary>>, acc), do: cadena(resto, [?" | acc])
  defp cadena(<<?\\, ?\\, resto::binary>>, acc), do: cadena(resto, [?\\ | acc])
  defp cadena(<<?\\, ?/, resto::binary>>, acc), do: cadena(resto, [?/ | acc])
  defp cadena(<<?\\, ?b, resto::binary>>, acc), do: cadena(resto, [?\b | acc])
  defp cadena(<<?\\, ?f, resto::binary>>, acc), do: cadena(resto, [?\f | acc])
  defp cadena(<<?\\, ?n, resto::binary>>, acc), do: cadena(resto, [?\n | acc])
  defp cadena(<<?\\, ?r, resto::binary>>, acc), do: cadena(resto, [?\r | acc])
  defp cadena(<<?\\, ?t, resto::binary>>, acc), do: cadena(resto, [?\t | acc])

  defp cadena(<<?\\, ?u, alto::binary-size(4), ?\\, ?u, bajo::binary-size(4), resto::binary>>, acc) do
    with {:ok, a} when a in 0xD800..0xDBFF <- hex4(alto),
         {:ok, b} when b in 0xDC00..0xDFFF <- hex4(bajo) do
      cadena(resto, [<<0x10000 + (a - 0xD800) * 0x400 + (b - 0xDC00)::utf8>> | acc])
    else
      _ -> escape_u(alto, <<?\\, ?u, bajo::binary, resto::binary>>, acc)
    end
  end

  defp cadena(<<?\\, ?u, hex::binary-size(4), resto::binary>>, acc), do: escape_u(hex, resto, acc)
  defp cadena(<<?\\, _::binary>>, _acc), do: {:error, "escape inválido en un string JSON"}
  defp cadena(<<c::utf8, resto::binary>>, acc), do: cadena(resto, [<<c::utf8>> | acc])
  defp cadena(_, _acc), do: {:error, "string JSON sin cerrar o con bytes inválidos"}

  # Un `\u` fuera de los surrogates es un punto de código. Uno dentro sin su
  # par no es un carácter, y cuatro dígitos que no son hexadecimales tampoco:
  # las dos cosas son un error del JSON, que se devuelve como todos los demás.
  # `Integer.parse/2` no sirve acá: acepta un signo (`-001`), y `<<-1::utf8>>`
  # es un ArgumentError.
  defp escape_u(hex, resto, acc) do
    case hex4(hex) do
      {:ok, n} when n < 0xD800 or n > 0xDFFF ->
        cadena(resto, [<<n::utf8>> | acc])

      {:ok, _surrogate} ->
        {:error, "escape \\u#{hex} inválido: un surrogate sin su par"}

      :error ->
        {:error, "escape \\u#{hex} inválido: se esperaban cuatro dígitos hexadecimales"}
    end
  end

  defp hex4(hex) do
    if hexadecimal?(hex), do: {:ok, String.to_integer(hex, 16)}, else: :error
  end

  defp hexadecimal?(<<>>), do: true

  defp hexadecimal?(<<c, resto::binary>>) when c in ?0..?9 or c in ?a..?f or c in ?A..?F,
    do: hexadecimal?(resto)

  defp hexadecimal?(_otro), do: false

  defp lista(<<?], resto::binary>>, acumulado), do: {:ok, Enum.reverse(acumulado), resto}

  defp lista(texto, acumulado) do
    with {:ok, v, resto} <- valor(saltar(texto)) do
      case saltar(resto) do
        <<?,, resto::binary>> -> lista(saltar(resto), [v | acumulado])
        <<?], resto::binary>> -> {:ok, Enum.reverse([v | acumulado]), resto}
        _ -> {:error, "lista JSON sin coma ni cierre"}
      end
    end
  end

  defp objeto(<<?}, resto::binary>>, acumulado), do: {:ok, acumulado, resto}

  defp objeto(<<?", resto::binary>>, acumulado) do
    with {:ok, clave, resto} <- cadena(resto, []),
         <<?:, resto::binary>> <- saltar(resto),
         {:ok, v, resto} <- valor(saltar(resto)) do
      case saltar(resto) do
        <<?,, resto::binary>> -> objeto(saltar(resto), Map.put(acumulado, clave, v))
        <<?}, resto::binary>> -> {:ok, Map.put(acumulado, clave, v), resto}
        _ -> {:error, "objeto JSON sin coma ni cierre"}
      end
    else
      {:error, _} = error -> error
      _ -> {:error, "objeto JSON: se esperaba \":\" después de la clave"}
    end
  end

  defp objeto(_texto, _acumulado), do: {:error, "objeto JSON: se esperaba una clave entre comillas"}

  defp numero(texto) do
    case Regex.run(~r/\A-?\d+(\.\d+)?([eE][+-]?\d+)?/, texto, capture: :first) do
      [entero] ->
        largo = byte_size(entero)
        resto = binary_part(texto, largo, byte_size(texto) - largo)

        if String.contains?(entero, [".", "e", "E"]),
          do: flotante(entero, resto),
          else: {:ok, String.to_integer(entero), resto}

      _ ->
        {:error,
         "valor JSON inválido: #{inspect(binary_part(texto, 0, min(byte_size(texto), 20)))}"}
    end
  end

  # String.to_float exige un punto: "1e3" se lee como "1.0e3". Un exponente
  # que no cabe en un float (`1e999`) es un ArgumentError de la VM y acá un
  # error del JSON, como cualquier otro.
  defp flotante(entero, resto) do
    {:ok, String.to_float(normalizar_float(entero)), resto}
  rescue
    ArgumentError -> {:error, "número JSON fuera de rango: #{entero}"}
  end

  defp normalizar_float(texto),
    do: if(String.contains?(texto, "."), do: texto, else: String.replace(texto, ~r/[eE]/, ".0e"))

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
