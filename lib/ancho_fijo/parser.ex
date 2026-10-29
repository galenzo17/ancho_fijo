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

  Los dos devuelven la misma forma: `{:ok, registros, diagnosticos}`.

  `:estricto` (default) corta en la primera línea con problemas y devuelve
  `{:error, diagnosticos}`. Sirve para archivos que son contratos: una cartola
  que no cuadra no se procesa a medias. Cuando llega a `:ok`, la lista de
  diagnósticos solo puede traer advertencias: un error habría cortado.

  `:tolerante` procesa todo y devuelve las filas buenas junto con los
  diagnósticos de las malas. Existe porque en producción una nómina de 10.000
  filas con 3 malas debe reportar las 3, no botar el lote completo; y porque el
  operador que corrige el archivo necesita la lista completa de errores, no el
  primero de una serie de treinta.

  Nótese que el modo tolerante devuelve `:ok`, no `:error`: un lote con filas
  malas separadas de las buenas es un resultado, no una falla. `{:error, _}`
  queda para lo que impide procesar cualquier cosa —layout inválido, archivo
  ilegible—, donde no hay nada que rescatar.

  ## Errores y advertencias

  La tercera posición de `{:ok, registros, diagnosticos}` mezcla las dos
  gravedades de `AnchoFijo.Diagnostico`: un `:error` es una fila que no se pudo
  leer, una `:advertencia` es una fila que sí se leyó pero asumiendo algo.
  Hay un error que sí trae su fila: el de tipo `:regla` (un valor leído
  bien que no cumple `en:`, `rango:`, `patron:`, `requerido_si:` o
  `prohibido_si:`). En `:tolerante` el registro está en la lista y el
  diagnóstico en la tercera posición; en `:estricto` la línea se rechaza.

  Una advertencia no tiene fila propia en `registros`, la tiene **además**: el
  registro está ahí, con su valor. Para separarlas, `Diagnostico.separar/1`.

  En modo `:estricto` un error aborta el archivo y las advertencias de las líneas
  ya leídas se descartan con él: no hay resultado parcial que anotar.

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
    * `:traza` — si es `true`, cada registro trae la clave `:__traza__` con
      un `AnchoFijo.Traza`: número de línea, byte donde empieza y largo.
      Default `false`, y apagada no cuesta nada: no se calcula ni se agrega.

  Una opción que no existe o un valor de otro tipo es un `ArgumentError`:
  es un error del programa, no del archivo, y no se reporta como diagnóstico.
  """

  alias AnchoFijo.Anidados
  alias AnchoFijo.Campo
  alias AnchoFijo.Diagnostico
  alias AnchoFijo.Entrada
  alias AnchoFijo.Layout
  alias AnchoFijo.Opciones
  alias AnchoFijo.Reglas
  alias AnchoFijo.Telemetria
  alias AnchoFijo.Transcodificacion
  alias AnchoFijo.Traza

  @type registro :: %{optional(atom()) => Campo.valor()}
  @type resultado ::
          {:ok, [registro()], [Diagnostico.t()]}
          | {:error, [Diagnostico.t()]}

  @doc """
  Parsea un archivo completo en memoria.

      iex> layout = AnchoFijo.Layout.nuevo!(campos: [[nombre: :sigla, largo: 3], [nombre: :saldo, largo: 6, tipo: :entero]])
      iex> AnchoFijo.Parser.parsear(layout, "CLP001234\\nUSD000567\\n")
      {:ok, [%{sigla: "CLP", saldo: 1234}, %{sigla: "USD", saldo: 567}], []}

  En modo estricto, la primera línea mala corta el proceso:

      iex> layout = AnchoFijo.Layout.nuevo!(campos: [[nombre: :sigla, largo: 3], [nombre: :saldo, largo: 6, tipo: :entero]])
      iex> {:error, [diagnostico]} = AnchoFijo.Parser.parsear(layout, "CLP001234\\nUSD00056\\n")
      iex> AnchoFijo.Diagnostico.mensaje(diagnostico)
      "línea 2: se esperaban 9 bytes, llegaron 8; posible campo faltante o archivo delimitado"
  """
  @spec parsear(Layout.t() | Enumerable.t(), term(), keyword()) :: resultado()
  def parsear(layout, entrada, opts \\ []) do
    opts = Opciones.validar!(opts, opciones_de_parsear(), "AnchoFijo.parsear/3")
    metadata = %{modo: Keyword.get(opts, :modo, :estricto), desde: Entrada.origen(entrada, opts)}

    Telemetria.span(:parsear, metadata, fn ->
      case preparar_parseo(layout, entrada, opts) do
        {:ok, layout, numeradas} ->
          {resultado, lineas} = procesar(numeradas, layout, metadata.modo)
          {medidas, extra} = Telemetria.medir_parseo(resultado, lineas)
          {resultado, medidas, Map.merge(extra, metadata_de_layout(layout))}

        {:error, diagnosticos} ->
          # La misma forma que un stop exitoso: un handler que lee
          # `metadata.layout` o `medidas.registros` no puede reventar (y ser
          # desenganchado por telemetry) porque el layout no se pudo construir.
          {medidas, extra} = Telemetria.medir_parseo({:error, diagnosticos}, 0)
          {{:error, diagnosticos}, medidas, Map.merge(extra, metadata_de_layout(nil))}
      end
    end)
  end

  defp preparar_parseo(layout, entrada, opts) do
    with {:ok, layout} <- Layout.coercer(layout),
         {:ok, contenido} <- Entrada.leer(entrada, opts) do
      numeradas =
        contenido
        |> numerar(Keyword.get(opts, :traza, false))
        |> seleccionar(opts)

      {:ok, layout, numeradas}
    end
  end

  defp metadata_de_layout(%Layout{} = layout) do
    %{layout: layout.nombre, encoding: layout.encoding, unidad: layout.unidad}
  end

  defp metadata_de_layout(nil), do: %{layout: nil, encoding: nil, unidad: nil}

  # Sin traza, el camino es el de siempre: partir y numerar. Con traza, la
  # tupla lleva la traza en vez del número solo: el offset sale del mismo
  # recorrido lazy que parte las líneas, así que en modo estricto un archivo
  # con la primera fila mala no se parte entero para mirar una. Cada línea
  # es un sub-binario del contenido, sin copia. `parsear_linea/3` recibe el
  # número en los dos casos; la traza se pega al registro al final.
  #
  # Es público (sin doc) porque `AnchoFijo.Multiregistro` numera igual: la
  # traza y el offset de una línea no dependen de cuántos layouts haya.
  @doc false
  @spec numerar(binary(), boolean()) :: Enumerable.t()
  def numerar(contenido, false) do
    contenido |> Entrada.dividir_lazy() |> Stream.with_index(1)
  end

  def numerar(contenido, true) do
    contenido
    |> Entrada.dividir_lazy_con_offset()
    |> Stream.with_index(1)
    |> Stream.map(fn {{linea, offset}, numero} ->
      {linea, Traza.nueva(numero, offset, byte_size(linea))}
    end)
  end

  @doc """
  Igual que `parsear/3`, pero devuelve solo los registros o levanta `AnchoFijo.Error`.

  Para el script de migración, el `Mix.Task` o el pipeline donde un archivo
  malo no deja nada que hacer salvo morir con un mensaje claro. El mensaje de
  la excepción es el reporte de los diagnósticos, el mismo que habría llegado
  en la tupla.

      iex> AnchoFijo.Parser.parsear!([campos: [[nombre: :codigo, largo: 3, tipo: :entero]]], "001\\n002\\n")
      [%{codigo: 1}, %{codigo: 2}]

      iex> AnchoFijo.Parser.parsear!([campos: [[nombre: :codigo, largo: 3, tipo: :entero]]], "001\\nAB2\\n")
      ** (AnchoFijo.Error) línea 2, campo :codigo (posiciones 1-3): se esperaban 3 posiciones con un número entero, llegaron "AB2"; hay caracteres no numéricos o el campo está corrido

  ## Con `modo: :tolerante`

  Levanta igual si alguna fila no se pudo leer, pero la excepción trae **todos**
  los errores del archivo, no el primero. Es la combinación para el script que
  tiene que morir, pero cuyo operador necesita la lista completa para corregir
  el archivo de una vez.

  Lo que el `!` no devuelve son las advertencias: un `relleno_final: :tolerar`
  que completó líneas, por ejemplo. Son filas que se leyeron bien bajo un
  supuesto que el layout declaró, y la función devuelve un solo valor. Si las
  advertencias importan, `parsear/3` las trae en la tercera posición.

      iex> layout = [campos: [[nombre: :codigo, largo: 3, tipo: :entero]]]
      iex> try do
      ...>   AnchoFijo.Parser.parsear!(layout, "001\\nAB2\\n003\\nXYZ\\n", modo: :tolerante)
      ...> rescue
      ...>   e in AnchoFijo.Error -> Enum.map(e.diagnosticos, & &1.linea)
      ...> end
      [2, 4]
  """
  @spec parsear!(Layout.t() | Enumerable.t(), term(), keyword()) :: [registro()]
  def parsear!(layout, entrada, opts \\ []) do
    case parsear(layout, entrada, opts) do
      {:ok, registros, diagnosticos} ->
        case Diagnostico.separar(diagnosticos) do
          {[], _advertencias} -> registros
          {errores, _advertencias} -> raise AnchoFijo.Error, errores
        end

      {:error, diagnosticos} ->
        raise AnchoFijo.Error, diagnosticos
    end
  end

  @doc """
  Versión lazy de `parsear/3`, para archivos que no caben en memoria.

  Devuelve un `Stream` de `{:ok, registro, advertencias}` o
  `{:error, diagnosticos}`, una entrada por línea con contenido. La decisión de
  qué hacer con los errores es del consumidor, que es la única forma honesta de
  ser lazy: acumular todos los diagnósticos de un archivo de 2 GB para
  devolverlos al final anula el punto. Las advertencias viajan pegadas a su
  registro por la misma razón: no hay dónde juntarlas.

      iex> layout = AnchoFijo.Layout.nuevo!(campos: [[nombre: :codigo, largo: 3, tipo: :entero]])
      iex> AnchoFijo.Parser.stream(layout, "001\\n002\\nXYZ\\n") |> Enum.count(&match?({:ok, _, _}, &1))
      2

  Para replicar el modo estricto sobre un stream, corte usted mismo:

      iex> layout = AnchoFijo.Layout.nuevo!(campos: [[nombre: :codigo, largo: 3, tipo: :entero]])
      iex> AnchoFijo.Parser.stream(layout, "001\\n002\\nXYZ\\n004\\n")
      ...> |> Enum.reduce_while([], fn
      ...>   {:ok, registro, _advertencias}, acumulado -> {:cont, [registro | acumulado]}
      ...>   {:error, _diagnosticos}, acumulado -> {:halt, Enum.reverse(acumulado)}
      ...> end)
      [%{codigo: 1}, %{codigo: 2}]

  Acepta un `File.Stream` ya construido, lo que permite elegir el tamaño de
  lectura o leer desde una tubería:

      AnchoFijo.Parser.stream(layout, File.stream!("cartola.txt"))

  Un layout inválido levanta `AnchoFijo.Error` en vez de devolver un stream:
  es un error del programador, no del archivo. Un archivo ilegible sí se
  reporta como dato, en el primer elemento del stream. Y un enumerable que
  entrega algo que no es un binario produce un `{:error, diagnosticos}` en
  esa posición, no una excepción desde el fondo de la implementación:

      iex> layout = AnchoFijo.Layout.nuevo!(campos: [[nombre: :codigo, largo: 3, tipo: :entero]])
      iex> [{:ok, _, _}, {:error, [diagnostico]}] = AnchoFijo.Parser.stream(layout, ["001", 2]) |> Enum.to_list()
      iex> AnchoFijo.Diagnostico.mensaje(diagnostico)
      "entrada, línea 2: se esperaba un binario por elemento del enumerable, llegó 2; el enumerable de entrada no entrega líneas como binarios"

  Con `File.stream!/1` las líneas se cortan solo por `\\n`; si el archivo usa CR
  a secas (Mac clásico, que `detectar/2` identifica), use `parsear/3` o pase
  la ruta con `traza: true`.

  Con `traza: true` y una ruta, `stream/3` lee el archivo en bloques y parte
  las líneas por sí mismo, byte a byte, así que los offsets cuadran con
  cualquier terminador. Con un `File.Stream` construido por el llamador no
  puede: `File.stream!/1` en modo línea convierte CRLF en LF y los offsets
  quedan corridos un byte por línea. Para archivos CRLF, pase la ruta.
  """
  @spec stream(Layout.t() | Enumerable.t(), term(), keyword()) :: Enumerable.t()
  def stream(layout, entrada, opts \\ []) do
    opts = Opciones.validar!(opts, opciones_de_stream(), "AnchoFijo.stream/3")
    layout = coercer!(layout)

    resultados =
      case fuente(entrada, opts) do
        {:ok, lineas} -> encadenar(lineas, layout, opts)
        {:error, diagnosticos} -> [{:error, diagnosticos}]
      end

    metadata = Map.put(metadata_de_layout(layout), :desde, Entrada.origen(entrada, opts))
    Telemetria.instrumentar_stream(resultados, metadata)
  end

  # Con traza, las líneas tienen que llegar con sus bytes exactos para que el
  # offset cuadre; sin traza, el camino de siempre.
  @doc false
  @spec fuente(term(), keyword()) :: {:ok, Enumerable.t()} | {:error, [Diagnostico.t()]}
  def fuente(entrada, opts) do
    if Keyword.get(opts, :traza, false),
      do: Entrada.lineas_con_terminador(entrada, opts),
      else: Entrada.lineas(entrada, opts)
  end

  # La traza en un stream sale sin estado global: el offset viaja en el
  # acumulador de `Stream.transform/3`. Para una ruta o un binario las líneas
  # vienen con sus bytes exactos; para un enumerable del llamador se supone
  # que cada elemento trae su terminador tal cual estaba en el archivo, y la
  # doc avisa que `File.stream!/1` no cumple eso con CRLF.
  @doc false
  @spec numerar_stream(Enumerable.t(), boolean()) :: Enumerable.t()
  def numerar_stream(lineas, false), do: Stream.with_index(lineas, 1)

  def numerar_stream(lineas, true) do
    Stream.transform(lineas, {1, 0}, fn cruda, {numero, offset} ->
      largo = if is_binary(cruda), do: byte_size(Entrada.sin_terminador(cruda)), else: 0
      avance = if is_binary(cruda), do: byte_size(cruda), else: 0
      {[{cruda, Traza.nueva(numero, offset, largo)}], {numero + 1, offset + avance}}
    end)
  end

  @doc """
  Parsea una sola línea, ya sin terminador.

      iex> layout = AnchoFijo.Layout.nuevo!(campos: [[nombre: :a, largo: 2], [nombre: :b, largo: 3, tipo: :entero]])
      iex> AnchoFijo.Parser.parsear_linea(layout, "XY007", 1)
      {:ok, %{a: "XY", b: 7}, []}

  El caso más común: un archivo latin-1 leído con el encoding por default.

      iex> layout = AnchoFijo.Layout.nuevo!(campos: [[nombre: :nombre, largo: 5]])
      iex> {:error, [diagnostico]} = AnchoFijo.Parser.parsear_linea(layout, <<74, 79, 83, 201, 32>>, 3)
      iex> AnchoFijo.Diagnostico.mensaje(diagnostico)
      "línea 3, campo :nombre (posiciones 1-5): se esperaban bytes válidos en utf8, llegaron el byte 0xC9 en la posición 4; el byte 0xC9 no es UTF-8 válido pero sí es un carácter latin-1; declare encoding: :latin1 en el layout"
  """
  @spec parsear_linea(Layout.t(), binary(), pos_integer()) ::
          {:ok, registro(), [Diagnostico.t()]} | {:error, [Diagnostico.t()]}
  def parsear_linea(%Layout{} = layout, cruda, numero) do
    with {:ok, linea} <- preparar(layout, cruda, numero),
         {:ok, linea, advertencias} <- ajustar_largo(layout, linea, numero),
         {:ok, registro, de_los_campos} <- extraer_campos(layout, linea, numero) do
      {:ok, registro, advertencias ++ de_los_campos}
    end
  end

  # Los predicados van en funciones y no en atributos de módulo porque una
  # función anónima no se puede guardar en un atributo. Son públicos (sin
  # doc) porque `AnchoFijo.Multiregistro` recibe exactamente las mismas
  # opciones y las valida con el mismo esquema.
  @doc false
  @spec opciones_de_parsear() :: Opciones.esquema()
  def opciones_de_parsear do
    [{:modo, &(&1 in [:estricto, :tolerante]), ":estricto o :tolerante"} | opciones_de_stream()]
  end

  @doc false
  @spec opciones_de_stream() :: Opciones.esquema()
  def opciones_de_stream do
    [
      {:saltar, &(is_integer(&1) and &1 >= 0), "un entero mayor o igual a cero"},
      {:omitir_vacias, &is_boolean/1, "true o false"},
      {:desde, &(&1 in [:auto, :archivo, :contenido]), ":auto, :archivo o :contenido"},
      {:traza, &is_boolean/1, "true o false"}
    ]
  end

  defp coercer!(layout) do
    case Layout.coercer(layout) do
      {:ok, layout} -> layout
      {:error, diagnosticos} -> raise AnchoFijo.Error, diagnosticos
    end
  end

  defp encadenar(lineas, layout, opts) do
    lineas
    |> numerar_stream(Keyword.get(opts, :traza, false))
    |> Stream.drop(Keyword.get(opts, :saltar, 0))
    |> Stream.map(fn {linea, marca} -> {sin_terminador(linea), marca} end)
    |> descartar_vacias(Keyword.get(opts, :omitir_vacias, true))
    |> Stream.map(fn
      {linea, marca} when is_binary(linea) -> parsear_marcada(layout, linea, marca)
      {otro, marca} -> {:error, [no_es_linea(otro, numero_de(marca))]}
    end)
  end

  # Un `File.Stream` entrega binarios; un enumerable armado por el llamador
  # puede entregar cualquier cosa, y eso se reporta en su posición en vez de
  # reventar en `String.trim_trailing/2`.
  defp sin_terminador(linea) when is_binary(linea), do: Entrada.sin_terminador(linea)
  defp sin_terminador(otro), do: otro

  @doc false
  @spec numero_de(Traza.t() | pos_integer()) :: pos_integer()
  def numero_de(%Traza{linea: numero}), do: numero
  def numero_de(numero), do: numero

  defp no_es_linea(elemento, numero) do
    Diagnostico.nuevo(
      tipo: :entrada,
      linea: numero,
      esperado: "un binario por elemento del enumerable",
      recibido: inspect(elemento),
      causa_probable: "el enumerable de entrada no entrega líneas como binarios"
    )
  end

  # `marca` es el número de línea, o la traza entera cuando se pidió. En el
  # segundo caso el registro sale con la clave reservada.
  defp parsear_marcada(layout, linea, %Traza{} = traza) do
    case parsear_linea(layout, linea, traza.linea) do
      {:ok, registro, advertencias} -> {:ok, Map.put(registro, Traza.clave(), traza), advertencias}
      {:error, diagnosticos} -> {:error, diagnosticos}
    end
  end

  defp parsear_marcada(layout, linea, numero), do: parsear_linea(layout, linea, numero)

  defp descartar_vacias(stream, true) do
    Stream.reject(stream, fn {linea, _marca} -> linea == "" end)
  end

  defp descartar_vacias(stream, _false), do: stream

  @doc false
  @spec seleccionar(Enumerable.t(), keyword()) :: Enumerable.t()
  def seleccionar(numeradas, opts) do
    numeradas
    |> Stream.drop(Keyword.get(opts, :saltar, 0))
    |> descartar_vacias(Keyword.get(opts, :omitir_vacias, true))
  end

  # Las líneas llegan de a una y se cuentan al pasar: en estricto el archivo
  # no se parte entero para mirar las primeras mil, así que la cuenta que
  # sale es la de las líneas leídas, no la del archivo. Devuelve el resultado
  # y esa cuenta, que es lo que `AnchoFijo.Telemetria` mide.
  #
  # En estricto un error aborta el archivo completo y las advertencias de las
  # líneas ya leídas se descartan: no hay resultado parcial que anotar. Las
  # advertencias solo viajan cuando el archivo entero se pudo leer.
  # Una regla que no se cumple es un error que viene con el registro leído:
  # en estricto rechaza la línea, como cualquier otro error.
  defp sin_errores({:ok, registro, diagnosticos}) do
    case Enum.filter(diagnosticos, &(&1.gravedad == :error)) do
      [] -> {:ok, registro, diagnosticos}
      errores -> {:error, errores}
    end
  end

  defp sin_errores(otro), do: otro

  defp procesar(numeradas, layout, :estricto) do
    resultado =
      Enum.reduce_while(numeradas, {[], [], 0}, fn {linea, marca},
                                                   {registros, advertencias, lineas} ->
        case parsear_marcada(layout, linea, marca) |> sin_errores() do
          {:ok, registro, nuevas} ->
            {:cont, {[registro | registros], apilar(nuevas, advertencias), lineas + 1}}

          {:error, diagnosticos} ->
            {:halt, {:error, diagnosticos, lineas + 1}}
        end
      end)

    case resultado do
      {:error, diagnosticos, lineas} ->
        {{:error, diagnosticos}, lineas}

      {registros, advertencias, lineas} ->
        {{:ok, Enum.reverse(registros), Enum.reverse(advertencias)}, lineas}
    end
  end

  defp procesar(numeradas, layout, :tolerante) do
    {registros, diagnosticos, lineas} =
      Enum.reduce(numeradas, {[], [], 0}, fn {linea, marca}, {registros, diagnosticos, lineas} ->
        case parsear_marcada(layout, linea, marca) do
          {:ok, registro, nuevas} ->
            {[registro | registros], apilar(nuevas, diagnosticos), lineas + 1}

          {:error, nuevos} ->
            {registros, apilar(nuevos, diagnosticos), lineas + 1}
        end
      end)

    {{:ok, Enum.reverse(registros), Enum.reverse(diagnosticos)}, lineas}
  end

  defp apilar([], acumulados), do: acumulados
  defp apilar(nuevos, acumulados), do: Enum.reverse(nuevos) ++ acumulados

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

  defp ajustar_largo(%Layout{} = layout, linea, numero) do
    encontrado = medida(layout, linea)

    cond do
      encontrado == layout.largo ->
        {:ok, linea, []}

      encontrado < layout.largo and layout.relleno_final == :tolerar ->
        completar_relleno(layout, linea, encontrado, numero)

      true ->
        {:error, [desajuste_de_largo(layout, encontrado, numero)]}
    end
  end

  # Una línea corta se completa solo si lo que falta es relleno: el tramo
  # faltante tiene que caber entero en la zona tolerable del final de la línea.
  # Si alcanza a un campo que no es relleno, completar no repone el dato, lo
  # inventa, y eso es exactamente el error silencioso que este paquete existe
  # para impedir.
  defp completar_relleno(%Layout{} = layout, linea, encontrado, numero) do
    faltan = layout.largo - encontrado
    {tolerables, caracter} = zona_tolerable(layout)

    if faltan <= tolerables do
      {:ok, linea <> String.duplicate(caracter, faltan),
       [relleno_completado(layout, encontrado, faltan, numero)]}
    else
      {:error, [relleno_insuficiente(layout, encontrado, faltan, tolerables, numero)]}
    end
  end

  # Cuántas unidades del final de la línea son relleno reponible, y con qué
  # carácter. La zona empieza en el final y crece hacia atrás: primero lo que
  # el layout no declara (el relleno después del último campo, y los huecos
  # entre campos: nadie los lee), después los campos de atrás hacia adelante
  # mientras sean `:texto` con el mismo carácter de relleno.
  #
  # Solo `:texto` y `:relleno`, y sin mirar su `:trim`: un emisor que recorta espacios
  # finales produce una línea corta exactamente cuando el original terminaba
  # en relleno, y reponerlo reconstruye el original byte a byte. En un
  # `:entero`, un `:decimal` o una `:fecha` el final de la línea son dígitos:
  # si faltan, la explicación probable es un dato truncado, no relleno
  # recortado, y completar con espacios lo taparía.
  #
  # Un `:texto` que queda entero en blanco sí cuenta: `Campo.extraer/3` lo lee
  # como `""` o `nil`, que es lo mismo que habría dado la línea completa.
  defp zona_tolerable(%Layout{campos: campos, largo: largo, unidad: unidad} = layout) do
    inicial = %{unidades: 0, caracter: nil, inicio_siguiente: largo + 1, cerrada: false}

    zona =
      campos
      |> Enum.reverse()
      |> Enum.reduce_while(inicial, fn campo, zona ->
        zona = sumar_no_declarado(zona, Campo.fin(campo))
        relleno = relleno_reponible(campo, layout, unidad)

        cond do
          not (Campo.texto?(campo) or Campo.relleno?(campo)) -> {:halt, cerrar(zona)}
          relleno == :error -> {:halt, cerrar(zona)}
          zona.caracter in [nil, relleno] -> {:cont, sumar_campo(zona, campo, relleno)}
          true -> {:halt, cerrar(zona)}
        end
      end)
      |> case do
        # Ningún campo cortó la zona: lo que haya antes del primero
        # tampoco lo lee nadie.
        %{cerrada: false} = zona -> sumar_no_declarado(zona, 0)
        zona -> zona
      end

    {zona.unidades, zona.caracter || " "}
  end

  defp cerrar(zona), do: %{zona | cerrada: true}

  defp sumar_no_declarado(zona, fin_del_campo) do
    %{zona | unidades: zona.unidades + (zona.inicio_siguiente - fin_del_campo - 1)}
  end

  defp sumar_campo(zona, %Campo{} = campo, relleno) do
    %{
      zona
      | unidades: zona.unidades + campo.largo,
        caracter: relleno,
        inicio_siguiente: campo.posicion
    }
  end

  # El relleno del campo como hay que pegarlo a la línea, o `:error` si no se
  # puede reponer. Con `unidad: :bytes` la línea todavía está en su encoding
  # original y el faltante se mide en bytes: el relleno se transcodifica al
  # encoding del campo (o del layout) y tiene que quedar en un byte; en
  # latin-1 cualquier carácter hasta U+00FF lo es, en UTF-8 solo ASCII. Con
  # `:caracteres` la línea ya es UTF-8 y cualquier carácter sirve.
  defp relleno_reponible(%Campo{relleno: relleno}, _layout, :caracteres), do: relleno

  defp relleno_reponible(%Campo{relleno: relleno} = campo, %Layout{} = layout, :bytes) do
    case {campo.encoding || layout.encoding, :unicode.characters_to_binary(relleno, :utf8, :latin1)} do
      {:latin1, <<byte>>} -> <<byte>>
      {:latin1, _no_cabe} -> :error
      {_utf8, _} when byte_size(relleno) == 1 -> relleno
      {_utf8, _} -> :error
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

  defp relleno_completado(%Layout{} = layout, encontrado, faltan, numero) do
    unidad = Campo.nombre_unidad(layout.unidad)

    Diagnostico.nuevo(
      tipo: :relleno_completado,
      gravedad: :advertencia,
      linea: numero,
      esperado: "#{layout.largo} #{unidad}",
      recibido: encontrado,
      causa_probable:
        "se completaron #{faltan} #{unidad} de relleno al final de la línea; " <>
          "el emisor recorta los espacios finales y el layout lo tolera"
    )
  end

  defp relleno_insuficiente(%Layout{} = layout, encontrado, faltan, tolerables, numero) do
    unidad = Campo.nombre_unidad(layout.unidad)

    Diagnostico.nuevo(
      tipo: :largo_de_linea,
      linea: numero,
      esperado: "#{layout.largo} #{unidad}",
      recibido: encontrado,
      causa_probable:
        "faltan #{faltan} #{unidad} y solo #{tolerables} son relleno reponible: " <>
          "el tramo que falta alcanza a un campo cuyo ancho es parte del dato, " <>
          "así que completarlo lo inventaría"
    )
  end

  defp causa_de_largo(encontrado, esperado) when encontrado < esperado do
    "posible campo faltante o archivo delimitado"
  end

  defp causa_de_largo(_encontrado, _esperado) do
    "posible campo extra, relleno no declarado, o un terminador de línea " <>
      "distinto del que se usó para cortar las líneas"
  end

  defp extraer_campo(%Campo{} = campo, linea, contexto, {valores, diagnosticos, advertencias}) do
    resultado =
      if Campo.anidado?(campo),
        do: Anidados.leer(campo, linea, contexto, Map.new(valores)),
        else: plano(Campo.leer(campo, linea, contexto))

    case resultado do
      {:ok, valor, nuevas} ->
        {[{campo.nombre, valor} | valores], diagnosticos, Enum.reverse(nuevas, advertencias)}

      {:error, nuevos} ->
        {valores, Enum.reverse(nuevos, diagnosticos), advertencias}
    end
  end

  defp plano({:ok, valor, advertencias}), do: {:ok, valor, advertencias}
  defp plano({:error, diagnostico}), do: {:error, [diagnostico]}

  defp extraer_campos(%Layout{} = layout, linea, numero) do
    contexto = Layout.contexto(layout, numero)

    # Un :relleno no se lee ni va al registro: nadie se compromete a lo que
    # hay en esas posiciones.
    {valores, diagnosticos, advertencias} =
      Enum.reduce(layout.campos, {[], [], []}, fn campo, acumulado ->
        if Campo.relleno?(campo),
          do: acumulado,
          else: extraer_campo(campo, linea, contexto, acumulado)
      end)

    case diagnosticos do
      [] ->
        registro = Map.new(valores)

        {:ok, registro,
         Enum.reverse(advertencias) ++ Reglas.cruzadas(layout.campos, registro, contexto)}

      diagnosticos ->
        {:error, Enum.reverse(diagnosticos)}
    end
  end
end
