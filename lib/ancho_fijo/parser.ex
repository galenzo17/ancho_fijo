defmodule AnchoFijo.Parser do
  @moduledoc """
  Lee registros de ancho fijo según un layout.

  Es la parte aburrida del paquete, y así debería ser: si `AnchoFijo.Detector`
  hizo su trabajo, el parser no descubre sorpresas.

      iex> layout = AnchoFijo.Layout.nuevo!(campos: [
      ...>   [nombre: :codigo, largo: 4, tipo: :entero],
      ...>   [nombre: :monto, largo: 8, tipo: :decimal, precision: 2]
      ...> ])
      iex> AnchoFijo.Parser.parsear(layout, "001000123456\\n0020no-monto\\n", modo: :tolerante)
      {:ok, [%{codigo: 10, monto: {123456, 2}}],
       [
         %AnchoFijo.Diagnostico{
           tipo: :campo_invalido,
           linea: 2,
           campo: :monto,
           posicion: {5, 12},
           esperado: "8 dígitos con 2 decimales implícitos",
           recibido: "\\"no-monto\\"",
           causa_probable: "el monto trae un separador decimal explícito o un carácter no numérico; si el archivo usa punto o coma, declare separador: :punto o :coma",
           contenido: nil
         }
       ]}

  ## Los dos modos

  `:estricto` (default) corta en la primera línea con problemas y devuelve
  `{:error, diagnosticos}`. Sirve para archivos que son contratos: una cartola
  que no cuadra no se procesa a medias.

  `:tolerante` procesa todo y devuelve `{:ok, registros, diagnosticos}`. Existe
  porque en producción una nómina de 10.000 filas con 3 malas debe reportar las
  3, no botar el lote completo; y porque el operador que corrige el archivo
  necesita la lista completa de errores, no el primero de una serie de treinta.

  Nótese que el modo tolerante devuelve `:ok`, no `:error`: un lote con filas
  malas separadas de las buenas es un resultado, no una falla. `{:error, _}`
  queda para lo que impide procesar cualquier cosa —layout inválido, archivo
  ilegible—, donde no hay nada que rescatar.

  ## Una línea, un diagnóstico por causa

  Si una línea no mide el largo declarado, se reporta solo eso y no se intentan
  leer sus campos. Un byte faltante corre todos los campos que vienen después:
  reportar los 12 diagnósticos derivados esconde el único que importa.

  ## Opciones

    * `:modo` — `:estricto` (default) o `:tolerante`.
    * `:saltar` — cantidad de líneas iniciales a ignorar (headers). Default 0.
    * `:omitir_vacias` — ignorar líneas en blanco. Default `true`, porque el
      salto final del archivo es una línea vacía y no un registro corrupto.
    * `:desde` — `:auto` (default), `:archivo` o `:contenido`.
  """

  alias AnchoFijo.Campo
  alias AnchoFijo.Diagnostico
  alias AnchoFijo.Entrada
  alias AnchoFijo.Layout
  alias AnchoFijo.Transcodificacion

  @type registro :: %{optional(atom()) => Campo.valor()}
  @type resultado ::
          {:ok, [registro()]}
          | {:ok, [registro()], [Diagnostico.t()]}
          | {:error, [Diagnostico.t()]}

  @doc """
  Parsea un archivo completo en memoria.

      iex> layout = AnchoFijo.Layout.nuevo!(campos: [[nombre: :sigla, largo: 3], [nombre: :saldo, largo: 6, tipo: :entero]])
      iex> AnchoFijo.Parser.parsear(layout, "CLP001234\\nUSD000567\\n")
      {:ok, [%{sigla: "CLP", saldo: 1234}, %{sigla: "USD", saldo: 567}]}

  En modo estricto, la primera línea mala corta el proceso:

      iex> layout = AnchoFijo.Layout.nuevo!(campos: [[nombre: :sigla, largo: 3], [nombre: :saldo, largo: 6, tipo: :entero]])
      iex> {:error, [diagnostico]} = AnchoFijo.Parser.parsear(layout, "CLP001234\\nUSD00056\\n")
      iex> AnchoFijo.Diagnostico.mensaje(diagnostico)
      "línea 2: se esperaban 9 bytes, llegaron 8; posible campo faltante o archivo delimitado"
  """
  @spec parsear(Layout.t() | Enumerable.t(), term(), keyword()) :: resultado()
  def parsear(layout, entrada, opts \\ []) do
    with {:ok, layout} <- Layout.coercer(layout),
         {:ok, contenido} <- Entrada.leer(entrada, opts) do
      contenido
      |> Entrada.dividir()
      |> Enum.with_index(1)
      |> seleccionar(opts)
      |> procesar(layout, Keyword.get(opts, :modo, :estricto))
    end
  end

  @doc """
  Versión lazy de `parsear/3`, para archivos que no caben en memoria.

  Devuelve un `Stream` de `{:ok, registro}` o `{:error, diagnosticos}`, una
  entrada por línea con contenido. La decisión de qué hacer con los errores es
  del consumidor, que es la única forma honesta de ser lazy: acumular todos los
  diagnósticos de un archivo de 2 GB para devolverlos al final anula el punto.

      iex> layout = AnchoFijo.Layout.nuevo!(campos: [[nombre: :codigo, largo: 3, tipo: :entero]])
      iex> AnchoFijo.Parser.stream(layout, "001\\n002\\nXYZ\\n") |> Enum.count(&match?({:ok, _}, &1))
      2

  Para replicar el modo estricto sobre un stream, corte usted mismo:

      iex> layout = AnchoFijo.Layout.nuevo!(campos: [[nombre: :codigo, largo: 3, tipo: :entero]])
      iex> AnchoFijo.Parser.stream(layout, "001\\n002\\nXYZ\\n004\\n")
      ...> |> Enum.reduce_while([], fn
      ...>   {:ok, registro}, acumulado -> {:cont, [registro | acumulado]}
      ...>   {:error, _diagnosticos}, acumulado -> {:halt, Enum.reverse(acumulado)}
      ...> end)
      [%{codigo: 1}, %{codigo: 2}]

  Acepta un `File.Stream` ya construido, lo que permite elegir el tamaño de
  lectura o leer desde una tubería:

      AnchoFijo.Parser.stream(layout, File.stream!("cartola.txt"))

  Un layout inválido levanta `AnchoFijo.Error` en vez de devolver un stream:
  es un error del programador, no del archivo. Un archivo ilegible sí se
  reporta como dato, en el primer elemento del stream.

  Con `File.stream!/1` las líneas se cortan solo por `\\n`; si el archivo usa CR
  a secas (Mac clásico, que `detectar/2` identifica), use `parsear/3`.
  """
  @spec stream(Layout.t() | Enumerable.t(), term(), keyword()) :: Enumerable.t()
  def stream(layout, entrada, opts \\ []) do
    layout = coercer!(layout)

    case Entrada.lineas(entrada, opts) do
      {:ok, lineas} -> encadenar(lineas, layout, opts)
      {:error, diagnosticos} -> [{:error, diagnosticos}]
    end
  end

  @doc """
  Parsea una sola línea, ya sin terminador.

      iex> layout = AnchoFijo.Layout.nuevo!(campos: [[nombre: :a, largo: 2], [nombre: :b, largo: 3, tipo: :entero]])
      iex> AnchoFijo.Parser.parsear_linea(layout, "XY007", 1)
      {:ok, %{a: "XY", b: 7}}

  El caso más común: un archivo latin-1 leído con el encoding por default.

      iex> layout = AnchoFijo.Layout.nuevo!(campos: [[nombre: :nombre, largo: 5]])
      iex> {:error, [diagnostico]} = AnchoFijo.Parser.parsear_linea(layout, <<74, 79, 83, 201, 32>>, 3)
      iex> AnchoFijo.Diagnostico.mensaje(diagnostico)
      "línea 3, campo :nombre (posiciones 1-5): se esperaban bytes válidos en utf8, llegaron el byte 0xC9 en la posición 4; el byte 0xC9 no es UTF-8 válido pero sí es un carácter latin-1; declare encoding: :latin1 en el layout"
  """
  @spec parsear_linea(Layout.t(), binary(), pos_integer()) ::
          {:ok, registro()} | {:error, [Diagnostico.t()]}
  def parsear_linea(%Layout{} = layout, cruda, numero) do
    with {:ok, linea} <- preparar(layout, cruda, numero),
         :ok <- validar_largo(layout, linea, numero) do
      extraer_campos(layout, linea, numero)
    end
  end

  defp coercer!(layout) do
    case Layout.coercer(layout) do
      {:ok, layout} -> layout
      {:error, diagnosticos} -> raise AnchoFijo.Error, diagnosticos
    end
  end

  defp encadenar(lineas, layout, opts) do
    lineas
    |> Stream.with_index(1)
    |> Stream.drop(Keyword.get(opts, :saltar, 0))
    |> Stream.map(fn {linea, numero} -> {Entrada.sin_terminador(linea), numero} end)
    |> descartar_vacias(Keyword.get(opts, :omitir_vacias, true))
    |> Stream.map(fn {linea, numero} -> parsear_linea(layout, linea, numero) end)
  end

  defp descartar_vacias(stream, true) do
    Stream.reject(stream, fn {linea, _numero} -> linea == "" end)
  end

  defp descartar_vacias(stream, _false), do: stream

  defp seleccionar(numeradas, opts) do
    numeradas
    |> Enum.drop(Keyword.get(opts, :saltar, 0))
    |> filtrar_vacias(Keyword.get(opts, :omitir_vacias, true))
  end

  defp filtrar_vacias(numeradas, true) do
    Enum.reject(numeradas, fn {linea, _numero} -> linea == "" end)
  end

  defp filtrar_vacias(numeradas, _false), do: numeradas

  defp procesar(numeradas, layout, :estricto) do
    resultado =
      Enum.reduce_while(numeradas, [], fn {linea, numero}, registros ->
        case parsear_linea(layout, linea, numero) do
          {:ok, registro} -> {:cont, [registro | registros]}
          {:error, diagnosticos} -> {:halt, {:error, diagnosticos}}
        end
      end)

    case resultado do
      {:error, diagnosticos} -> {:error, diagnosticos}
      registros -> {:ok, Enum.reverse(registros)}
    end
  end

  defp procesar(numeradas, layout, :tolerante) do
    {registros, diagnosticos} =
      Enum.reduce(numeradas, {[], []}, fn {linea, numero}, {registros, diagnosticos} ->
        case parsear_linea(layout, linea, numero) do
          {:ok, registro} -> {[registro | registros], diagnosticos}
          {:error, nuevos} -> {registros, Enum.reverse(nuevos) ++ diagnosticos}
        end
      end)

    {:ok, Enum.reverse(registros), Enum.reverse(diagnosticos)}
  end

  defp procesar(_numeradas, _layout, modo) do
    {:error,
     [
       Diagnostico.nuevo(
         tipo: :entrada,
         esperado: ":modo en [:estricto, :tolerante]",
         recibido: modo,
         causa_probable: "la opción :modo no reconoce ese valor"
       )
     ]}
  end

  defp preparar(%Layout{unidad: :bytes}, cruda, _numero), do: {:ok, cruda}

  defp preparar(%Layout{unidad: :caracteres} = layout, cruda, numero) do
    case Transcodificacion.a_utf8(cruda, layout.encoding) do
      {:ok, texto} ->
        {:ok, texto}

      {:error, detalle} ->
        {:error,
         [
           Diagnostico.nuevo(
             tipo: :encoding,
             linea: numero,
             esperado: "una línea completa válida en #{layout.encoding}",
             recibido: Transcodificacion.describir_byte(detalle, 1),
             causa_probable: Transcodificacion.causa_probable(detalle, layout.encoding)
           )
         ]}
    end
  end

  defp validar_largo(%Layout{} = layout, linea, numero) do
    encontrado = medida(layout, linea)

    if encontrado == layout.largo do
      :ok
    else
      {:error, [desajuste_de_largo(layout, encontrado, numero)]}
    end
  end

  defp medida(%Layout{unidad: :caracteres}, linea), do: String.length(linea)
  defp medida(%Layout{unidad: :bytes}, linea), do: byte_size(linea)

  defp desajuste_de_largo(%Layout{} = layout, encontrado, numero) do
    unidad = Campo.nombre_unidad(layout.unidad)

    Diagnostico.nuevo(
      tipo: :largo_de_linea,
      linea: numero,
      esperado: "#{layout.largo} #{unidad}",
      recibido: encontrado,
      causa_probable: causa_de_largo(encontrado, layout.largo)
    )
  end

  defp causa_de_largo(encontrado, esperado) when encontrado < esperado do
    "posible campo faltante o archivo delimitado"
  end

  defp causa_de_largo(_encontrado, _esperado) do
    "posible campo extra, relleno no declarado, o un terminador de línea " <>
      "distinto del que se usó para cortar las líneas"
  end

  defp extraer_campos(%Layout{} = layout, linea, numero) do
    contexto = Layout.contexto(layout, numero)

    {valores, diagnosticos} =
      Enum.reduce(layout.campos, {[], []}, fn campo, {valores, diagnosticos} ->
        case Campo.extraer(campo, linea, contexto) do
          {:ok, valor} -> {[{campo.nombre, valor} | valores], diagnosticos}
          {:error, diagnostico} -> {valores, [diagnostico | diagnosticos]}
        end
      end)

    case diagnosticos do
      [] -> {:ok, Map.new(valores)}
      diagnosticos -> {:error, Enum.reverse(diagnosticos)}
    end
  end
end
