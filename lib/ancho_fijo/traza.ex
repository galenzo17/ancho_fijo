defmodule AnchoFijo.Traza do
  @moduledoc """
  De dónde salió cada registro, y qué archivo era.

  Cuando el banco rechaza una nómina de 40.000 líneas, la conversación es "el
  registro del beneficiario X está mal", y lo primero que se pide es volver
  del dato al lugar físico del archivo del que salió. Con `traza: true`,
  `AnchoFijo.parsear/3` y `AnchoFijo.stream/3` agregan a cada registro la
  clave `:__traza__` con este struct:

      iex> layout = AnchoFijo.Layout.nuevo!(campos: [[nombre: :codigo, largo: 3, tipo: :entero]])
      iex> contenido = "001\\r\\n002\\r\\n"
      iex> {:ok, [_, registro], []} = AnchoFijo.parsear(layout, contenido, traza: true)
      iex> registro.__traza__
      %AnchoFijo.Traza{linea: 2, offset: 5, largo: 3}
      iex> AnchoFijo.Traza.linea_original(registro.__traza__, contenido)
      "002"

    * `:linea` — número de línea, 1-based, contando desde la primera del
      archivo (las que `:saltar` omite también cuentan).
    * `:offset` — byte donde empieza la línea, 0-based, tal como lo usa
      `:binary.part/3`.
    * `:largo` — bytes de la línea sin su terminador.

  Sin la opción, el registro es el mapa de siempre y no se calcula nada.

  ## Por qué una clave reservada en el mapa

  Las alternativas eran una tupla `{registro, traza}` o un struct
  `%Registro{valores: ..., traza: ...}`. Las dos cambian la forma de retorno
  para todo el código que ya lee `registro.monto`. La clave `:__traza__` no:
  el registro sigue siendo el mapa, la traza está al lado, y los dos guiones
  bajos son la convención de Elixir para metadatos que no chocan con datos
  (`__struct__`, `__meta__` en Ecto). Un campo del layout no se puede llamar
  así; `AnchoFijo.Layout.nuevo/1` lo rechaza.

  ## La huella del lote

  `huella/2` es un SHA-256 del contenido, estable entre corridas y sensible a
  cualquier cambio de un byte de datos. Lo que **no** cambia la huella es lo
  que no cambia lo que el parser lee: el estilo de terminador de línea (CRLF,
  LF o CR, normalizados a LF) y la presencia del terminador en la última
  línea. Un archivo que pasó por un editor de Windows es el mismo lote.

      iex> AnchoFijo.Traza.huella("001\\n002\\n") == AnchoFijo.Traza.huella("001\\r\\n002")
      true
      iex> AnchoFijo.Traza.huella("001\\n002\\n") == AnchoFijo.Traza.huella("001\\n003\\n")
      false

  Con `normalizar: false` se calcula sobre los bytes exactos, que es lo que
  da `sha256sum`. Se calcula por bloques, así que un archivo de gigabytes no
  se carga en memoria.
  """

  @type t :: %__MODULE__{linea: pos_integer(), offset: non_neg_integer(), largo: non_neg_integer()}

  @enforce_keys [:linea, :offset, :largo]
  defstruct [:linea, :offset, :largo]

  @clave :__traza__

  alias AnchoFijo.Diagnostico
  alias AnchoFijo.Entrada

  @doc "La clave reservada bajo la que viaja la traza en el registro."
  @spec clave() :: :__traza__
  def clave, do: @clave

  @doc """
  Construye la traza de una línea.

      iex> AnchoFijo.Traza.nueva(7, 288, 48)
      %AnchoFijo.Traza{linea: 7, offset: 288, largo: 48}
  """
  @spec nueva(pos_integer(), non_neg_integer(), non_neg_integer()) :: t()
  def nueva(linea, offset, largo), do: %__MODULE__{linea: linea, offset: offset, largo: largo}

  @doc """
  Recupera la línea original desde el contenido completo del archivo.

      iex> traza = AnchoFijo.Traza.nueva(2, 4, 3)
      iex> AnchoFijo.Traza.linea_original(traza, "001\\n002\\n")
      "002"
  """
  @spec linea_original(t(), binary()) :: binary()
  def linea_original(%__MODULE__{offset: offset, largo: largo}, contenido)
      when is_binary(contenido) do
    :binary.part(contenido, offset, largo)
  end

  @doc """
  SHA-256 del contenido con los terminadores de línea normalizados, como
  `"sha256:"` seguido de 64 dígitos hexadecimales.

  `entrada` es el contenido, una ruta o un enumerable de bloques, igual que en
  `AnchoFijo.parsear/3`; acepta `:desde` para desambiguar.

      iex> AnchoFijo.Traza.huella("001\\n002\\n")
      {:ok, "sha256:3164aeb0f4d85eabb8bcc255402e83170729ffe8cb076483b98caf2407eca512"}

  Con `normalizar: false`, el hash es de los bytes exactos:

      iex> {:ok, "sha256:" <> hex} = AnchoFijo.Traza.huella("abc", normalizar: false)
      iex> hex == Base.encode16(:crypto.hash(:sha256, "abc"), case: :lower)
      true
  """
  @spec huella(term(), keyword()) :: {:ok, String.t()} | {:error, [Diagnostico.t()]}
  def huella(entrada, opts \\ []) do
    normalizar? = Keyword.get(opts, :normalizar, true)

    with {:ok, bloques} <- Entrada.bloques(entrada, opts) do
      {:ok, "sha256:" <> calcular(bloques, normalizar?)}
    end
  end

  defp calcular(bloques, false) do
    bloques
    |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
  end

  # Los bloques se recorren una sola vez. El estado arrastra si el bloque
  # anterior terminó en CR (puede ser la mitad de un CRLF), si el último byte
  # emitido fue un salto de línea, y si se emitió algo. Al final, un CR
  # pendiente es un salto, y si hubo contenido que no terminó en salto se
  # agrega uno: así "a\\nb" y "a\\nb\\n" son el mismo lote.
  defp calcular(bloques, true) do
    estado = {:crypto.hash_init(:sha256), false, false, false}

    {hash, cr_pendiente?, termina_en_salto?, hubo_contenido?} =
      Enum.reduce(bloques, estado, fn bloque, acumulado -> absorber(bloque, acumulado) end)

    hash =
      cond do
        cr_pendiente? -> :crypto.hash_update(hash, "\n")
        hubo_contenido? and not termina_en_salto? -> :crypto.hash_update(hash, "\n")
        true -> hash
      end

    hash |> :crypto.hash_final() |> Base.encode16(case: :lower)
  end

  defp absorber("", acumulado), do: acumulado

  defp absorber(bloque, {hash, cr_pendiente?, _termina_en_salto?, hubo_contenido?}) do
    {prefijo, bloque} = resolver_cr(cr_pendiente?, bloque)
    normalizado = prefijo <> normalizar_terminadores(bloque)

    {normalizado, cr_pendiente?} =
      case normalizado do
        "" ->
          {"", false}

        _ ->
          if String.ends_with?(normalizado, "\r"),
            do: {binary_part(normalizado, 0, byte_size(normalizado) - 1), true},
            else: {normalizado, false}
      end

    termina_en_salto? = normalizado != "" and String.ends_with?(normalizado, "\n")
    hubo_contenido? = hubo_contenido? or normalizado != "" or cr_pendiente?

    {:crypto.hash_update(hash, normalizado), cr_pendiente?, termina_en_salto?, hubo_contenido?}
  end

  # Un CR al final del bloque anterior era un CRLF partido si este bloque
  # empieza con LF; si no, era un CR solo. En los dos casos vale un LF.
  defp resolver_cr(false, bloque), do: {"", bloque}
  defp resolver_cr(true, "\n" <> resto), do: {"\n", resto}
  defp resolver_cr(true, bloque), do: {"\n", bloque}

  defp normalizar_terminadores(bloque) do
    bloque
    |> String.replace("\r\n", "\n")
    |> String.replace(~r/\r(?!$)/, "\n")
  end
end
