defmodule AnchoFijo.Tipo.Patron do
  @moduledoc false
  # El patrón de un campo de fecha, hora o fecha y hora: una lista de piezas,
  # cada una un token (`AAAA`, `MM`, `DD`, `HH`...) o un literal (`/`, `-`,
  # `:`, un espacio). Lo comparten `Tipo.Fecha`, `Tipo.Hora` y
  # `Tipo.FechaHora`: leer es cortar el texto pieza por pieza, escribir es
  # pegar las partes en el mismo orden.
  #
  # Los tokens: `AAAA` y `AA` (año de cuatro y de dos dígitos), `MM` (mes, o
  # minuto si viene después de `HH`), `DD` (día), `DDD` (día del año, fecha
  # juliana), `HH`, `SS`. Cualquier otro carácter que no sea una de esas
  # letras es un literal que tiene que estar tal cual en la línea.

  @nombrados %{
    aaaammdd: "AAAAMMDD",
    ddmmaaaa: "DDMMAAAA",
    mmddaaaa: "MMDDAAAA",
    aammdd: "AAMMDD",
    ddmmaa: "DDMMAA",
    mmddaa: "MMDDAA",
    aaaaddd: "AAAADDD",
    aaddd: "AADDD",
    hhmmss: "HHMMSS",
    hhmm: "HHMM",
    aaaammddhhmmss: "AAAAMMDDHHMMSS",
    aaaammddhhmm: "AAAAMMDDHHMM",
    ddmmaaaahhmmss: "DDMMAAAAHHMMSS",
    ddmmaaaahhmm: "DDMMAAAAHHMM"
  }

  @letras ~c"AMDHS"
  @pivote_default 2000

  @type parte :: :anio | :anio2 | :mes | :dia | :dia_del_anio | :hora | :minuto | :segundo
  @type pieza :: {:token, parte(), pos_integer()} | {:literal, String.t()}
  @type t :: %{
          texto: String.t(),
          piezas: [pieza()],
          largo: pos_integer(),
          largo_bytes: pos_integer(),
          partes: [parte()]
        }

  @doc "Los formatos con nombre, para la documentación y los mensajes."
  @spec nombrados() :: %{atom() => String.t()}
  def nombrados, do: @nombrados

  @doc "El pivote por default para los años de dos dígitos."
  @spec pivote_default() :: pos_integer()
  def pivote_default, do: @pivote_default

  @doc """
  Compila un formato con nombre (`:aaaammdd`) o un patrón explícito
  (`"DD/MM/AA"`). Devuelve `{:ok, patron}` o `{:error, descripcion}`.
  """
  @spec compilar(term()) :: {:ok, t()} | {:error, String.t()}
  def compilar(formato) when is_atom(formato) and not is_nil(formato) do
    case Map.fetch(@nombrados, formato) do
      {:ok, texto} -> compilar(texto)
      :error -> {:error, "un formato con nombre o un patrón de tokens"}
    end
  end

  def compilar(texto) when is_binary(texto) and texto != "" do
    with {:ok, piezas} <- tokenizar(texto, [], false),
         partes = for({:token, parte, _} <- piezas, do: parte),
         :ok <- sin_repetidos(partes) do
      {:ok,
       %{
         texto: texto,
         piezas: piezas,
         largo: String.length(texto),
         largo_bytes: byte_size(texto),
         partes: partes
       }}
    end
  end

  def compilar(_otro), do: {:error, "un formato con nombre o un patrón de tokens"}

  @doc """
  El patrón ya compilado de un campo: el que `Campo.nuevo/1` guardó en
  `:formato_compilado`, o el de `:formato` si el campo se armó sin pasar
  por ahí. Compilar tokeniza y arma un mapa; hacerlo en cada lectura era
  la mitad del costo de un campo de fecha.
  """
  @spec de(map()) :: t()
  def de(%{formato_compilado: %{piezas: _} = patron}), do: patron

  def de(%{formato: formato}) do
    {:ok, patron} = compilar(formato)
    patron
  end

  defp tokenizar("", piezas, _con_hora?), do: {:ok, Enum.reverse(piezas)}

  defp tokenizar("AAAA" <> resto, piezas, con_hora?),
    do: tokenizar(resto, [{:token, :anio, 4} | piezas], con_hora?)

  defp tokenizar("AA" <> resto, piezas, con_hora?),
    do: tokenizar(resto, [{:token, :anio2, 2} | piezas], con_hora?)

  defp tokenizar("DDD" <> resto, piezas, con_hora?),
    do: tokenizar(resto, [{:token, :dia_del_anio, 3} | piezas], con_hora?)

  defp tokenizar("DD" <> resto, piezas, con_hora?),
    do: tokenizar(resto, [{:token, :dia, 2} | piezas], con_hora?)

  defp tokenizar("HH" <> resto, piezas, _con_hora?),
    do: tokenizar(resto, [{:token, :hora, 2} | piezas], true)

  defp tokenizar("MM" <> resto, piezas, true),
    do: tokenizar(resto, [{:token, :minuto, 2} | piezas], true)

  defp tokenizar("MM" <> resto, piezas, false),
    do: tokenizar(resto, [{:token, :mes, 2} | piezas], false)

  defp tokenizar("SS" <> resto, piezas, con_hora?),
    do: tokenizar(resto, [{:token, :segundo, 2} | piezas], con_hora?)

  defp tokenizar(<<letra::utf8, _::binary>>, _piezas, _con_hora?) when letra in @letras do
    {:error,
     "tokens AAAA, AA, MM, DD, DDD, HH, SS y literales; #{inspect(<<letra::utf8>>)} suelto no es un token"}
  end

  defp tokenizar(<<caracter::utf8, resto::binary>>, piezas, con_hora?),
    do: tokenizar(resto, [{:literal, <<caracter::utf8>>} | piezas], con_hora?)

  defp sin_repetidos(partes) do
    case partes -- Enum.uniq(partes) do
      [] -> :ok
      [repetida | _] -> {:error, "cada token una sola vez; #{describir(repetida)} se repite"}
    end
  end

  @doc "Si el patrón tiene las partes de una fecha: año con mes y día, o con día del año."
  @spec fecha?(t()) :: boolean()
  def fecha?(%{partes: partes}) do
    anio? = :anio in partes or :anio2 in partes
    anio? and ((:mes in partes and :dia in partes) or :dia_del_anio in partes)
  end

  @doc "Si el patrón tiene las partes de una hora: hora y minuto."
  @spec hora?(t()) :: boolean()
  def hora?(%{partes: partes}), do: :hora in partes and :minuto in partes

  @doc "Si alguna parte es de fecha."
  @spec con_fecha?(t()) :: boolean()
  def con_fecha?(%{partes: partes}),
    do: Enum.any?(partes, &(&1 in [:anio, :anio2, :mes, :dia, :dia_del_anio]))

  @doc "Si alguna parte es de hora."
  @spec con_hora?(t()) :: boolean()
  def con_hora?(%{partes: partes}), do: Enum.any?(partes, &(&1 in [:hora, :minuto, :segundo]))

  @doc """
  Si el texto es la forma de "sin dato" de estos campos: vacío, o solo
  ceros donde van dígitos y los literales en su lugar.
  """
  @spec nulo?(t(), String.t()) :: boolean()
  def nulo?(_patron, ""), do: true

  def nulo?(%{piezas: piezas}, texto) do
    case cortar(piezas, texto, []) do
      {:ok, trozos} -> Enum.all?(trozos, fn {_parte, trozo} -> solo_ceros?(trozo) end)
      :error -> false
    end
  end

  defp solo_ceros?(<<?0, resto::binary>>), do: solo_ceros?(resto)
  defp solo_ceros?(""), do: true
  defp solo_ceros?(_otro), do: false

  @doc """
  Lee el texto según el patrón. Devuelve las partes como mapa de enteros, o
  `{:error, causa}` cuando el largo no es el del patrón, un literal no está
  donde debe o un tramo no es numérico. Un año de dos dígitos se expande con
  el pivote.
  """
  @spec leer(t(), String.t(), pos_integer() | nil) :: {:ok, map()} | {:error, String.t()}
  def leer(%{} = patron, texto, pivote) do
    case cortar_por_bytes(patron, texto) do
      {:ok, trozos} ->
        case convertir(trozos, pivote) do
          {:ok, partes} -> {:ok, partes}
          {:error, _causa} -> leer_por_grafemas(patron, texto, pivote)
        end

      :error ->
        leer_por_grafemas(patron, texto, pivote)
    end
  end

  @doc """
  `nulo?/2` y `leer/3` en un solo corte: `:nulo` si el texto es la forma de
  "sin dato", y si no, lo que `leer/3` devuelve.
  """
  @spec leer_o_nulo(t(), String.t(), pos_integer() | nil) ::
          :nulo | {:ok, map()} | {:error, String.t()}
  def leer_o_nulo(_patron, "", _pivote), do: :nulo

  def leer_o_nulo(%{} = patron, texto, pivote) do
    case cortar_por_bytes(patron, texto) do
      {:ok, trozos} -> nulo_o_partes(trozos, patron, texto, pivote)
      :error -> nulo_o_partes(:error, patron, texto, pivote)
    end
  end

  defp nulo_o_partes(:error, patron, texto, pivote) do
    if nulo?(patron, texto), do: :nulo, else: leer_por_grafemas(patron, texto, pivote)
  end

  defp nulo_o_partes(trozos, patron, texto, pivote) do
    if Enum.all?(trozos, fn {_parte, trozo} -> solo_ceros?(trozo) end),
      do: :nulo,
      else: con_fallback(convertir(trozos, pivote), patron, texto, pivote)
  end

  defp con_fallback({:ok, partes}, _patron, _texto, _pivote), do: {:ok, partes}

  defp con_fallback({:error, _}, patron, texto, pivote),
    do: leer_por_grafemas(patron, texto, pivote)

  # El camino rápido: con un patrón ASCII (todos lo son salvo que un literal
  # no lo sea) y un texto que mide en bytes lo que el patrón, los tokens se
  # cortan con `binary_part/3` y no hay que contar grafemas. Si algo no
  # cuadra, el camino por grafemas decide y redacta el mensaje: los dos dan
  # exactamente el mismo resultado cuando el texto es válido, y el lento es
  # el que distingue "mide distinto" de "no es numérico".
  defp cortar_por_bytes(%{piezas: piezas, largo: largo, largo_bytes: largo}, texto)
       when byte_size(texto) == largo,
       do: cortar_bytes(piezas, texto, 0, [])

  defp cortar_por_bytes(_patron, _texto), do: :error

  defp cortar_bytes([], _texto, _desde, trozos), do: {:ok, Enum.reverse(trozos)}

  defp cortar_bytes([{:literal, literal} | piezas], texto, desde, trozos) do
    largo = byte_size(literal)

    if binary_part(texto, desde, largo) == literal,
      do: cortar_bytes(piezas, texto, desde + largo, trozos),
      else: :error
  end

  defp cortar_bytes([{:token, parte, ancho} | piezas], texto, desde, trozos),
    do:
      cortar_bytes(piezas, texto, desde + ancho, [
        {parte, binary_part(texto, desde, ancho)} | trozos
      ])

  defp leer_por_grafemas(%{piezas: piezas, largo: largo} = patron, texto, pivote) do
    if String.length(texto) != largo do
      {:error,
       "se esperaban #{largo} posiciones (#{patron.texto}); el campo puede estar corrido " <>
         "o traer otros separadores"}
    else
      case cortar(piezas, texto, []) do
        {:ok, trozos} -> convertir(trozos, pivote)
        :error -> {:error, "los separadores no están donde el patrón #{patron.texto} los espera"}
      end
    end
  end

  defp cortar([], "", trozos), do: {:ok, Enum.reverse(trozos)}

  # `<<^literal::binary, resto::binary>>` recién compila en Elixir 1.16, y
  # `binary-size(^largo)` también; el paquete soporta 1.14, así que el
  # literal se compara con `binary_part/3`.
  defp cortar([{:literal, literal} | piezas], texto, trozos) do
    largo = byte_size(literal)

    if byte_size(texto) >= largo and binary_part(texto, 0, largo) == literal do
      cortar(piezas, binary_part(texto, largo, byte_size(texto) - largo), trozos)
    else
      :error
    end
  end

  defp cortar([{:token, parte, ancho} | piezas], texto, trozos) do
    case String.split_at(texto, ancho) do
      {trozo, resto} when byte_size(trozo) > 0 -> cortar(piezas, resto, [{parte, trozo} | trozos])
      _otro -> :error
    end
  end

  defp cortar(_piezas, _texto, _trozos), do: :error

  defp convertir(trozos, pivote) do
    Enum.reduce_while(trozos, {:ok, %{}}, fn {parte, trozo}, {:ok, partes} ->
      if AnchoFijo.Tipo.solo_digitos?(trozo),
        do: {:cont, {:ok, Map.put(partes, parte, String.to_integer(trozo))}},
        else: {:halt, {:error, "#{describir(parte)} trae #{inspect(trozo)}, que no es numérico"}}
    end)
    |> case do
      {:ok, %{anio2: dos} = partes} ->
        {:ok, partes |> Map.delete(:anio2) |> Map.put(:anio, expandir(dos, pivote))}

      otro ->
        otro
    end
  end

  # El pivote es el primer año de la ventana de cien: con 2000, "24" es 2024
  # y "99" es 2099; con 1970, "69" es 2069 y "70" es 1970.
  defp expandir(dos, pivote) do
    pivote = pivote || @pivote_default
    siglo = pivote - rem(pivote, 100)
    anio = siglo + dos
    if anio < pivote, do: anio + 100, else: anio
  end

  @doc """
  Escribe las partes según el patrón. `{:error, causa}` si un año no cabe
  en dos dígitos con el pivote.
  """
  @spec escribir(t(), map(), pos_integer() | nil) :: {:ok, String.t()} | {:error, String.t()}
  def escribir(%{piezas: piezas}, partes, pivote) do
    Enum.reduce_while(piezas, {:ok, []}, fn
      {:literal, literal}, {:ok, acumulado} ->
        {:cont, {:ok, [literal | acumulado]}}

      {:token, :anio2, 2}, {:ok, acumulado} ->
        pivote = pivote || @pivote_default
        anio = Map.fetch!(partes, :anio)

        if anio >= pivote and anio < pivote + 100,
          do: {:cont, {:ok, [digitos(rem(anio, 100), 2) | acumulado]}},
          else:
            {:halt,
             {:error,
              "el año #{anio} no cabe en dos dígitos con pivote #{pivote} " <>
                "(ventana #{pivote}-#{pivote + 99}); declare :pivote"}}

      {:token, parte, ancho}, {:ok, acumulado} ->
        {:cont, {:ok, [digitos(Map.fetch!(partes, parte), ancho) | acumulado]}}
    end)
    |> case do
      {:ok, acumulado} -> {:ok, acumulado |> Enum.reverse() |> IO.iodata_to_binary()}
      error -> error
    end
  end

  # Dígitos ASCII: se completan con ceros por bytes, sin pasar por grafemas.
  defp digitos(numero, ancho) do
    texto = Integer.to_string(numero)
    :binary.copy("0", max(ancho - byte_size(texto), 0)) <> texto
  end

  @doc "El nombre de una parte, para los mensajes."
  @spec describir(parte()) :: String.t()
  def describir(:anio), do: "el año"
  def describir(:anio2), do: "el año de dos dígitos"
  def describir(:mes), do: "el mes"
  def describir(:dia), do: "el día"
  def describir(:dia_del_anio), do: "el día del año"
  def describir(:hora), do: "la hora"
  def describir(:minuto), do: "el minuto"
  def describir(:segundo), do: "el segundo"
end
