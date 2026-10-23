defmodule AnchoFijo.Identidad do
  @moduledoc """
  Reconocer el archivo que ya se procesó, antes de pagar dos veces.

  El error operacional más caro de una nómina no es una fila mal parseada:
  es el mismo archivo procesado dos veces, por un reintento manual, un cron
  que corrió dos veces o un correo reenviado. La librería es el punto natural
  para detectarlo, porque ve el archivo completo antes de que exista un solo
  registro en la base de datos.

  Una identidad tiene tres fuentes, en orden de confiabilidad decreciente:

    1. **Lo que el archivo declara de sí mismo**: el número de lote y la
       fecha de generación que casi todos los formatos traen en el header.
       El layout dice cuáles son esos campos con `identidad: [campos: [...]]`
       y se leen del primer registro.
    2. **La huella del contenido**: `AnchoFijo.Traza.huella/2`, SHA-256 con
       los terminadores normalizados. No depende de que el emisor haya
       puesto nada.
    3. **El nombre del archivo**. Es informativo y nada más: dos nóminas
       distintas se llaman `nomina.txt` todos los días.

      iex> layout = AnchoFijo.Layout.nuevo!(
      ...>   identidad: [campos: [:lote, :fecha]],
      ...>   campos: [
      ...>     [nombre: :lote, largo: 4, tipo: :entero],
      ...>     [nombre: :fecha, largo: 8, tipo: :fecha, formato: :aaaammdd],
      ...>     [nombre: :monto, largo: 6, tipo: :entero]
      ...>   ]
      ...> )
      iex> {:ok, identidad} = AnchoFijo.identidad(layout, "000120240115001000\\n000120240115002500\\n")
      iex> identidad.declarada
      %{lote: 1, fecha: ~D[2024-01-15]}
      iex> identidad.huella
      "sha256:83777cc281b739e2b20d1c0bf81036b3e478a787b8ade119e2a4503970b314e5"

  ## Con header, detalle y trailer

  Justo los formatos con header son los que traen una identidad declarada
  de verdad, y en un archivo multiregistro el header tiene su propio
  layout. `identidad/3` acepta un `AnchoFijo.Multiregistro`: la identidad
  declarada se lee con el layout del primer tipo de `:registros` que tenga
  `identidad:`, y el primer registro del archivo tiene que ser de ese tipo;
  si es de otro, es un diagnóstico `:identidad`. Si ningún tipo la declara,
  `:declarada` es `nil`, como con un layout plano sin `identidad:`.

      iex> {:ok, identidad} = AnchoFijo.identidad(AnchoFijo.Formatos.nacha(), "test/fixtures/nacha_ppd.txt")
      iex> identidad.declarada
      %{immediate_origin: "991000012", file_creation_date: "240115", file_creation_time: "0930", file_id_modifier: "A"}

  ## Cotejar contra lo ya visto

  `cotejar/2` compara una identidad con la lista de las que ya se
  procesaron y responde una de tres cosas:

    * `:nueva` — no se parece a ninguna.
    * `{:duplicada, vista}` — la misma huella: es el mismo archivo, se llame
      como se llame y diga lo que diga.
    * `{:conflicto, diagnostico, vista}` — la misma identidad declarada con
      otra huella. **No es un duplicado, es algo peor**: el emisor reutilizó
      el número de lote o alguien editó el archivo, y el diagnóstico lo dice.

  ## La frontera

  La librería no persiste nada ni tiene estado. Recibe las identidades que
  el llamador ya vio, responde, y punto. El día en que un parser abre una
  tabla o un ETS deja de ser un parser, y además decide por el usuario
  cuánto tiempo recordar y qué hacer con un duplicado. Eso es del sistema
  que paga: guardar `huella` y `declarada` de cada archivo procesado (son
  dos binarios y un mapa chico) y consultarlos antes de empezar.
  """

  alias AnchoFijo.Diagnostico
  alias AnchoFijo.Entrada
  alias AnchoFijo.Layout
  alias AnchoFijo.Multiregistro
  alias AnchoFijo.Parser
  alias AnchoFijo.Traza

  @type t :: %__MODULE__{
          declarada: %{atom() => term()} | nil,
          huella: String.t(),
          nombre: String.t() | nil
        }

  @enforce_keys [:huella]
  defstruct declarada: nil, huella: nil, nombre: nil

  @doc """
  La identidad de un archivo según un layout o un multiregistro.

  `entrada` es el contenido o una ruta, como en `AnchoFijo.parsear/3`. Si
  el layout declara `identidad: [campos: [...]]`, el primer registro se lee
  con el layout y esos campos forman `:declarada`; un primer registro que
  no se puede leer es `{:error, diagnosticos}`. Sin esa opción, `:declarada`
  es `nil` y la identidad es la huella. `:nombre` es el nombre del archivo
  cuando la entrada es una ruta.

  Con un `AnchoFijo.Multiregistro`, el layout que declara la identidad es
  el del primer tipo de `:registros` que tenga `identidad:`, y el primer
  registro del archivo tiene que ser de ese tipo.
  """
  @spec identidad(Layout.t() | Multiregistro.t() | Enumerable.t(), term(), keyword()) ::
          {:ok, t()} | {:error, [Diagnostico.t()]}
  def identidad(layout, entrada, opts \\ [])

  def identidad(%Multiregistro{} = multi, entrada, opts) do
    with {:ok, huella} <- Traza.huella(entrada, opts),
         {:ok, declarada} <- declarada_multi(multi, entrada, opts) do
      {:ok, %__MODULE__{declarada: declarada, huella: huella, nombre: nombre(entrada, opts)}}
    end
  end

  def identidad(layout, entrada, opts) do
    with {:ok, layout} <- Layout.coercer(layout),
         {:ok, huella} <- Traza.huella(entrada, opts),
         {:ok, declarada} <- declarada(layout, entrada, opts) do
      {:ok, %__MODULE__{declarada: declarada, huella: huella, nombre: nombre(entrada, opts)}}
    end
  end

  defp declarada(%Layout{identidad: nil}, _entrada, _opts), do: {:ok, nil}

  defp declarada(%Layout{identidad: %{campos: campos}} = layout, entrada, opts) do
    with {:ok, lineas} <- Entrada.lineas(entrada, opts),
         {:ok, linea, numero} <- primer_registro(lineas, opts, campos),
         {:ok, registro, _advertencias} <- Parser.parsear_linea(layout, linea, numero) do
      {:ok, Map.take(registro, campos)}
    end
  end

  # El tipo que declara la identidad es el primero de :registros con
  # `identidad:` en su layout. El primer registro del archivo se discrimina
  # con el multiregistro, para que un archivo que empieza por otro tipo no
  # se lea con el layout equivocado y falle con diagnósticos de campos que
  # no vienen al caso.
  defp declarada_multi(%Multiregistro{} = multi, entrada, opts) do
    case Enum.find(multi.registros, fn {_tipo, d} -> d.layout.identidad != nil end) do
      nil ->
        {:ok, nil}

      {esperado, %{layout: %Layout{identidad: %{campos: campos}} = layout}} ->
        with {:ok, lineas} <- Entrada.lineas(entrada, opts),
             {:ok, linea, numero} <- primer_registro(lineas, opts, campos),
             {:ok, tipo, _definicion} <- Multiregistro.discriminar(multi, linea, numero, :primera),
             :ok <- del_tipo_esperado(tipo, esperado, numero, campos),
             {:ok, registro, _advertencias} <- Parser.parsear_linea(layout, linea, numero) do
          {:ok, Map.take(registro, campos)}
        end
    end
  end

  defp del_tipo_esperado(tipo, tipo, _numero, _campos), do: :ok

  defp del_tipo_esperado(tipo, esperado, numero, campos) do
    {:error,
     [
       Diagnostico.nuevo(
         tipo: :identidad,
         linea: numero,
         esperado:
           "un primer registro #{inspect(esperado)}, que es el que declara la identidad " <>
             "en #{inspect(campos)}",
         recibido: inspect(tipo),
         causa_probable:
           "el archivo no empieza por el registro que trae la identidad; " <>
             "puede ser un archivo sin header o pegado a otro"
       )
     ]}
  end

  # La primera línea con contenido, respetando :saltar, sin leer el resto.
  defp primer_registro(lineas, opts, campos) do
    lineas
    |> Stream.with_index(1)
    |> Stream.drop(Keyword.get(opts, :saltar, 0))
    |> Stream.map(fn {linea, numero} -> {Entrada.sin_terminador(linea), numero} end)
    |> Stream.reject(fn {linea, _numero} -> linea == "" end)
    |> Enum.take(1)
    |> case do
      [{linea, numero}] -> {:ok, linea, numero}
      [] -> {:error, [sin_primer_registro(campos)]}
    end
  end

  defp sin_primer_registro(campos) do
    Diagnostico.nuevo(
      tipo: :identidad,
      esperado: "un primer registro con los campos #{inspect(campos)} que declaran la identidad",
      recibido: "un archivo sin líneas con contenido",
      causa_probable: "el archivo está vacío; no hay lote que identificar"
    )
  end

  defp nombre(entrada, opts) when is_binary(entrada) do
    if Entrada.es_ruta?(entrada, opts), do: Path.basename(entrada), else: nil
  end

  defp nombre(_entrada, _opts), do: nil

  @doc """
  Compara una identidad con las ya vistas.

      iex> alias AnchoFijo.Identidad
      iex> vista = %Identidad{declarada: %{lote: 1}, huella: "sha256:aaa", nombre: "nomina.txt"}
      iex> Identidad.cotejar(%Identidad{declarada: %{lote: 2}, huella: "sha256:bbb"}, [vista])
      :nueva
      iex> Identidad.cotejar(%Identidad{declarada: %{lote: 1}, huella: "sha256:aaa"}, [vista])
      {:duplicada, vista}
      iex> {:conflicto, diagnostico, ^vista} = Identidad.cotejar(%Identidad{declarada: %{lote: 1}, huella: "sha256:ccc"}, [vista])
      iex> AnchoFijo.Diagnostico.mensaje(diagnostico)
      "identidad: se esperaba un contenido distinto para una identidad declarada distinta, o la misma huella para la misma, llegó lote: 1 con huella sha256:ccc, ya visto con huella sha256:aaa; el emisor reutilizó el número de lote o alguien editó el archivo: no es un reproceso, es otro archivo con la misma identidad"

  La huella manda: el mismo contenido es un duplicado aunque el nombre o la
  identidad declarada difieran. La identidad declarada igual con otro
  contenido es un conflicto. El nombre no decide nada.
  """
  @spec cotejar(t(), [t()]) :: :nueva | {:duplicada, t()} | {:conflicto, Diagnostico.t(), t()}
  def cotejar(%__MODULE__{} = identidad, vistas) when is_list(vistas) do
    cond do
      vista = Enum.find(vistas, &(&1.huella == identidad.huella)) ->
        {:duplicada, vista}

      vista = misma_declarada(identidad, vistas) ->
        {:conflicto, conflicto(identidad, vista), vista}

      true ->
        :nueva
    end
  end

  @doc """
  `true` si la identidad ya se vio: la misma huella. Un conflicto no es un
  duplicado, y devuelve `false`; para distinguirlo, `cotejar/2`.
  """
  @spec duplicada?(t(), [t()]) :: boolean()
  def duplicada?(%__MODULE__{} = identidad, vistas),
    do: match?({:duplicada, _}, cotejar(identidad, vistas))

  defp misma_declarada(%__MODULE__{declarada: nil}, _vistas), do: nil

  defp misma_declarada(%__MODULE__{declarada: declarada}, vistas) do
    Enum.find(vistas, &(&1.declarada == declarada))
  end

  defp conflicto(%__MODULE__{} = identidad, %__MODULE__{} = vista) do
    Diagnostico.nuevo(
      tipo: :identidad,
      esperado:
        "un contenido distinto para una identidad declarada distinta, o la misma huella para la misma",
      recibido:
        "#{describir(identidad.declarada)} con huella #{identidad.huella}, ya visto con huella #{vista.huella}",
      causa_probable:
        "el emisor reutilizó el número de lote o alguien editó el archivo: no es un reproceso, " <>
          "es otro archivo con la misma identidad"
    )
  end

  defp describir(declarada) do
    Enum.map_join(declarada, ", ", fn {campo, valor} -> "#{campo}: #{inspect(valor)}" end)
  end
end
