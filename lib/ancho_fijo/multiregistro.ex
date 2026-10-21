defmodule AnchoFijo.Multiregistro do
  @moduledoc """
  Un archivo con varios tipos de registro: header, detalle, trailer.

  Es lo que piden las cartolas y las nóminas bancarias reales: cada línea
  dice qué es en sus primeras posiciones, cada tipo tiene su propio layout,
  el orden importa, y el trailer trae totales que tienen que cuadrar con los
  detalles. Un `Multiregistro` es un layout de layouts más esas reglas.

      iex> multi = AnchoFijo.Multiregistro.nuevo!(
      ...>   discriminador: [posicion: 1, largo: 2],
      ...>   registros: [
      ...>     header: [valor: "01", cantidad: :uno, layout: [campos: [[nombre: :tipo, largo: 2], [nombre: :fecha, largo: 8, tipo: :fecha, formato: :aaaammdd]]]],
      ...>     detalle: [valor: "02", cantidad: :varios, layout: [campos: [[nombre: :tipo, largo: 2], [nombre: :monto, largo: 8, tipo: :entero]]]],
      ...>     trailer: [valor: "09", cantidad: :uno, layout: [campos: [[nombre: :tipo, largo: 2], [nombre: :cantidad, largo: 3, tipo: :entero], [nombre: :total, largo: 8, tipo: :entero]]]]
      ...>   ],
      ...>   controles: [
      ...>     [en: :trailer, campo: :cantidad, cuenta: :detalle],
      ...>     [en: :trailer, campo: :total, suma: {:detalle, :monto}]
      ...>   ]
      ...> )
      iex> contenido = "0120240131\\n0200001000\\n0200000250\\n0900200001250\\n"
      iex> {:ok, registros, []} = AnchoFijo.parsear(multi, contenido)
      iex> Enum.map(registros, fn {tipo, _registro} -> tipo end)
      [:header, :detalle, :detalle, :trailer]
      iex> AnchoFijo.Multiregistro.agrupar(multi, registros).trailer.total
      1250

  ## La definición

    * `:nombre` — opcional, para los mensajes y la telemetría, como el
      `:nombre` de un `AnchoFijo.Layout`.
    * `:discriminador` — `[posicion: 1, largo: 2]`: dónde dice cada línea
      qué es, en bytes de la línea cruda.
    * `:registros` — una keyword list de tipo a definición, en el orden
      esperado en el archivo. Cada definición tiene `:valor` (lo que trae el
      discriminador, o una lista de valores si el tipo admite varios),
      `:layout` (un `AnchoFijo.Layout` o su definición) y `:cantidad`:
      `:uno` (exactamente uno), `:opcional` (cero o uno), `:varios` (cero o
      más) o `:al_menos_uno`.
    * `:orden` — `:estricto` (default): los tipos aparecen en el orden de
      `:registros`. `:libre`: cualquier orden; solo se verifican las
      cantidades. Es para los formatos con lotes que se repiten (NACHA), donde
      la estructura anidada se valida aparte.
    * `:controles` — lista de `[en: tipo, campo: nombre, cuenta: tipo]` o
      `[en: tipo, campo: nombre, suma: {tipo, campo}]`. El campo del registro
      `en:` tiene que valer la cantidad de registros de ese tipo, o la suma
      de ese campo en ellos. Las sumas son sobre enteros o sobre
      `{unidades, precision}`, nunca floats, y con precisiones distintas se
      comparan a la mayor.

  Una clave que no es ninguna de estas es un diagnóstico `:layout`, no se
  ignora: `controls:` en vez de `controles:` dejaría el trailer sin
  verificar y nadie se enteraría.

  ## Las opciones

  `parsear/3` y `stream/3` reciben exactamente las opciones de
  `AnchoFijo.parsear/3` y `AnchoFijo.stream/3`: `:modo`, `:saltar`,
  `:omitir_vacias`, `:desde` y `:traza`. Con `traza: true` cada mapa trae
  `:__traza__` con la línea, el offset y el largo, igual que con un layout
  plano. Una opción desconocida o con un valor de otro tipo es un
  `ArgumentError`, y los eventos de `AnchoFijo.Telemetria` se emiten igual.

  ## Lo que devuelve

  `parsear/3` devuelve `{:ok, registros, diagnosticos}` donde cada registro
  es `{tipo, mapa}`, **en el orden del archivo**. Es una lista y no un mapa
  por tipo porque el orden es parte del dato (un formato puede intercalar
  tipos) y porque es lo que `stream/3` puede emitir de a uno. Para el caso
  común, `agrupar/2` arma `%{header: mapa, detalle: [mapas], trailer: mapa}`.

  ## Los diagnósticos

  Además de los de cada línea, que son los de `AnchoFijo.parsear/3`:

    * `:estructura` — un discriminador que no corresponde a ningún tipo, un
      registro fuera de orden (un `:detalle` después del `:trailer`), uno
      repetido cuando la cantidad es `:uno`, o uno obligatorio que falta al
      llegar al fin del archivo.
    * `:control` — un total del trailer que no cuadra. Dice el valor
      esperado, el que llegó y de qué se calculó.

  En modo `:estricto` el primero corta. En `:tolerante` salen todos; los
  controles se calculan sobre los registros que sí se pudieron leer, así que
  un detalle ilegible produce su diagnóstico **y** el del total que no
  cuadra. Es a propósito: los dos son ciertos, y el segundo es el que el
  banco va a reportar.

  ## En un stream

  `stream/3` emite `{:ok, {tipo, registro}, advertencias}` o
  `{:error, diagnosticos}` por línea, con la estructura verificada al pasar.
  Los controles necesitan todos los detalles, así que salen **al final del
  stream**, como un último elemento `{:error, diagnosticos}` si algo no
  cuadra o si falta un registro obligatorio, y nada si todo cuadra. El
  estado que viaja en el acumulador son las cuentas y las sumas, no los
  registros: la memoria sigue siendo constante.
  """

  alias AnchoFijo.Diagnostico
  alias AnchoFijo.Entrada
  alias AnchoFijo.Layout
  alias AnchoFijo.Opciones
  alias AnchoFijo.Parser
  alias AnchoFijo.Telemetria
  alias AnchoFijo.Traza

  @cantidades [:uno, :opcional, :varios, :al_menos_uno]
  @claves [:nombre, :discriminador, :registros, :controles, :orden]

  @type cantidad :: :uno | :opcional | :varios | :al_menos_uno
  @type tipo :: atom()
  @type registro :: {tipo(), Parser.registro()}

  @type definicion :: %{valores: [binary()], layout: Layout.t(), cantidad: cantidad()}

  @type control ::
          %{en: tipo(), campo: atom(), cuenta: tipo()}
          | %{en: tipo(), campo: atom(), suma: {tipo(), atom()}}

  @type t :: %__MODULE__{
          nombre: String.t() | nil,
          discriminador: %{posicion: pos_integer(), largo: pos_integer()},
          registros: [{tipo(), definicion()}],
          controles: [control()],
          orden: :estricto | :libre
        }

  @enforce_keys [:discriminador, :registros]
  defstruct nombre: nil, discriminador: nil, registros: [], controles: [], orden: :estricto

  # ------------------------------------------------------------- definición

  @doc """
  Valida y construye la definición. Devuelve `{:ok, multi}` o
  `{:error, diagnosticos}` con todos los problemas.

      iex> {:error, [d]} = AnchoFijo.Multiregistro.nuevo(discriminador: [posicion: 1, largo: 2], registros: [])
      iex> AnchoFijo.Diagnostico.mensaje(d)
      "layout: se esperaba al menos un tipo de registro en :registros, llegó una lista vacía"
  """
  @spec nuevo(keyword() | map()) :: {:ok, t()} | {:error, [Diagnostico.t()]}
  def nuevo(definicion) do
    with {:ok, definicion} <- a_mapa(definicion),
         :ok <- sin_claves_desconocidas(definicion),
         {:ok, nombre} <- validar_nombre(Map.get(definicion, :nombre)),
         {:ok, discriminador} <- validar_discriminador(Map.get(definicion, :discriminador)),
         {:ok, registros} <- validar_registros(Map.get(definicion, :registros, []), discriminador),
         {:ok, controles} <- validar_controles(Map.get(definicion, :controles, []), registros),
         {:ok, orden} <- validar_orden(Map.get(definicion, :orden, :estricto)) do
      {:ok,
       %__MODULE__{
         nombre: nombre,
         discriminador: discriminador,
         registros: registros,
         controles: controles,
         orden: orden
       }}
    end
  end

  defp a_mapa(definicion) do
    case Opciones.a_mapa(definicion) do
      {:ok, mapa} ->
        {:ok, mapa}

      :error ->
        {:error, [falla("la definición como keyword list o mapa", inspect(definicion), nil)]}
    end
  end

  defp sin_claves_desconocidas(definicion) do
    case Opciones.claves_desconocidas(definicion, @claves) do
      [] ->
        :ok

      [clave | _] ->
        {:error,
         [
           falla(
             "opciones en #{inspect(@claves)}",
             inspect(clave),
             "la opción no existe y se ignoraría en silencio; probablemente un error de tipeo"
           )
         ]}
    end
  end

  defp validar_nombre(nombre) when is_nil(nombre) or is_binary(nombre), do: {:ok, nombre}
  defp validar_nombre(otro), do: {:error, [falla("un :nombre binario", inspect(otro), nil)]}

  defp validar_orden(orden) when orden in [:estricto, :libre], do: {:ok, orden}
  defp validar_orden(otro), do: {:error, [falla(":orden :estricto o :libre", inspect(otro), nil)]}

  @doc "Como `nuevo/1`, pero levanta `AnchoFijo.Error`."
  @spec nuevo!(keyword() | map()) :: t()
  def nuevo!(definicion) do
    case nuevo(definicion) do
      {:ok, multi} -> multi
      {:error, diagnosticos} -> raise AnchoFijo.Error, diagnosticos
    end
  end

  defp validar_discriminador(nil),
    do: {:error, [falla("un :discriminador con :posicion y :largo", nil, nil)]}

  defp validar_discriminador(discriminador) do
    posicion = get(discriminador, :posicion, 1)
    largo = get(discriminador, :largo)

    if is_integer(posicion) and posicion > 0 and is_integer(largo) and largo > 0 do
      {:ok, %{posicion: posicion, largo: largo}}
    else
      {:error,
       [
         falla(
           "un :discriminador con :posicion entera 1-based y :largo mayor que cero",
           inspect(discriminador),
           nil
         )
       ]}
    end
  end

  defp validar_registros([], _discriminador) do
    {:error, [falla("al menos un tipo de registro en :registros", "una lista vacía", nil)]}
  end

  defp validar_registros(registros, discriminador) when is_list(registros) do
    {definiciones, diagnosticos} =
      Enum.reduce(registros, {[], []}, fn
        {tipo, definicion}, {definiciones, diagnosticos} when is_atom(tipo) ->
          case validar_registro(tipo, definicion, discriminador) do
            {:ok, definicion} -> {[{tipo, definicion} | definiciones], diagnosticos}
            {:error, nuevos} -> {definiciones, diagnosticos ++ nuevos}
          end

        otro, {definiciones, diagnosticos} ->
          {definiciones,
           diagnosticos ++ [falla("pares tipo: definición en :registros", inspect(otro), nil)]}
      end)

    definiciones = Enum.reverse(definiciones)

    case diagnosticos ++ valores_repetidos(definiciones) do
      [] -> {:ok, definiciones}
      diagnosticos -> {:error, diagnosticos}
    end
  end

  defp validar_registros(otro, _discriminador) do
    {:error, [falla("una keyword list en :registros", inspect(otro), nil)]}
  end

  defp validar_registro(tipo, definicion, discriminador) do
    valores = definicion |> get(:valor) |> List.wrap()
    cantidad = get(definicion, :cantidad, :varios)

    problemas =
      Enum.concat([
        if(
          valores != [] and
            Enum.all?(valores, &(is_binary(&1) and byte_size(&1) == discriminador.largo)),
          do: [],
          else: [
            falla(
              "un :valor binario (o una lista de ellos) de #{discriminador.largo} bytes para " <>
                "#{inspect(tipo)}, el largo del discriminador",
              inspect(get(definicion, :valor)),
              nil
            )
          ]
        ),
        if(cantidad in @cantidades,
          do: [],
          else: [
            falla(
              ":cantidad en #{inspect(@cantidades)} para #{inspect(tipo)}",
              inspect(cantidad),
              nil
            )
          ]
        )
      ])

    case {problemas, Layout.coercer(get(definicion, :layout))} do
      {[], {:ok, layout}} ->
        {:ok, %{valores: valores, layout: layout, cantidad: cantidad}}

      {problemas, {:ok, _layout}} ->
        {:error, problemas}

      {problemas, {:error, del_layout}} ->
        {:error,
         problemas ++
           Enum.map(del_layout, fn %Diagnostico{} = d ->
             %Diagnostico{d | campo: d.campo || tipo}
           end)}
    end
  end

  defp valores_repetidos(definiciones) do
    definiciones
    |> Enum.flat_map(fn {tipo, d} -> Enum.map(d.valores, &{&1, tipo}) end)
    |> Enum.group_by(fn {valor, _tipo} -> valor end, fn {_valor, tipo} -> tipo end)
    |> Enum.filter(fn {_valor, tipos} -> length(tipos) > 1 end)
    |> Enum.map(fn {valor, tipos} ->
      falla(
        "un :valor distinto por tipo de registro",
        "#{inspect(valor)} en #{Enum.map_join(tipos, " y ", &inspect/1)}",
        "dos tipos con el mismo discriminador no se pueden distinguir"
      )
    end)
  end

  defp validar_controles(controles, registros) when is_list(controles) do
    {validos, diagnosticos} =
      Enum.reduce(controles, {[], []}, fn control, {validos, diagnosticos} ->
        case validar_control(control, registros) do
          {:ok, control} -> {[control | validos], diagnosticos}
          {:error, diagnostico} -> {validos, [diagnostico | diagnosticos]}
        end
      end)

    case diagnosticos do
      [] -> {:ok, Enum.reverse(validos)}
      diagnosticos -> {:error, Enum.reverse(diagnosticos)}
    end
  end

  defp validar_controles(otro, _registros),
    do: {:error, [falla("una lista en :controles", inspect(otro), nil)]}

  defp validar_control(control, registros) do
    en = get(control, :en)
    campo = get(control, :campo)

    cond do
      not tiene_campo?(registros, en, campo) ->
        {:error,
         falla(
           "un control con :en y :campo que existan en el layout de ese tipo",
           inspect(control),
           "el tipo #{inspect(en)} no está en :registros o su layout no tiene el campo #{inspect(campo)}"
         )}

      is_atom(get(control, :cuenta)) and not is_nil(get(control, :cuenta)) ->
        cuenta = get(control, :cuenta)

        if Keyword.has_key?(registros, cuenta),
          do: {:ok, %{en: en, campo: campo, cuenta: cuenta}},
          else: {:error, falla("un tipo declarado en :cuenta", inspect(cuenta), nil)}

      match?({t, c} when is_atom(t) and is_atom(c), get(control, :suma)) ->
        {tipo, sumado} = get(control, :suma)

        if tiene_campo?(registros, tipo, sumado),
          do: {:ok, %{en: en, campo: campo, suma: {tipo, sumado}}},
          else:
            {:error, falla("un {tipo, campo} declarados en :suma", inspect({tipo, sumado}), nil)}

      true ->
        {:error, falla("un control con :cuenta o con :suma", inspect(control), nil)}
    end
  end

  defp tiene_campo?(registros, tipo, campo) do
    case Keyword.fetch(registros, tipo) do
      {:ok, %{layout: layout}} -> is_atom(campo) and Enum.any?(layout.campos, &(&1.nombre == campo))
      :error -> false
    end
  end

  defp get(definicion, clave, default \\ nil)

  defp get(definicion, clave, default) when is_list(definicion),
    do: Keyword.get(definicion, clave, default)

  defp get(definicion, clave, default) when is_map(definicion),
    do: Map.get(definicion, clave, default)

  defp get(_otro, _clave, default), do: default

  defp falla(esperado, recibido, causa) do
    Diagnostico.nuevo(tipo: :layout, esperado: esperado, recibido: recibido, causa_probable: causa)
  end

  # ----------------------------------------------------------------- lectura

  @doc """
  Parsea un archivo completo. Mismas opciones que `AnchoFijo.parsear/3`.

  Devuelve `{:ok, registros, diagnosticos}` con cada registro como
  `{tipo, mapa}` en el orden del archivo, o `{:error, diagnosticos}` en modo
  estricto.
  """
  @spec parsear(t(), term(), keyword()) ::
          {:ok, [registro()], [Diagnostico.t()]} | {:error, [Diagnostico.t()]}
  def parsear(%__MODULE__{} = multi, entrada, opts \\ []) do
    opts = Opciones.validar!(opts, Parser.opciones_de_parsear(), "AnchoFijo.parsear/3")
    modo = Keyword.get(opts, :modo, :estricto)
    metadata = %{modo: modo, desde: Entrada.origen(entrada, opts)}

    Telemetria.span(:parsear, metadata, fn ->
      {resultado, lineas} =
        case Entrada.leer(entrada, opts) do
          {:ok, contenido} ->
            contenido
            |> Parser.numerar(Keyword.get(opts, :traza, false))
            |> Parser.seleccionar(opts)
            |> then(&recorrer(multi, &1, modo))

          {:error, diagnosticos} ->
            {{:error, diagnosticos}, 0}
        end

      {medidas, extra} = Telemetria.medir_parseo(resultado, lineas)
      {resultado, medidas, Map.merge(extra, metadata_de(multi))}
    end)
  end

  # Cada tipo tiene su layout: no hay un encoding ni una unidad que declarar
  # por el archivo entero, y un handler que lea las claves documentadas de
  # `[:ancho_fijo, :parsear, :stop]` recibe `nil`, no un KeyError.
  defp metadata_de(%__MODULE__{nombre: nombre}), do: %{layout: nombre, encoding: nil, unidad: nil}

  # Las líneas llegan de a una y se cuentan al pasar, como en `Parser`:
  # devuelve el resultado y esa cuenta, que es lo que la telemetría mide. En
  # estricto, el primer error corta y la cuenta es la de las líneas leídas.
  defp recorrer(multi, lineas, :estricto) do
    resultado =
      Enum.reduce_while(lineas, {[], [], estado_inicial(multi), 0}, fn {linea, marca},
                                                                       {registros, advertencias,
                                                                        estado, leidas} ->
        case paso(multi, linea, marca, estado) do
          {:ok, registro, nuevas, estado} ->
            {:cont,
             {[registro | registros], Enum.reverse(nuevas, advertencias), estado, leidas + 1}}

          {:error, diagnosticos, _estado} ->
            {:halt, {:error, diagnosticos, leidas + 1}}
        end
      end)

    case resultado do
      {:error, diagnosticos, leidas} ->
        {{:error, diagnosticos}, leidas}

      {registros, advertencias, estado, leidas} ->
        case cierre(multi, estado) do
          [] -> {{:ok, Enum.reverse(registros), Enum.reverse(advertencias)}, leidas}
          diagnosticos -> {{:error, diagnosticos}, leidas}
        end
    end
  end

  defp recorrer(multi, lineas, :tolerante) do
    {registros, diagnosticos, estado, leidas} =
      Enum.reduce(lineas, {[], [], estado_inicial(multi), 0}, fn {linea, marca},
                                                                 {registros, diagnosticos, estado,
                                                                  leidas} ->
        case paso(multi, linea, marca, estado) do
          {:ok, registro, nuevos, estado} ->
            {[registro | registros], Enum.reverse(nuevos, diagnosticos), estado, leidas + 1}

          {:error, nuevos, estado} ->
            {registros, Enum.reverse(nuevos, diagnosticos), estado, leidas + 1}
        end
      end)

    {{:ok, Enum.reverse(registros), Enum.reverse(diagnosticos) ++ cierre(multi, estado)}, leidas}
  end

  @doc """
  Igual que `parsear/3`, pero devuelve solo los registros o levanta
  `AnchoFijo.Error`. Es el mismo contrato que `AnchoFijo.Parser.parsear!/3`:
  en modo `:tolerante` levanta con **todos** los errores del archivo, los de
  las líneas y los de estructura y control, y las advertencias no se
  devuelven.

      iex> multi = AnchoFijo.Multiregistro.nuevo!(discriminador: [largo: 1], registros: [
      ...>   h: [valor: "H", cantidad: :uno, layout: [campos: [[nombre: :t, largo: 1]]]],
      ...>   d: [valor: "D", cantidad: :varios, layout: [campos: [[nombre: :t, largo: 1]]]]
      ...> ])
      iex> AnchoFijo.Multiregistro.parsear!(multi, "H\\nD\\nD\\n")
      [h: %{t: "H"}, d: %{t: "D"}, d: %{t: "D"}]

      iex> multi = AnchoFijo.Multiregistro.nuevo!(discriminador: [largo: 1], registros: [
      ...>   h: [valor: "H", cantidad: :uno, layout: [campos: [[nombre: :t, largo: 1]]]],
      ...>   d: [valor: "D", cantidad: :varios, layout: [campos: [[nombre: :t, largo: 1]]]]
      ...> ])
      iex> AnchoFijo.Multiregistro.parsear!(multi, "D\\n")
      ** (AnchoFijo.Error) estructura: se esperaba un registro :h en el archivo, llegó el fin del archivo sin :h; el archivo está truncado o el emisor no cerró el lote
  """
  @spec parsear!(t(), term(), keyword()) :: [registro()]
  def parsear!(%__MODULE__{} = multi, entrada, opts \\ []) do
    case parsear(multi, entrada, opts) do
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
  Versión lazy. Emite `{:ok, {tipo, registro}, advertencias}` o
  `{:error, diagnosticos}` por línea, y al final un `{:error, diagnosticos}`
  más si los controles no cuadran o falta un registro obligatorio.
  """
  @spec stream(t(), term(), keyword()) :: Enumerable.t()
  def stream(%__MODULE__{} = multi, entrada, opts \\ []) do
    opts = Opciones.validar!(opts, Parser.opciones_de_stream(), "AnchoFijo.stream/3")
    metadata = Map.put(metadata_de(multi), :desde, Entrada.origen(entrada, opts))

    case Parser.fuente(entrada, opts) do
      {:ok, lineas} -> encadenar(multi, lineas, opts, metadata)
      {:error, diagnosticos} -> Telemetria.instrumentar_stream([{:error, diagnosticos}], metadata)
    end
  end

  # El acumulador lleva dos cosas: el estado de la estructura y las cuentas
  # de la telemetría. Van juntas y no en un `instrumentar_stream/2` por
  # fuera porque el elemento de cierre no es una línea: hay que contarlo
  # como errores sin sumarlo a `lineas`, y eso solo se sabe desde acá.
  defp encadenar(multi, lineas, opts, metadata) do
    numeradas =
      lineas
      |> Parser.numerar_stream(Keyword.get(opts, :traza, false))
      |> Stream.drop(Keyword.get(opts, :saltar, 0))
      |> Stream.map(fn {linea, marca} -> {sin_terminador(linea), marca} end)
      |> descartar_vacias(Keyword.get(opts, :omitir_vacias, true))

    Stream.transform(
      numeradas,
      fn -> {estado_inicial(multi), Telemetria.iniciar_cuentas(metadata)} end,
      fn {linea, marca}, {estado, cuentas} ->
        {resultado, estado} =
          case paso(multi, linea, marca, estado) do
            {:ok, registro, advertencias, estado} -> {{:ok, registro, advertencias}, estado}
            {:error, diagnosticos, estado} -> {{:error, diagnosticos}, estado}
          end

        {[resultado], {estado, Telemetria.contar(resultado, cuentas)}}
      end,
      fn {estado, cuentas} ->
        case cierre(multi, estado) do
          [] ->
            {[], {estado, cuentas}}

          diagnosticos ->
            {[{:error, diagnosticos}], {estado, Telemetria.contar_cierre(diagnosticos, cuentas)}}
        end
      end,
      fn {_estado, cuentas} -> Telemetria.cerrar_cuentas(cuentas, metadata) end
    )
  end

  defp marcar(registro, %Traza{} = traza), do: Map.put(registro, Traza.clave(), traza)
  defp marcar(registro, _numero), do: registro

  defp sin_terminador(linea) when is_binary(linea), do: Entrada.sin_terminador(linea)
  defp sin_terminador(otro), do: otro

  defp descartar_vacias(stream, true), do: Stream.reject(stream, fn {linea, _} -> linea == "" end)
  defp descartar_vacias(stream, _false), do: stream

  # ------------------------------------------------------------------ estado
  #
  # El estado que viaja: en qué tipo va el orden, cuántos de cada tipo se
  # leyeron, y los acumuladores de los controles (la cuenta por tipo y la
  # suma por {tipo, campo}), más los valores que el registro de control
  # declaró, para compararlos al final. Nunca los registros.

  defp estado_inicial(%__MODULE__{} = multi) do
    %{
      indice: 0,
      vistos: Map.new(multi.registros, fn {tipo, _} -> {tipo, 0} end),
      sumas:
        Map.new(multi.controles, fn
          %{suma: clave} -> {clave, nil}
          %{cuenta: tipo} -> {{:cuenta, tipo}, 0}
        end),
      declarados: []
    }
  end

  # `marca` es el número de línea, o la traza entera cuando se pidió; en el
  # segundo caso el mapa sale con la clave reservada, como en `Parser`.
  defp paso(%__MODULE__{} = multi, linea, marca, estado) when is_binary(linea) do
    numero = Parser.numero_de(marca)

    with {:ok, tipo, definicion} <- discriminar(multi, linea, numero),
         {:ok, estado} <- avanzar(multi, tipo, definicion, numero, estado),
         {:ok, registro, advertencias} <- Parser.parsear_linea(definicion.layout, linea, numero) do
      registro = marcar(registro, marca)
      {:ok, {tipo, registro}, advertencias, acumular(multi, tipo, registro, numero, estado)}
    else
      {:error, diagnosticos} -> {:error, diagnosticos, estado}
      {:error, diagnosticos, estado} -> {:error, diagnosticos, estado}
    end
  end

  defp paso(_multi, otro, marca, estado) do
    {:error,
     [
       Diagnostico.nuevo(
         tipo: :entrada,
         linea: Parser.numero_de(marca),
         esperado: "un binario por elemento del enumerable",
         recibido: inspect(otro),
         causa_probable: "el enumerable de entrada no entrega líneas como binarios"
       )
     ], estado}
  end

  # Público sin doc: `AnchoFijo.Identidad` lo usa para saber de qué tipo es
  # el primer registro antes de leerlo con un layout.
  @doc false
  @spec discriminar(t(), binary(), pos_integer()) ::
          {:ok, tipo(), definicion()} | {:error, [Diagnostico.t()]}
  def discriminar(
        %__MODULE__{discriminador: %{posicion: posicion, largo: largo}} = multi,
        linea,
        numero
      ) do
    desde = posicion - 1

    if byte_size(linea) >= desde + largo do
      buscar_tipo(multi, binary_part(linea, desde, largo), numero)
    else
      {:error, [linea_corta(posicion, desde + largo, byte_size(linea), numero)]}
    end
  end

  defp buscar_tipo(%__MODULE__{} = multi, valor, numero) do
    case Enum.find(multi.registros, fn {_tipo, d} -> valor in d.valores end) do
      {tipo, definicion} -> {:ok, tipo, definicion}
      nil -> {:error, [desconocido(multi, valor, numero)]}
    end
  end

  defp linea_corta(posicion, hasta, medida, numero) do
    Diagnostico.nuevo(
      tipo: :estructura,
      linea: numero,
      esperado:
        "al menos #{hasta} bytes para leer el discriminador (posiciones #{posicion}-#{hasta})",
      recibido: "#{medida}",
      causa_probable: "la línea es demasiado corta para saber de qué tipo es"
    )
  end

  defp desconocido(%__MODULE__{} = multi, valor, numero) do
    valores =
      Enum.map_join(multi.registros, ", ", fn {tipo, d} ->
        "#{Enum.map_join(d.valores, "/", &inspect/1)} (#{inspect(tipo)})"
      end)

    Diagnostico.nuevo(
      tipo: :estructura,
      linea: numero,
      esperado: "un discriminador en #{valores}",
      recibido: inspect(valor),
      causa_probable:
        "la línea no corresponde a ningún tipo de registro declarado; puede ser un tipo que el formato " <>
          "agregó, o una línea corrida"
    )
  end

  # El orden es el de :registros. Un tipo puede ser el actual o uno
  # posterior; uno anterior está fuera de orden. Las cantidades :uno y
  # :opcional admiten una sola aparición.
  defp avanzar(%__MODULE__{} = multi, tipo, definicion, numero, estado) do
    indice = Enum.find_index(multi.registros, fn {t, _} -> t == tipo end)
    vistos = Map.fetch!(estado.vistos, tipo)

    cond do
      multi.orden == :estricto and indice < estado.indice ->
        {:error, [fuera_de_orden(multi, tipo, numero, estado)], estado}

      vistos >= 1 and definicion.cantidad in [:uno, :opcional] ->
        {:error, [repetido(tipo, numero, vistos)], estado}

      true ->
        {:ok, %{estado | indice: indice, vistos: Map.put(estado.vistos, tipo, vistos + 1)}}
    end
  end

  defp fuera_de_orden(%__MODULE__{} = multi, tipo, numero, estado) do
    {actual, _} = Enum.at(multi.registros, estado.indice)
    orden = Enum.map_join(multi.registros, ", ", fn {t, _} -> inspect(t) end)

    Diagnostico.nuevo(
      tipo: :estructura,
      linea: numero,
      esperado: "un registro #{inspect(actual)} o uno posterior en el orden #{orden}",
      recibido: inspect(tipo),
      causa_probable:
        "un #{inspect(tipo)} después de un #{inspect(actual)} rompe el orden del formato; " <>
          "suele ser un archivo pegado a otro o un lote sin cerrar"
    )
  end

  defp repetido(tipo, numero, vistos) do
    Diagnostico.nuevo(
      tipo: :estructura,
      linea: numero,
      esperado: "un solo registro #{inspect(tipo)}",
      recibido: "el número #{vistos + 1}",
      causa_probable:
        "el formato admite un #{inspect(tipo)} por archivo; puede haber dos lotes pegados"
    )
  end

  defp acumular(%__MODULE__{} = multi, tipo, registro, numero, estado) do
    sumas =
      Enum.reduce(multi.controles, estado.sumas, fn
        %{cuenta: ^tipo}, sumas ->
          Map.update!(sumas, {:cuenta, tipo}, &(&1 + 1))

        %{suma: {^tipo, campo} = clave}, sumas ->
          Map.update!(sumas, clave, &sumar(&1, Map.get(registro, campo)))

        _otro, sumas ->
          sumas
      end)

    declarados =
      multi.controles
      |> Enum.filter(&(&1.en == tipo))
      |> Enum.map(fn control -> {control, Map.get(registro, control.campo), numero} end)

    %{estado | sumas: sumas, declarados: estado.declarados ++ declarados}
  end

  # Sumas sobre enteros o sobre {unidades, precision}; con precisiones
  # distintas se lleva todo a la mayor. nil (un campo opcional vacío) no suma.
  defp sumar(acumulado, nil), do: acumulado
  defp sumar(nil, valor), do: valor
  defp sumar(a, b) when is_integer(a) and is_integer(b), do: a + b

  defp sumar({ua, pa}, {ub, pb}) do
    p = max(pa, pb)
    {escalar(ua, pa, p) + escalar(ub, pb, p), p}
  end

  defp sumar(a, b), do: {:incomparable, a, b}

  defp escalar(u, p, p), do: u
  defp escalar(u, p, objetivo), do: u * Integer.pow(10, objetivo - p)

  # Sin registros que sumar, el acumulador es nil y el trailer tiene que
  # declarar cero, en la forma que sea.
  defp iguales?(nil, declarado), do: declarado in [0, nil] or match?({0, _}, declarado)
  defp iguales?(a, b) when is_integer(a) and is_integer(b), do: a == b
  defp iguales?({ua, pa}, {ub, pb}), do: sumar({ua, pa}, {0, pb}) == sumar({ub, pb}, {0, pa})
  defp iguales?(_a, _b), do: false

  # Al terminar: los obligatorios que faltan y los controles que no cuadran.
  defp cierre(%__MODULE__{} = multi, estado) do
    faltantes =
      multi.registros
      |> Enum.filter(fn {tipo, d} ->
        d.cantidad in [:uno, :al_menos_uno] and Map.fetch!(estado.vistos, tipo) == 0
      end)
      |> Enum.map(fn {tipo, _} ->
        Diagnostico.nuevo(
          tipo: :estructura,
          esperado: "un registro #{inspect(tipo)} en el archivo",
          recibido: "el fin del archivo sin #{inspect(tipo)}",
          causa_probable: "el archivo está truncado o el emisor no cerró el lote"
        )
      end)

    controles =
      Enum.flat_map(estado.declarados, fn {control, declarado, numero} ->
        calculado = calcular(control, estado.sumas)

        if iguales?(calculado, declarado),
          do: [],
          else: [no_cuadra(control, declarado, calculado, numero)]
      end)

    faltantes ++ controles
  end

  defp calcular(%{cuenta: tipo}, sumas), do: Map.fetch!(sumas, {:cuenta, tipo})
  defp calcular(%{suma: clave}, sumas), do: Map.fetch!(sumas, clave)

  defp no_cuadra(%{cuenta: tipo} = control, declarado, calculado, numero) do
    Diagnostico.nuevo(
      tipo: :control,
      linea: numero,
      campo: control.campo,
      esperado:
        "#{calculado} en #{inspect(control.campo)}, que es la cantidad de registros #{inspect(tipo)}",
      recibido: inspect(declarado),
      causa_probable:
        "el #{inspect(control.en)} no cuadra con los #{inspect(tipo)}: faltan registros o sobran; " <>
          "si hubo líneas ilegibles, la cuenta las excluye"
    )
  end

  defp no_cuadra(%{suma: {tipo, campo}} = control, declarado, calculado, numero) do
    Diagnostico.nuevo(
      tipo: :control,
      linea: numero,
      campo: control.campo,
      esperado:
        "#{inspect(calculado || 0)} en #{inspect(control.campo)}, la suma de #{inspect(campo)} de los #{inspect(tipo)}",
      recibido: inspect(declarado),
      causa_probable:
        "el total del #{inspect(control.en)} no cuadra con los #{inspect(tipo)}; si hubo líneas " <>
          "ilegibles, la suma las excluye"
    )
  end

  # ----------------------------------------------------------------- agrupar

  @doc """
  Agrupa los registros por tipo: los de cantidad `:uno` u `:opcional` como
  el mapa (o `nil`), los demás como lista en el orden del archivo.

      iex> multi = AnchoFijo.Multiregistro.nuevo!(discriminador: [largo: 1], registros: [
      ...>   h: [valor: "H", cantidad: :uno, layout: [campos: [[nombre: :t, largo: 1]]]],
      ...>   d: [valor: "D", cantidad: :varios, layout: [campos: [[nombre: :t, largo: 1]]]]
      ...> ])
      iex> AnchoFijo.Multiregistro.agrupar(multi, [h: %{t: "H"}, d: %{t: "D"}, d: %{t: "D"}])
      %{h: %{t: "H"}, d: [%{t: "D"}, %{t: "D"}]}
  """
  @spec agrupar(t(), [registro()]) :: %{tipo() => Parser.registro() | nil | [Parser.registro()]}
  def agrupar(%__MODULE__{} = multi, registros) do
    por_tipo = Enum.group_by(registros, fn {tipo, _} -> tipo end, fn {_, registro} -> registro end)

    Map.new(multi.registros, fn {tipo, definicion} ->
      lista = Map.get(por_tipo, tipo, [])

      if definicion.cantidad in [:uno, :opcional],
        do: {tipo, List.first(lista)},
        else: {tipo, lista}
    end)
  end
end
