defmodule AnchoFijo.Escritor do
  @moduledoc """
  Escribe registros con el mismo layout que los lee.

  Para mandarle una nómina al banco hay que generarla con el formato del
  anexo, y el formato ya está escrito una vez: es el layout. `escribir/3` es
  el inverso de `AnchoFijo.parsear/3`, y la propiedad que lo define es el
  round-trip: lo que se escribe se vuelve a leer igual.

      iex> layout = AnchoFijo.Layout.nuevo!(campos: [
      ...>   [nombre: :rut, largo: 10, tipo: :rut],
      ...>   [nombre: :nombre, largo: 12],
      ...>   [nombre: :monto, largo: 8, tipo: :decimal, precision: 2],
      ...>   [nombre: :fecha, largo: 8, tipo: :fecha, formato: :aaaammdd]
      ...> ])
      iex> registro = %{rut: "12345678-5", nombre: "JUAN PEREZ", monto: {123_456, 2}, fecha: ~D[2024-01-31]}
      iex> {:ok, contenido, []} = AnchoFijo.Escritor.escribir(layout, [registro])
      iex> contenido
      "12345678-5JUAN PEREZ  0012345620240131\\n"
      iex> AnchoFijo.parsear(layout, contenido)
      {:ok, [registro], []}

  ## Todo o nada, con todos los diagnósticos

  No hay modo tolerante para escribir: una nómina con una fila menos es un
  archivo distinto, y mandarlo al banco es peor que no mandarlo. Si algún
  valor no se puede escribir, `escribir/3` devuelve `{:error, diagnosticos}`
  con **todos** los problemas, de todos los registros, para corregirlos de
  una vez. Cada diagnóstico dice el registro (como `:linea`), el campo, las
  posiciones, qué se esperaba y qué llegó.

  ## Lo que no cabe

  Un valor más ancho que el campo es un error, no se trunca: un monto
  truncado es otro monto, un RUT truncado es otra persona, y una glosa
  truncada es la única de las tres que a veces se acepta. Por eso
  `truncar: true` existe solo para `:texto`, y deja una advertencia por cada
  campo truncado; los demás tipos fallan siempre.

  ## Relleno, signo, encoding

    * `:texto` se rellena con `:relleno` del lado que `:trim` recorta al
      leer (a la derecha con `:ambos` o `:derecha`, a la izquierda con
      `:izquierda`); con `trim: false` el valor tiene que medir exacto.
    * `:entero` y `:decimal` se rellenan con ceros a la izquierda. El signo
      ocupa una posición solo cuando el número es negativo, del lado que
      `:signo` declara; el positivo no lleva signo.
    * `:decimal` recibe `{unidades, precision}` y la precisión tiene que
      ser la del campo: no se escala, porque escalar es donde se pierde el
      peso. Con `:separador` explícito se escribe el punto o la coma.
    * `:fecha` según `:formato`; `:rut` en forma canónica, o solo el cuerpo
      con `dv: :ausente`.
    * `nil` en un campo `opcional: true` se escribe como relleno en blanco;
      sin `:opcional`, es un error.
    * El encoding del layout se respeta: con `encoding: :latin1` el texto
      sale en latin-1, y un carácter que latin-1 no tiene es un error con el
      carácter y su posición. El ancho se mide en la `:unidad` del layout.

  ## Opciones

    * `:terminador` — `:lf` (default), `:crlf`, `:cr` o `:ninguno`.
    * `:truncar` — `true` para recortar los `:texto` que no caben, con una
      advertencia por cada uno. Default `false`.

  Una opción que no existe o un valor de otro tipo (`terminador: :lf2`,
  `truncarr: true`) es un `ArgumentError` que nombra la función y la
  opción, como en `AnchoFijo.parsear/3`: es un error del programa, no de
  los datos. `escribir/3` emite los eventos `[:ancho_fijo, :escribir, ...]`
  de `AnchoFijo.Telemetria`.
  """

  alias AnchoFijo.Anidados
  alias AnchoFijo.Campo
  alias AnchoFijo.Diagnostico
  alias AnchoFijo.Layout
  alias AnchoFijo.Opciones
  alias AnchoFijo.Telemetria

  @terminadores %{lf: "\n", crlf: "\r\n", cr: "\r", ninguno: ""}

  @type registro :: %{optional(atom()) => term()}

  @doc """
  Escribe todos los registros como un binario, o devuelve todos los
  diagnósticos.

      iex> AnchoFijo.Escritor.escribir([campos: [[nombre: :codigo, largo: 3, tipo: :entero]]], [%{codigo: 7}, %{codigo: 42}])
      {:ok, "007\\n042\\n", []}

      iex> {:error, [d]} = AnchoFijo.Escritor.escribir([campos: [[nombre: :codigo, largo: 3, tipo: :entero]]], [%{codigo: 1234}])
      iex> AnchoFijo.Diagnostico.mensaje(d)
      "línea 1, campo :codigo (posiciones 1-3): se esperaban un entero de hasta 3 dígitos, llegaron 1234; el valor no cabe en el campo: 4 posiciones en 3"
  """
  @spec escribir(Layout.t() | Enumerable.t(), Enumerable.t(), keyword()) ::
          {:ok, binary(), [Diagnostico.t()]} | {:error, [Diagnostico.t()]}
  def escribir(layout, registros, opts \\ []) do
    opts = Opciones.validar!(opts, opciones(), "AnchoFijo.escribir/3")
    metadata = metadata_de(opts)

    Telemetria.span(:escribir, metadata, fn ->
      case Layout.coercer(layout) do
        {:ok, layout} ->
          {resultado, procesados} = escribir_todo(registros, layout, opts)
          {medidas, extra} = medir(resultado, procesados)
          {resultado, medidas, Map.merge(extra, metadata_de_layout(layout))}

        {:error, diagnosticos} ->
          {medidas, extra} = medir({:error, diagnosticos}, 0)
          {{:error, diagnosticos}, medidas, Map.merge(extra, metadata_de_layout(nil))}
      end
    end)
  end

  # Las mismas cinco medidas que `parsear`. Con `{:ok, _}` todos los
  # registros se escribieron; con `{:error, _}` ninguno, porque es todo o
  # nada, y los errores son los diagnósticos devueltos.
  defp medir({:ok, _contenido, advertencias}, procesados) do
    {%{lineas: procesados, registros: procesados, errores: 0, advertencias: length(advertencias)},
     %{resultado: :ok}}
  end

  defp medir({:error, diagnosticos}, procesados) do
    {%{lineas: procesados, registros: 0, errores: length(diagnosticos), advertencias: 0},
     %{resultado: :error}}
  end

  # Devuelve el resultado y cuántos registros se procesaron, que es lo que
  # la telemetría mide como `lineas`. Un registro que no es un mapa también
  # cuenta: se intentó escribir.
  defp escribir_todo(registros, %Layout{} = layout, opts) do
    {lineas, advertencias, errores, procesados} =
      registros
      |> stream_con_layout(layout, opts)
      |> Enum.reduce({[], [], [], 0}, fn
        {:ok, linea, nuevas}, {lineas, advertencias, errores, n} ->
          {[linea | lineas], Enum.reverse(nuevas, advertencias), errores, n + 1}

        {:error, nuevos}, {lineas, advertencias, errores, n} ->
          {lineas, advertencias, Enum.reverse(nuevos, errores), n + 1}
      end)

    case errores do
      [] ->
        {{:ok, lineas |> Enum.reverse() |> IO.iodata_to_binary(), Enum.reverse(advertencias)},
         procesados}

      errores ->
        {{:error, Enum.reverse(errores)}, procesados}
    end
  end

  defp metadata_de(opts) do
    %{terminador: Keyword.get(opts, :terminador, :lf), truncar: Keyword.get(opts, :truncar, false)}
  end

  defp metadata_de_layout(%Layout{} = layout) do
    %{layout: layout.nombre, encoding: layout.encoding, unidad: layout.unidad}
  end

  defp metadata_de_layout(nil), do: %{layout: nil, encoding: nil, unidad: nil}

  @doc false
  # Públicas sin doc: `AnchoFijo.Multiregistro.escribir/3` valida las mismas
  # opciones y escribe con el mismo terminador.
  @spec opciones() :: Opciones.esquema()
  def opciones do
    [
      {:terminador, &Map.has_key?(@terminadores, &1), ":lf, :crlf, :cr o :ninguno"},
      {:truncar, &is_boolean/1, "true o false"}
    ]
  end

  @doc false
  @spec terminador(atom()) :: binary()
  def terminador(nombre), do: Map.fetch!(@terminadores, nombre)

  @doc """
  Versión lazy: un `Stream` de `{:ok, linea_con_terminador, advertencias}` o
  `{:error, diagnosticos}` por registro. Para escribir una nómina de
  millones de filas a un archivo sin armarla entera en memoria:

      layout
      |> AnchoFijo.Escritor.stream(registros)
      |> Stream.map(fn {:ok, linea, _} -> linea end)
      |> Stream.into(File.stream!("nomina.txt"))
      |> Stream.run()

  Un layout inválido levanta `AnchoFijo.Error`, como en `AnchoFijo.stream/3`.
  Qué hacer con un registro que no se puede escribir es decisión del
  consumidor; la variante eager, `escribir/3`, no escribe nada si hay uno.
  Un `AnchoFijo.Multiregistro` levanta `ArgumentError`: el trailer necesita
  los totales de todos los detalles, y eso no tiene versión lazy; use
  `AnchoFijo.escribir/3`.

  Emite `[:ancho_fijo, :escribir_stream, :start]` cuando empieza la
  enumeración y `:stop` cuando termina o se corta, con las mismas cuentas
  que `AnchoFijo.stream/3`.
  """
  @spec stream(Layout.t() | Enumerable.t(), Enumerable.t(), keyword()) :: Enumerable.t()
  def stream(layout, registros, opts \\ [])

  # Un multiregistro no se escribe lazy: el trailer lleva los totales de los
  # detalles, y los totales necesitan todos los detalles.
  def stream(%AnchoFijo.Multiregistro{}, _registros, _opts) do
    raise ArgumentError,
          "AnchoFijo.Escritor.stream/3 no acepta un Multiregistro: el trailer necesita los " <>
            "totales de todos los detalles, así que no hay versión lazy; use AnchoFijo.escribir/3"
  end

  def stream(layout, registros, opts) do
    opts = Opciones.validar!(opts, opciones(), "AnchoFijo.Escritor.stream/3")

    case Layout.coercer(layout) do
      {:ok, layout} ->
        metadata = Map.merge(metadata_de(opts), metadata_de_layout(layout))

        registros
        |> stream_con_layout(layout, opts)
        |> Telemetria.instrumentar_stream(metadata, :escribir_stream)

      {:error, diagnosticos} ->
        raise AnchoFijo.Error, diagnosticos
    end
  end

  # Las opciones ya vienen validadas: el terminador existe en el mapa.
  defp stream_con_layout(registros, %Layout{} = layout, opts) do
    terminador = Map.fetch!(@terminadores, Keyword.get(opts, :terminador, :lf))
    truncar? = Keyword.get(opts, :truncar, false)

    registros
    |> Stream.with_index(1)
    |> Stream.map(fn {registro, numero} ->
      case escribir_linea(layout, registro, numero, truncar?) do
        {:ok, linea, advertencias} -> {:ok, linea <> terminador, advertencias}
        {:error, diagnosticos} -> {:error, diagnosticos}
      end
    end)
  end

  @doc """
  Escribe un solo registro como una línea sin terminador.

      iex> layout = AnchoFijo.Layout.nuevo!(campos: [[nombre: :a, largo: 2], [nombre: :b, posicion: 5, largo: 3, tipo: :entero]])
      iex> AnchoFijo.Escritor.escribir_linea(layout, %{a: "x", b: 7}, 1)
      {:ok, "x   007", []}

  Las posiciones que el layout no declara —huecos y relleno final— se
  escriben en blanco.
  """
  @spec escribir_linea(Layout.t(), registro(), pos_integer(), boolean()) ::
          {:ok, binary(), [Diagnostico.t()]} | {:error, [Diagnostico.t()]}
  def escribir_linea(layout, registro, numero, truncar? \\ false)

  def escribir_linea(%Layout{} = layout, registro, numero, truncar?) when is_map(registro) do
    contexto = layout |> Layout.contexto(numero) |> Map.put(:truncar, truncar?)

    {segmentos, cursor, advertencias, errores} =
      Enum.reduce(layout.campos, {[], 1, [], []}, fn campo,
                                                     {segmentos, cursor, advertencias, errores} ->
        hueco = String.duplicate(" ", campo.posicion - cursor)

        case formatear(campo, registro, contexto) do
          {:ok, texto, nuevas} ->
            {[texto, hueco | segmentos], Campo.fin(campo) + 1, Enum.reverse(nuevas, advertencias),
             errores}

          {:error, nuevos} ->
            {segmentos, Campo.fin(campo) + 1, advertencias, Enum.reverse(nuevos, errores)}
        end
      end)

    case errores do
      [] ->
        relleno_final = String.duplicate(" ", layout.largo + 1 - cursor)

        {:ok, IO.iodata_to_binary(Enum.reverse([relleno_final | segmentos])),
         Enum.reverse(advertencias)}

      errores ->
        {:error, Enum.reverse(errores)}
    end
  end

  def escribir_linea(%Layout{}, registro, numero, _truncar?) do
    {:error,
     [
       Diagnostico.nuevo(
         tipo: :entrada,
         linea: numero,
         esperado: "un mapa con los campos del layout",
         recibido: tipo_de(registro),
         causa_probable: "cada registro a escribir es un mapa como los que devuelve parsear/3"
       )
     ]}
  end

  # Un grupo o una variante se escriben campo por campo, con el registro a
  # la vista (la variante la elige otro campo); el resto, con `Campo`.
  defp formatear(%Campo{} = campo, registro, contexto) do
    if Campo.anidado?(campo) do
      Anidados.escribir(campo, Map.get(registro, campo.nombre), registro, contexto)
    else
      case Campo.formatear(campo, Map.get(registro, campo.nombre), contexto) do
        {:ok, texto, advertencias} -> {:ok, texto, advertencias}
        {:error, diagnostico} -> {:error, [diagnostico]}
      end
    end
  end

  defp tipo_de(valor) when is_list(valor), do: "una lista"
  defp tipo_de(valor) when is_binary(valor), do: "un binario"
  defp tipo_de(valor) when is_tuple(valor), do: "una tupla"
  defp tipo_de(nil), do: "nil"
  defp tipo_de(valor) when is_atom(valor), do: "un átomo"
  defp tipo_de(valor) when is_number(valor), do: "un número"
  defp tipo_de(_valor), do: "un término de otro tipo"
end
