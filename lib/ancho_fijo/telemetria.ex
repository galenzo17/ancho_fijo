defmodule AnchoFijo.Telemetria do
  @moduledoc """
  Los eventos de `:telemetry` que emite la librería. Son parte de la API:
  cambiarle el nombre a uno rompe los dashboards de quien lo mira.

  Para recibirlos hay que tener `{:telemetry, "~> 1.3"}` en las dependencias
  del proyecto. Es una dependencia **opcional** de `ancho_fijo`: sin ella no
  se emite nada, no se carga nada y el paquete sigue sin dependencias de
  runtime. Si se agrega después de haber compilado `ancho_fijo`, hay que
  recompilarlo (`mix deps.compile ancho_fijo --force`), porque la decisión de
  emitir o no se toma al compilar.

  Suscribirse son tres líneas:

      :telemetry.attach("nomina", [:ancho_fijo, :parsear, :stop], fn _evento, medidas, metadata, _config ->
        Logger.info("nómina \#{metadata.layout}: \#{medidas.registros} registros en \#{medidas.duration} ns")
      end, nil)

  ## Eventos

  Todos los nombres empiezan con `:ancho_fijo`. Los de `parsear/3` y
  `detectar/2` siguen el patrón `start`/`stop`/`exception` de
  `:telemetry.span/3`; el de `stream/3` emite `start` y `stop` por sí mismo,
  porque un stream no tiene una función que envolver.

  ### `[:ancho_fijo, :parsear, :start]`

  Al entrar a `AnchoFijo.parsear/3`.

    * Medidas: `system_time`, `monotonic_time`.
    * Metadata: `telemetry_span_context`, más `:modo` (`:estricto` o
      `:tolerante`) y `:desde` (`:archivo` o `:contenido`).

  ### `[:ancho_fijo, :parsear, :stop]`

  Al salir, con éxito o con `{:error, _}`.

    * Medidas: `duration`, `monotonic_time`, `lineas` (las que se
      leyeron, después de `:saltar` y `:omitir_vacias`; en `:estricto` un
      error corta ahí y las que siguen no se cuentan), `registros`,
      `errores` y `advertencias`. Siempre las cinco: si el layout o la entrada
      no se pudieron leer, `lineas` y `registros` son `0` y `errores` cuenta
      los diagnósticos.
    * Metadata: la de `start` más `:resultado` (`:ok` o `:error`), `:layout`
      (el `:nombre` del layout), `:encoding` y `:unidad`. Las tres son `nil`
      cuando el layout no se pudo construir. Un handler puede leer cualquier
      clave documentada sin chequear si existe.

  ### `[:ancho_fijo, :parsear, :exception]`

  Si `parsear/3` levanta. No debería: toda falla es un diagnóstico. Si pasa,
  es un bug, y el evento trae `kind`, `reason` y `stacktrace` como todo
  `:telemetry.span/3`.

  ### `[:ancho_fijo, :detectar, :start]` y `[:ancho_fijo, :detectar, :stop]`

  Igual que `parsear`. En `stop`: medidas `duration`, `monotonic_time`,
  `lineas` (analizadas) y `bytes` (de la muestra), en cero si la entrada no
  se pudo leer; metadata `:desde`, `:resultado` y
  `:probablemente_ancho_fijo?` (`nil` con `:resultado` `:error`). Y
  `:exception` con el mismo contrato.

  ### `[:ancho_fijo, :stream, :start]` y `[:ancho_fijo, :stream, :stop]`

  `start` se emite cuando **empieza la enumeración**, no cuando se construye
  el stream: hasta entonces no pasó nada. `stop` se emite cuando la
  enumeración termina o se corta (`Enum.take/2`, `Stream.take_while/2`), con
  lo que se contó hasta ahí.

    * Medidas en `stop`: `duration`, `lineas`, `registros`, `errores`,
      `advertencias`.
    * Metadata: `:layout`, `:encoding`, `:unidad`, `:desde`.

  Las cuentas viven en el acumulador del stream, cuatro enteros: la
  instrumentación no acumula registros ni rompe la memoria constante.

  ### `[:ancho_fijo, :escribir, :start]`, `:stop` y `:exception`

  `AnchoFijo.escribir/3`, con el patrón de `parsear`. En `start`, la
  metadata trae `:terminador` y `:truncar`. En `stop`: medidas `duration`,
  `lineas` (los registros que se intentaron escribir), `registros` (los
  que se escribieron; `0` si el resultado es `{:error, _}`, porque no se
  escribe nada), `errores` y `advertencias`; metadata `:resultado`,
  `:layout`, `:encoding` y `:unidad`, `nil` las tres si el layout no se
  pudo construir.

  ### `[:ancho_fijo, :escribir_stream, :start]` y `:stop`

  `AnchoFijo.Escritor.stream/3`, con el contrato de `stream`: `start` al
  empezar la enumeración, `stop` al terminar o cortarse, y las mismas
  cuentas. La metadata es la de `escribir`.

  ### Con un `AnchoFijo.Multiregistro`

  `parsear/3` y `stream/3` con un multiregistro emiten los mismos eventos,
  con las mismas medidas. En la metadata, `:layout` es el `:nombre` del
  multiregistro (o `nil`), y `:encoding` y `:unidad` son `nil`: cada tipo
  de registro tiene su layout y no hay un solo valor que declarar. Los
  diagnósticos de cierre (un trailer que falta, un total que no cuadra)
  cuentan en `errores` pero no en `lineas`: no son una línea del archivo.

  ## Lo que no se emite, a propósito

  No hay un evento por línea que falla. En un archivo con 10.000 filas malas
  serían 10.000 eventos en el handler, y cada uno llevaría el diagnóstico,
  que puede traer datos personales (ver `AnchoFijo.Diagnostico`). El volumen
  de errores va en las medidas de `stop`; el detalle de cada uno ya está en
  los diagnósticos que la función devuelve, que son datos y no eventos.
  """

  @typedoc "Lo que devuelve la función envuelta: resultado, medidas extra y metadata extra."
  @type salida :: {term(), map(), map()}

  # La decisión de emitir o no se toma al compilar: si `:telemetry` no está
  # entre las dependencias del proyecto que compila `ancho_fijo`, estas
  # funciones son el camino directo, sin una sola llamada ni un `if` en
  # runtime. `Code.ensure_loaded?/1` acá adentro corre en tiempo de
  # compilación porque está en el cuerpo del módulo, no de una función.
  if Code.ensure_loaded?(:telemetry) do
    @prefijo :ancho_fijo

    @doc """
    Envuelve `fun` en un `:telemetry.span/3` bajo `[:ancho_fijo, nombre]`.

    `fun` devuelve `{resultado, medidas_extra, metadata_extra}`; el resultado
    es lo que se devuelve al llamador. `span/3` existe en vez de escribir el
    par `start`/`stop` a mano porque garantiza el `stop` o el `exception`
    pase lo que pase adentro, y mide la duración con el reloj monotónico.
    """
    @spec span(atom(), map(), (-> salida())) :: term()
    def span(nombre, metadata, fun) do
      :telemetry.span([@prefijo, nombre], metadata, fn ->
        {resultado, medidas, metadata_extra} = fun.()
        {resultado, medidas, Map.merge(metadata, metadata_extra)}
      end)
    end

    @doc false
    @spec emitir([atom()], map(), map()) :: :ok
    def emitir(nombre, medidas, metadata),
      do: :telemetry.execute([@prefijo | nombre], medidas, metadata)

    @doc "Si `:telemetry` estaba disponible cuando se compiló la librería."
    def disponible?, do: true
  else
    @spec span(atom(), map(), (-> salida())) :: term()
    def span(_nombre, _metadata, fun) do
      {resultado, _medidas, _metadata} = fun.()
      resultado
    end

    @doc false
    @spec emitir([atom()], map(), map()) :: :ok
    def emitir(_nombre, _medidas, _metadata), do: :ok

    def disponible?, do: false
  end

  @doc """
  Instrumenta un stream de resultados de `AnchoFijo.stream/3` con `start`
  al empezar la enumeración y `stop` al terminar o cortarse.

  Las cuentas viajan en el acumulador: cuatro enteros y el instante de inicio.
  """
  @spec instrumentar_stream(Enumerable.t(), map(), atom()) :: Enumerable.t()
  def instrumentar_stream(stream, metadata, nombre \\ :stream) do
    Stream.transform(
      stream,
      fn -> iniciar_cuentas(metadata, nombre) end,
      fn resultado, cuentas -> {[resultado], contar(resultado, cuentas)} end,
      fn cuentas -> cerrar_cuentas(cuentas, metadata, nombre) end
    )
  end

  # Las tres piezas de `instrumentar_stream/2` por separado, para un stream
  # que ya tiene su propio acumulador (`AnchoFijo.Multiregistro`, que lleva
  # el estado de la estructura) y emite elementos de cierre que no son
  # líneas.

  @doc false
  @spec iniciar_cuentas(map(), atom()) :: map()
  def iniciar_cuentas(metadata, nombre \\ :stream) do
    emitir([nombre, :start], %{system_time: System.system_time()}, metadata)
    %{inicio: System.monotonic_time(), lineas: 0, registros: 0, errores: 0, advertencias: 0}
  end

  @doc false
  @spec contar(term(), map()) :: map()
  def contar({:ok, _registro, advertencias}, cuentas) do
    %{
      cuentas
      | lineas: cuentas.lineas + 1,
        registros: cuentas.registros + 1,
        advertencias: cuentas.advertencias + length(advertencias)
    }
  end

  def contar({:error, diagnosticos}, cuentas) do
    %{cuentas | lineas: cuentas.lineas + 1, errores: cuentas.errores + length(diagnosticos)}
  end

  @doc false
  # Diagnósticos que no vienen de una línea: los del cierre de un multiregistro.
  @spec contar_cierre([term()], map()) :: map()
  def contar_cierre(diagnosticos, cuentas) do
    %{cuentas | errores: cuentas.errores + length(diagnosticos)}
  end

  @doc false
  @spec cerrar_cuentas(map(), map(), atom()) :: :ok
  def cerrar_cuentas(cuentas, metadata, nombre \\ :stream) do
    {inicio, medidas} = Map.pop(cuentas, :inicio)
    duracion = System.monotonic_time() - inicio
    emitir([nombre, :stop], Map.put(medidas, :duration, duracion), metadata)
  end

  @doc false
  # Medidas y metadata de un resultado de `parsear/3`, para el `stop`.
  @spec medir_parseo(term(), non_neg_integer()) :: {map(), map()}
  def medir_parseo({:ok, registros, diagnosticos}, lineas) do
    {errores, advertencias} = Enum.split_with(diagnosticos, &(&1.gravedad == :error))

    {%{
       lineas: lineas,
       registros: length(registros),
       errores: length(errores),
       advertencias: length(advertencias)
     }, %{resultado: :ok}}
  end

  def medir_parseo({:error, diagnosticos}, lineas) do
    {%{lineas: lineas, registros: 0, errores: length(diagnosticos), advertencias: 0},
     %{resultado: :error}}
  end
end
