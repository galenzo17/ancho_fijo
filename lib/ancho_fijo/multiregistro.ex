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
    * `:discriminador` — cómo se sabe de qué tipo es cada línea:
        * `[posicion: 1, largo: 2]`: por un código en esas posiciones, en
          bytes de la línea cruda, comparado con el `:valor` de cada tipo.
        * `[campo: :tipo]`: lo mismo, con la posición, el largo y los
          valores tomados del campo `:constante` que cada layout declara
          con ese nombre (en la misma posición y con el mismo largo en
          todos); así el literal de cada tipo se escribe una sola vez.
        * `[por: :largo]`: por el largo de la línea, que tiene que ser el
          `largo` del layout de exactamente un tipo. Dos tipos que miden
          lo mismo son una definición inválida: no se pueden distinguir.
        * `[por: :posicion_en_archivo]`: por dónde está la línea; cada
          tipo declara `ubicacion: :primera`, `:ultima` o `:resto` (a lo
          más uno de cada). Es para los formatos cuyo header y trailer no
          traen código ni miden distinto. En un stream, la última línea
          se reconoce con una línea de anticipación, así que la memoria
          sigue siendo constante.
        * `[por: fun]`: una función `(linea, numero) -> tipo | nil` para lo
          que no cabe en lo anterior. `nil` es "ningún tipo" y produce un
          diagnóstico `:estructura`. Una función no se puede serializar ni
          contrastar desde `AnchoFijo.detectar/2`, que solo cuenta lo que
          devuelve: úsela cuando ninguna de las otras formas alcance.
    * `:registros` — una keyword list de tipo a definición, en el orden
      esperado en el archivo. Cada definición tiene `:layout` (un
      `AnchoFijo.Layout` o su definición), `:cantidad`: `:uno` (exactamente
      uno), `:opcional` (cero o uno), `:varios` (cero o más) o
      `:al_menos_uno`, y `:valor`: lo que trae el discriminador, o una lista
      de valores si el tipo admite varios. `:valor` se puede omitir cuando
      el layout tiene un campo `:constante` justo en las posiciones del
      discriminador: el literal es el valor.
    * `:orden` — `:estricto` (default): los tipos aparecen en el orden de
      `:registros`. `:libre`: cualquier orden; solo se verifican las
      cantidades. Es para los formatos con lotes que se repiten (NACHA), donde
      la estructura anidada se valida aparte.
    * `:controles` — lista de `[en: tipo, campo: nombre, cuenta: tipo]` o
      `[en: tipo, campo: nombre, suma: {tipo, campo}]`. El campo del registro
      `en:` tiene que valer la cantidad de registros de ese tipo, o la suma
      de ese campo en ellos. Las sumas son sobre enteros, sobre
      `{unidades, precision}` (con precisiones distintas se comparan a la
      mayor), sobre `AnchoFijo.Monto` de la misma moneda o sobre `Decimal`;
      nunca floats. Con `agrupar_por: campo`, el control vale por grupo: un
      trailer por moneda, con `[en: :trailer, campo: :total, suma:
      {:detalle, :importe}, agrupar_por: :moneda]`, se compara con la suma
      de los detalles que tienen la misma `:moneda` que ese trailer. El
      campo de agrupación tiene que existir en los dos layouts.

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

  ## Escribir

  `escribir/3` es el inverso: recibe los `{tipo, mapa}` en el orden del
  archivo y genera el contenido con el layout de cada tipo, verificando la
  estructura (orden, cantidades, lo obligatorio que falta) y **calculando
  los controles**: el campo de `cuenta:` sale con la cantidad de registros
  del tipo contado y el de `suma:` con la suma, sin que el mapa del trailer
  los traiga. Si los trae, tienen que coincidir; otro valor es un
  diagnóstico `:control`, no se sobreescribe en silencio. Todo o nada, como
  `AnchoFijo.escribir/3`. No hay versión lazy: el trailer necesita los
  totales, y los totales necesitan todos los detalles.

  ## En un stream

  `stream/3` emite `{:ok, {tipo, registro}, advertencias}` o
  `{:error, diagnosticos}` por línea, con la estructura verificada al pasar.
  Los controles necesitan todos los detalles, así que salen **al final del
  stream**, como un último elemento `{:error, diagnosticos}` si algo no
  cuadra o si falta un registro obligatorio, y nada si todo cuadra. El
  estado que viaja en el acumulador son las cuentas y las sumas, no los
  registros: la memoria sigue siendo constante.
  """

  alias AnchoFijo.Campo
  alias AnchoFijo.Diagnostico
  alias AnchoFijo.Entrada
  alias AnchoFijo.Escritor
  alias AnchoFijo.Layout
  alias AnchoFijo.Monto
  alias AnchoFijo.Opciones
  alias AnchoFijo.Parser
  alias AnchoFijo.Telemetria
  alias AnchoFijo.Tipo
  alias AnchoFijo.Traza

  @compile {:no_warn_undefined, Decimal}

  @cantidades [:uno, :opcional, :varios, :al_menos_uno]
  @claves [:nombre, :discriminador, :registros, :controles, :orden]

  @type cantidad :: :uno | :opcional | :varios | :al_menos_uno
  @type tipo :: atom()
  @type registro :: {tipo(), Parser.registro()}

  @type definicion :: %{
          valores: [binary()],
          layout: Layout.t(),
          cantidad: cantidad(),
          ubicacion: ubicacion() | nil
        }

  @type control ::
          %{optional(:agrupar_por) => atom(), en: tipo(), campo: atom(), cuenta: tipo()}
          | %{optional(:agrupar_por) => atom(), en: tipo(), campo: atom(), suma: {tipo(), atom()}}

  @type discriminador ::
          %{optional(:campo) => atom(), posicion: pos_integer(), largo: pos_integer()}
          | %{por: :largo | :posicion_en_archivo}
          | %{por: :funcion, funcion: (binary(), pos_integer() -> tipo() | nil)}

  @type ubicacion :: :primera | :resto | :ultima

  @type t :: %__MODULE__{
          nombre: String.t() | nil,
          discriminador: discriminador(),
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
    with {:ok, definicion} <- definicion_a_mapa(definicion),
         :ok <- sin_claves_desconocidas(definicion),
         {:ok, nombre} <- validar_nombre(Map.get(definicion, :nombre)),
         {:ok, discriminador} <- validar_discriminador(Map.get(definicion, :discriminador)),
         {:ok, registros} <- validar_registros(Map.get(definicion, :registros, [])),
         {:ok, discriminador, registros} <- resolver_discriminador(discriminador, registros),
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

  defp definicion_a_mapa(definicion) do
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
             clave,
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

  @formas "un :discriminador con :posicion y :largo, con :campo, o con :por " <>
            "(:largo, :posicion_en_archivo o una función de dos argumentos)"

  defp validar_discriminador(nil), do: {:error, [falla(@formas, nil, nil)]}

  defp validar_discriminador(discriminador) do
    case {get(discriminador, :por), solo_por?(discriminador)} do
      {nil, _} -> validar_por_valor(discriminador)
      {por, true} -> validar_por(por, discriminador)
      {_por, false} -> {:error, [falla(@formas, inspect(discriminador), nil)]}
    end
  end

  defp validar_por(:largo, _discriminador), do: {:ok, %{por: :largo}}
  defp validar_por(:posicion_en_archivo, _discriminador), do: {:ok, %{por: :posicion_en_archivo}}

  defp validar_por(fun, _discriminador) when is_function(fun, 2),
    do: {:ok, %{por: :funcion, funcion: fun}}

  defp validar_por(_otro, discriminador),
    do: {:error, [falla(@formas, inspect(discriminador), nil)]}

  defp validar_por_valor(discriminador) do
    campo = get(discriminador, :campo)
    posicion = get(discriminador, :posicion, 1)
    largo = get(discriminador, :largo)

    cond do
      por_campo?(campo, largo) -> {:ok, %{campo: campo}}
      por_posicion?(campo, posicion, largo) -> {:ok, %{posicion: posicion, largo: largo}}
      true -> {:error, [falla(@formas, inspect(discriminador), nil)]}
    end
  end

  defp solo_por?(discriminador) do
    is_nil(get(discriminador, :campo)) and is_nil(get(discriminador, :largo)) and
      is_nil(get(discriminador, :posicion))
  end

  defp por_campo?(campo, largo), do: is_atom(campo) and not is_nil(campo) and is_nil(largo)

  defp por_posicion?(campo, posicion, largo) do
    is_nil(campo) and is_integer(posicion) and posicion > 0 and is_integer(largo) and largo > 0
  end

  defp validar_registros([]) do
    {:error, [falla("al menos un tipo de registro en :registros", "una lista vacía", nil)]}
  end

  defp validar_registros(registros) when is_list(registros) do
    {definiciones, diagnosticos} =
      Enum.reduce(registros, {[], []}, fn
        {tipo, definicion}, {definiciones, diagnosticos} when is_atom(tipo) ->
          case validar_registro(tipo, definicion) do
            {:ok, definicion} -> {[{tipo, definicion} | definiciones], diagnosticos}
            {:error, nuevos} -> {definiciones, diagnosticos ++ nuevos}
          end

        otro, {definiciones, diagnosticos} ->
          {definiciones,
           diagnosticos ++ [falla("pares tipo: definición en :registros", inspect(otro), nil)]}
      end)

    case diagnosticos do
      [] -> {:ok, Enum.reverse(definiciones)}
      diagnosticos -> {:error, diagnosticos}
    end
  end

  defp validar_registros(otro) do
    {:error, [falla("una keyword list en :registros", inspect(otro), nil)]}
  end

  # El layout y la cantidad se validan acá; los valores del discriminador,
  # en `resolver_discriminador/2`, porque con `[campo: :tipo]` el largo sale
  # de los layouts y hay que tenerlos construidos primero.
  defp validar_registro(tipo, definicion) do
    cantidad = get(definicion, :cantidad, :varios)

    problemas =
      if cantidad in @cantidades,
        do: [],
        else: [
          falla(
            ":cantidad en #{inspect(@cantidades)} para #{inspect(tipo)}",
            inspect(cantidad),
            nil
          )
        ]

    case {problemas, Layout.coercer(get(definicion, :layout))} do
      {[], {:ok, layout}} ->
        {:ok,
         %{
           valores: get(definicion, :valor),
           layout: layout,
           cantidad: cantidad,
           ubicacion: get(definicion, :ubicacion)
         }}

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

  # Con `[campo: nombre]`, la posición y el largo son los del campo
  # :constante con ese nombre, que tiene que estar igual en todos los
  # layouts. Con posición y largo explícitos, cada tipo declara su :valor, o
  # lo toma del campo :constante que ocupa exactamente esas posiciones.
  defp resolver_discriminador(%{campo: nombre} = discriminador, registros)
       when not is_map_key(discriminador, :largo) do
    {ubicaciones, diagnosticos} =
      Enum.reduce(registros, {[], []}, fn {tipo, d}, {ubicaciones, diagnosticos} ->
        case ubicacion_de(tipo, d.layout, nombre) do
          {:ok, ubicacion} -> {[ubicacion | ubicaciones], diagnosticos}
          {:error, diagnostico} -> {ubicaciones, diagnosticos ++ [diagnostico]}
        end
      end)

    ubicaciones = Enum.reverse(ubicaciones)

    with [] <- diagnosticos,
         [{_tipo, posicion, largo}] <- Enum.uniq_by(ubicaciones, fn {_, p, l} -> {p, l} end) do
      resolver_discriminador(%{posicion: posicion, largo: largo, campo: nombre}, registros)
    else
      [%Diagnostico{} | _] = diagnosticos ->
        {:error, diagnosticos}

      distintas ->
        {:error,
         [
           falla(
             "el campo #{inspect(nombre)} en la misma posición y con el mismo largo en todos los layouts",
             Enum.map_join(distintas, ", ", fn {tipo, p, l} ->
               "#{inspect(tipo)} en #{p} con largo #{l}"
             end),
             "el discriminador tiene que leerse igual en todas las líneas para saber de qué tipo son"
           )
         ]}
    end
  end

  # Por largo: cada tipo mide lo que su layout; dos iguales no se distinguen.
  defp resolver_discriminador(%{por: :largo} = discriminador, registros) do
    repetidos =
      registros
      |> Enum.group_by(fn {_tipo, d} -> d.layout.largo end, fn {tipo, _d} -> tipo end)
      |> Enum.filter(fn {_largo, tipos} -> length(tipos) > 1 end)

    case repetidos do
      [] ->
        {:ok, discriminador, sin_valores(registros)}

      [{largo, tipos} | _] ->
        {:error,
         [
           falla(
             "un largo de línea distinto por tipo de registro",
             "#{Enum.map_join(tipos, " y ", &inspect/1)} miden #{largo}",
             "dos tipos que miden lo mismo no se pueden distinguir por largo; " <>
               "use un código de tipo, :posicion_en_archivo o una función"
           )
         ]}
    end
  end

  # Por posición en el archivo: cada tipo dice dónde va, y a lo más uno por lugar.
  defp resolver_discriminador(%{por: :posicion_en_archivo} = discriminador, registros) do
    ubicaciones = Enum.map(registros, fn {tipo, d} -> {tipo, d.ubicacion} end)

    invalidas =
      for {tipo, ubicacion} <- ubicaciones, ubicacion not in [:primera, :resto, :ultima] do
        falla(
          "ubicacion: :primera, :resto o :ultima para #{inspect(tipo)}",
          inspect(ubicacion),
          "con :posicion_en_archivo cada tipo declara dónde va en el archivo"
        )
      end

    repetidas =
      ubicaciones
      |> Enum.group_by(fn {_tipo, u} -> u end, fn {tipo, _u} -> tipo end)
      |> Enum.filter(fn {u, tipos} -> u in [:primera, :resto, :ultima] and length(tipos) > 1 end)
      |> Enum.map(fn {u, tipos} ->
        falla(
          "un solo tipo con ubicacion: #{inspect(u)}",
          Enum.map_join(tipos, " y ", &inspect/1),
          "dos tipos en el mismo lugar del archivo no se pueden distinguir"
        )
      end)

    case invalidas ++ repetidas do
      [] -> {:ok, discriminador, sin_valores(registros)}
      diagnosticos -> {:error, diagnosticos}
    end
  end

  defp resolver_discriminador(%{por: :funcion} = discriminador, registros),
    do: {:ok, discriminador, sin_valores(registros)}

  defp resolver_discriminador(%{largo: largo} = discriminador, registros) do
    {definiciones, diagnosticos} =
      Enum.reduce(registros, {[], []}, fn {tipo, d}, {definiciones, diagnosticos} ->
        case valores_de(tipo, d, discriminador) do
          {:ok, valores} -> {[{tipo, %{d | valores: valores}} | definiciones], diagnosticos}
          {:error, diagnostico} -> {definiciones, diagnosticos ++ [diagnostico]}
        end
      end)

    definiciones = Enum.reverse(definiciones)

    case diagnosticos ++ valores_repetidos(definiciones) do
      [] -> {:ok, Map.put(discriminador, :largo, largo), definiciones}
      diagnosticos -> {:error, diagnosticos}
    end
  end

  defp sin_valores(registros),
    do: Enum.map(registros, fn {tipo, d} -> {tipo, %{d | valores: []}} end)

  defp valores_de(tipo, %{valores: nil, layout: layout}, discriminador) do
    constante =
      Enum.find(layout.campos, fn campo ->
        Campo.constante?(campo) and campo.posicion == discriminador.posicion and
          campo.largo == discriminador.largo
      end)

    case constante do
      %Campo{} = campo ->
        {:ok, [Tipo.Constante.esperado(campo)]}

      nil ->
        {:error,
         falla(
           "un :valor para #{inspect(tipo)}, o un campo :constante en las posiciones " <>
             "#{discriminador.posicion}-#{discriminador.posicion + discriminador.largo - 1} de su layout",
           "ninguno de los dos",
           "sin valor no hay forma de saber qué líneas son #{inspect(tipo)}"
         )}
    end
  end

  defp valores_de(tipo, %{valores: declarados}, discriminador) do
    valores = List.wrap(declarados)

    if valores != [] and
         Enum.all?(valores, &(is_binary(&1) and byte_size(&1) == discriminador.largo)) do
      {:ok, valores}
    else
      {:error,
       falla(
         "un :valor binario (o una lista de ellos) de #{discriminador.largo} bytes para " <>
           "#{inspect(tipo)}, el largo del discriminador",
         inspect(declarados),
         nil
       )}
    end
  end

  defp ubicacion_de(tipo, layout, nombre) do
    case Layout.campo(layout, nombre) do
      %Campo{} = campo ->
        if Campo.constante?(campo),
          do: {:ok, {tipo, campo.posicion, campo.largo}},
          else: {:error, no_es_constante(tipo, nombre, campo)}

      nil ->
        {:error, sin_campo(tipo, nombre)}
    end
  end

  defp sin_campo(tipo, nombre) do
    falla(
      "un campo #{inspect(nombre)} en el layout de #{inspect(tipo)}",
      "un layout sin ese campo",
      "el discriminador por :campo exige que cada tipo tenga ese campo :constante"
    )
  end

  defp no_es_constante(tipo, nombre, %Campo{tipo: otro}) do
    falla(
      "un campo #{inspect(nombre)} de tipo :constante en el layout de #{inspect(tipo)}",
      "un campo #{inspect(otro)}",
      "el literal del discriminador se declara con tipo: :constante, valor: \"...\""
    )
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

    with :ok <- validar_en(control, registros, en, campo),
         {:ok, validado} <- validar_cuenta_o_suma(control, registros, en, campo) do
      validar_agrupar_por(control, registros, validado)
    end
  end

  defp validar_en(control, registros, en, campo) do
    if tiene_campo?(registros, en, campo) do
      :ok
    else
      {:error,
       falla(
         "un control con :en y :campo que existan en el layout de ese tipo",
         inspect(control),
         "el tipo #{inspect(en)} no está en :registros o su layout no tiene el campo #{inspect(campo)}"
       )}
    end
  end

  defp validar_cuenta_o_suma(control, registros, en, campo) do
    cond do
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

  # El campo de agrupación tiene que estar en el layout del registro de
  # control y en el del tipo contado o sumado: se compara el valor de uno
  # con el de los otros.
  defp validar_agrupar_por(control, registros, validado) do
    case get(control, :agrupar_por) do
      nil ->
        {:ok, validado}

      grupo when is_atom(grupo) ->
        contado = tipo_contado(validado)

        if tiene_campo?(registros, validado.en, grupo) and tiene_campo?(registros, contado, grupo),
          do: {:ok, Map.put(validado, :agrupar_por, grupo)},
          else:
            {:error,
             falla(
               "un :agrupar_por que exista en el layout de #{inspect(validado.en)} y en el de " <>
                 "#{inspect(contado)}",
               inspect(grupo),
               "el valor de ese campo en el registro de control se compara con el de los registros " <>
                 "que cuenta o suma"
             )}

      otro ->
        {:error, falla("un :agrupar_por que sea el nombre de un campo", inspect(otro), nil)}
    end
  end

  defp tipo_contado(%{cuenta: tipo}), do: tipo
  defp tipo_contado(%{suma: {tipo, _campo}}), do: tipo

  defp tiene_campo?(registros, tipo, campo) when is_atom(tipo) do
    case Keyword.fetch(registros, tipo) do
      {:ok, %{layout: layout}} -> is_atom(campo) and Enum.any?(layout.campos, &(&1.nombre == campo))
      :error -> false
    end
  end

  defp tiene_campo?(_registros, _tipo, _campo), do: false

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
            |> con_ubicacion(multi)
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
  # Una regla que no se cumple es un error que viene con el registro leído:
  # en estricto rechaza la línea, como cualquier otro error.
  defp sin_errores({:ok, registro, diagnosticos, estado}) do
    case Enum.filter(diagnosticos, &(&1.gravedad == :error)) do
      [] -> {:ok, registro, diagnosticos, estado}
      errores -> {:error, errores, estado}
    end
  end

  defp sin_errores(otro), do: otro

  defp recorrer(multi, lineas, :estricto) do
    resultado =
      Enum.reduce_while(lineas, {[], [], estado_inicial(multi), 0}, fn {linea, marca, pista},
                                                                       {registros, advertencias,
                                                                        estado, leidas} ->
        case paso(multi, linea, marca, pista, estado) |> sin_errores() do
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
      Enum.reduce(lineas, {[], [], estado_inicial(multi), 0}, fn {linea, marca, pista},
                                                                 {registros, diagnosticos, estado,
                                                                  leidas} ->
        case paso(multi, linea, marca, pista, estado) do
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
      |> con_ubicacion(multi)

    Stream.transform(
      numeradas,
      fn -> {estado_inicial(multi), Telemetria.iniciar_cuentas(metadata)} end,
      fn {linea, marca, pista}, {estado, cuentas} ->
        {resultado, estado} =
          case paso(multi, linea, marca, pista, estado) do
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

  # Cada línea viaja con una pista para el discriminador: con
  # :posicion_en_archivo, si es la primera, la última o una del medio; con
  # los demás, nada. La última se reconoce con una línea de anticipación:
  # se retiene una y se emite recién cuando llega la siguiente, o al final.
  defp con_ubicacion(lineas, %__MODULE__{discriminador: %{por: :posicion_en_archivo}} = multi) do
    tiene? = fn ubicacion ->
      Enum.any?(multi.registros, fn {_, d} -> d.ubicacion == ubicacion end)
    end

    Stream.transform(
      lineas,
      fn -> {nil, 0} end,
      fn {linea, marca}, {pendiente, indice} ->
        case pendiente do
          nil -> {[], {{linea, marca}, indice + 1}}
          {l, m} -> {[{l, m, no_ultima(indice, tiene?)}], {{linea, marca}, indice + 1}}
        end
      end,
      fn
        {nil, _indice} = acumulado -> {[], acumulado}
        {{l, m}, indice} = acumulado -> {[{l, m, ultima(indice, tiene?)}], acumulado}
      end,
      fn _acumulado -> :ok end
    )
  end

  defp con_ubicacion(lineas, _multi),
    do: Stream.map(lineas, fn {linea, marca} -> {linea, marca, nil} end)

  defp no_ultima(1, tiene?), do: if(tiene?.(:primera), do: :primera, else: :resto)
  defp no_ultima(_indice, _tiene?), do: :resto

  defp ultima(1, tiene?) do
    cond do
      tiene?.(:primera) -> :primera
      tiene?.(:ultima) -> :ultima
      true -> :resto
    end
  end

  defp ultima(_indice, tiene?), do: if(tiene?.(:ultima), do: :ultima, else: :resto)

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

  # Las sumas van por clave del control y por grupo (`nil` sin
  # `agrupar_por`), y se crean al aparecer el primer registro: con grupos no
  # se sabe de antemano cuáles hay.
  defp estado_inicial(%__MODULE__{} = multi) do
    %{
      indice: 0,
      vistos: Map.new(multi.registros, fn {tipo, _} -> {tipo, 0} end),
      sumas: %{},
      declarados: []
    }
  end

  # `marca` es el número de línea, o la traza entera cuando se pidió; en el
  # segundo caso el mapa sale con la clave reservada, como en `Parser`.
  defp paso(%__MODULE__{} = multi, linea, marca, pista, estado) when is_binary(linea) do
    numero = Parser.numero_de(marca)

    with {:ok, tipo, definicion} <- discriminar(multi, linea, numero, pista),
         {:ok, estado} <- avanzar(multi, tipo, definicion, numero, estado),
         {:ok, registro, advertencias} <- Parser.parsear_linea(definicion.layout, linea, numero) do
      registro = marcar(registro, marca)
      {:ok, {tipo, registro}, advertencias, acumular(multi, tipo, registro, numero, estado)}
    else
      {:error, diagnosticos} -> {:error, diagnosticos, estado}
      {:error, diagnosticos, estado} -> {:error, diagnosticos, estado}
    end
  end

  defp paso(_multi, otro, marca, _pista, estado) do
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
  # el primer registro antes de leerlo con un layout, y `AnchoFijo.Detector`
  # para contar las líneas de cada tipo. La pista es la ubicación de la línea
  # en el archivo (`:primera`, `:resto`, `:ultima`), que solo el
  # discriminador por posición en el archivo mira.
  @doc false
  @spec discriminar(t(), binary(), pos_integer(), ubicacion() | nil) ::
          {:ok, tipo(), definicion()} | {:error, [Diagnostico.t()]}
  def discriminar(multi, linea, numero, pista \\ nil)

  def discriminar(
        %__MODULE__{discriminador: %{posicion: posicion, largo: largo}} = multi,
        linea,
        numero,
        _pista
      ) do
    desde = posicion - 1

    if byte_size(linea) >= desde + largo do
      buscar_tipo(multi, binary_part(linea, desde, largo), numero)
    else
      {:error, [linea_corta(posicion, desde + largo, byte_size(linea), numero)]}
    end
  end

  def discriminar(%__MODULE__{discriminador: %{por: :largo}} = multi, linea, numero, _pista) do
    case Enum.find(multi.registros, fn {_tipo, d} -> largo_de(linea, d.layout) == d.layout.largo end) do
      {tipo, definicion} ->
        {:ok, tipo, definicion}

      nil ->
        largos =
          Enum.map_join(multi.registros, ", ", fn {tipo, d} ->
            "#{d.layout.largo} (#{inspect(tipo)})"
          end)

        {:error,
         [
           Diagnostico.nuevo(
             tipo: :estructura,
             linea: numero,
             esperado: "una línea que mida lo que algún tipo declara: #{largos}",
             recibido: "#{byte_size(linea)} bytes",
             causa_probable:
               "ningún tipo de registro mide eso; la línea está corrida, trae relleno de más " <>
                 "o es de un tipo que el formato agregó"
           )
         ]}
    end
  end

  def discriminar(
        %__MODULE__{discriminador: %{por: :posicion_en_archivo}} = multi,
        _linea,
        numero,
        pista
      ) do
    case Enum.find(multi.registros, fn {_tipo, d} -> d.ubicacion == pista end) do
      {tipo, definicion} ->
        {:ok, tipo, definicion}

      nil ->
        {:error,
         [
           Diagnostico.nuevo(
             tipo: :estructura,
             linea: numero,
             esperado: "un tipo de registro con ubicacion: #{inspect(pista)}",
             recibido: "ninguno declarado",
             causa_probable:
               "el archivo tiene líneas en una posición que la definición no contempla"
           )
         ]}
    end
  end

  def discriminar(
        %__MODULE__{discriminador: %{por: :funcion, funcion: funcion}} = multi,
        linea,
        numero,
        _pista
      ) do
    case funcion.(linea, numero) do
      nil ->
        {:error,
         [
           Diagnostico.nuevo(
             tipo: :estructura,
             linea: numero,
             esperado: "un tipo de registro de #{inspect(Keyword.keys(multi.registros))}",
             recibido: "nil de la función de discriminación",
             causa_probable: "la función no reconoció la línea como ningún tipo"
           )
         ]}

      tipo ->
        case Keyword.fetch(multi.registros, tipo) do
          {:ok, definicion} ->
            {:ok, tipo, definicion}

          :error ->
            {:error,
             [
               Diagnostico.nuevo(
                 tipo: :estructura,
                 linea: numero,
                 esperado: "un tipo de registro de #{inspect(Keyword.keys(multi.registros))}",
                 recibido: inspect(tipo),
                 causa_probable:
                   "la función de discriminación devolvió un tipo que no está en :registros"
               )
             ]}
        end
    end
  end

  # El largo de la línea cruda en la unidad del layout del tipo: en bytes, o
  # en caracteres si el layout mide así y el encoding es multibyte. Público
  # sin doc para que `AnchoFijo.Detector` compare igual.
  @doc false
  @spec largo_de(binary(), Layout.t()) :: non_neg_integer()
  def largo_de(linea, %Layout{unidad: :caracteres, encoding: :utf8}), do: String.length(linea)
  def largo_de(linea, _layout), do: byte_size(linea)

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
        %{cuenta: ^tipo} = control, sumas ->
          clave = {{:cuenta, tipo}, grupo_de(control, registro)}
          Map.update(sumas, clave, 1, &(&1 + 1))

        %{suma: {^tipo, campo}} = control, sumas ->
          clave = {{tipo, campo}, grupo_de(control, registro)}
          valor = Map.get(registro, campo)
          Map.update(sumas, clave, sumar(nil, valor), &sumar(&1, valor))

        _otro, sumas ->
          sumas
      end)

    declarados =
      multi.controles
      |> Enum.filter(&(&1.en == tipo))
      |> Enum.map(fn control ->
        {control, Map.get(registro, control.campo), numero, grupo_de(control, registro)}
      end)

    %{estado | sumas: sumas, declarados: estado.declarados ++ declarados}
  end

  defp grupo_de(%{agrupar_por: campo}, registro), do: Map.get(registro, campo)
  defp grupo_de(_control, _registro), do: nil

  # Sumas sobre enteros, sobre {unidades, precision} (con precisiones
  # distintas se lleva todo a la mayor), sobre Monto de la misma moneda o
  # sobre Decimal. nil (un campo opcional vacío) no suma.
  defp sumar(acumulado, nil), do: acumulado
  defp sumar(nil, valor), do: valor
  defp sumar(a, b) when is_integer(a) and is_integer(b), do: a + b

  defp sumar({ua, pa}, {ub, pb}) when is_integer(ua) and is_integer(ub) do
    p = max(pa, pb)
    {escalar(ua, pa, p) + escalar(ub, pb, p), p}
  end

  defp sumar(%Monto{} = a, %Monto{} = b) do
    case Monto.sumar(a, b) do
      {:ok, suma} -> suma
      {:error, _diagnostico} -> {:incomparable, a, b}
    end
  end

  defp sumar(%{__struct__: Decimal} = a, %{__struct__: Decimal} = b), do: Decimal.add(a, b)
  defp sumar(a, b), do: {:incomparable, a, b}

  defp escalar(u, p, p), do: u
  defp escalar(u, p, objetivo), do: u * Integer.pow(10, objetivo - p)

  # Sin registros que sumar, el acumulador es nil y el trailer tiene que
  # declarar cero, en la forma que sea.
  defp iguales?(nil, declarado), do: cero?(declarado)
  defp iguales?(a, b) when is_integer(a) and is_integer(b), do: a == b

  defp iguales?({ua, pa}, {ub, pb}) when is_integer(ua) and is_integer(ub),
    do: sumar({ua, pa}, {0, pb}) == sumar({ub, pb}, {0, pa})

  defp iguales?(%Monto{moneda: m} = a, %Monto{moneda: m} = b),
    do: iguales?({a.unidades, a.precision}, {b.unidades, b.precision})

  defp iguales?(%{__struct__: Decimal} = a, %{__struct__: Decimal} = b), do: Decimal.equal?(a, b)
  defp iguales?(_a, _b), do: false

  defp cero?(nil), do: true
  defp cero?(0), do: true
  defp cero?({0, _precision}), do: true
  defp cero?(%Monto{unidades: 0}), do: true
  defp cero?(%{__struct__: Decimal} = d), do: Decimal.equal?(d, 0)
  defp cero?(_otro), do: false

  # Al terminar: los obligatorios que faltan y los controles que no cuadran.
  defp cierre(%__MODULE__{} = multi, estado) do
    faltantes(multi, estado) ++ controles_que_no_cuadran(estado)
  end

  defp faltantes(%__MODULE__{} = multi, estado) do
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
  end

  defp controles_que_no_cuadran(estado) do
    Enum.flat_map(estado.declarados, fn {control, declarado, numero, grupo} ->
      calculado = calcular(control, estado.sumas, grupo)

      if iguales?(calculado, declarado),
        do: [],
        else: [no_cuadra(control, declarado, calculado, numero)]
    end)
  end

  defp calcular(%{cuenta: tipo}, sumas, grupo), do: Map.get(sumas, {{:cuenta, tipo}, grupo}, 0)
  defp calcular(%{suma: clave}, sumas, grupo), do: Map.get(sumas, {clave, grupo}, nil)

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

  # ---------------------------------------------------------------- escribir

  @doc """
  Escribe un archivo multiregistro: los `{tipo, mapa}` en el orden del
  archivo, cada uno con el layout de su tipo, y los controles calculados.
  Mismas opciones que `AnchoFijo.escribir/3`.

      iex> multi = AnchoFijo.Multiregistro.nuevo!(
      ...>   discriminador: [posicion: 1, largo: 2],
      ...>   registros: [
      ...>     header: [valor: "01", cantidad: :uno, layout: [campos: [[nombre: :tipo, largo: 2, tipo: :constante, valor: "01"], [nombre: :fecha, largo: 8, tipo: :fecha, formato: :aaaammdd]]]],
      ...>     detalle: [valor: "02", cantidad: :varios, layout: [campos: [[nombre: :tipo, largo: 2, tipo: :constante, valor: "02"], [nombre: :monto, largo: 8, tipo: :entero]]]],
      ...>     trailer: [valor: "09", cantidad: :uno, layout: [campos: [[nombre: :tipo, largo: 2, tipo: :constante, valor: "09"], [nombre: :cantidad, largo: 3, tipo: :entero], [nombre: :total, largo: 8, tipo: :entero]]]]
      ...>   ],
      ...>   controles: [
      ...>     [en: :trailer, campo: :cantidad, cuenta: :detalle],
      ...>     [en: :trailer, campo: :total, suma: {:detalle, :monto}]
      ...>   ]
      ...> )
      iex> AnchoFijo.escribir(multi, [header: %{fecha: ~D[2024-01-31]}, detalle: %{monto: 1000}, detalle: %{monto: 250}, trailer: %{}])
      {:ok, "0120240131\\n0200001000\\n0200000250\\n0900200001250\\n", []}

  El trailer no trae `:cantidad` ni `:total`: salen de los detalles. Si los
  trae con otro valor, es un diagnóstico `:control` que dice el declarado y
  el calculado, y no se escribe nada.

  Cada registro es `{tipo, mapa}`. Con `discriminador: [campo: nombre]`
  también se acepta el mapa solo, con el literal del tipo en ese campo. Y
  si el código de tipo es un campo de texto del layout (no una constante),
  el mapa no necesita traerlo: sale el `:valor` del tipo; si lo trae, tiene
  que ser uno de los valores de ese tipo. Un
  tipo que no está en `:registros`, un registro fuera de orden o repetido,
  o un tipo obligatorio que falta, son diagnósticos `:estructura`, los
  mismos que al leer.
  """
  @spec escribir(t(), Enumerable.t(), keyword()) ::
          {:ok, binary(), [Diagnostico.t()]} | {:error, [Diagnostico.t()]}
  def escribir(%__MODULE__{} = multi, registros, opts \\ []) do
    opts = Opciones.validar!(opts, Escritor.opciones(), "AnchoFijo.escribir/3")

    metadata =
      Map.merge(metadata_de(multi), %{
        terminador: Keyword.get(opts, :terminador, :lf),
        truncar: Keyword.get(opts, :truncar, false)
      })

    Telemetria.span(:escribir, metadata, fn ->
      # Los totales del trailer necesitan todos los detalles: se materializa.
      registros = Enum.to_list(registros)
      resultado = escribir_todo(multi, registros, opts)
      {resultado, medir_escritura(resultado, length(registros)), %{resultado: elem(resultado, 0)}}
    end)
  end

  defp medir_escritura({:ok, _contenido, advertencias}, procesados),
    do: %{lineas: procesados, registros: procesados, errores: 0, advertencias: length(advertencias)}

  defp medir_escritura({:error, diagnosticos}, procesados),
    do: %{lineas: procesados, registros: 0, errores: length(diagnosticos), advertencias: 0}

  # Dos pasadas: la primera tipa cada registro, verifica la estructura y
  # acumula cuentas y sumas; la segunda escribe, con los controles puestos
  # (o verificados) en los registros que los declaran.
  defp escribir_todo(%__MODULE__{} = multi, registros, opts) do
    {tipados, estado, errores} =
      registros
      |> Enum.with_index(1)
      |> Enum.reduce({[], estado_inicial(multi), []}, fn {elemento, numero},
                                                         {tipados, estado, errores} ->
        with {:ok, tipo, mapa} <- tipar(multi, elemento, numero),
             {:ok, estado} <- avanzar(multi, tipo, definicion_de(multi, tipo), numero, estado) do
          {[{tipo, mapa, numero} | tipados], acumular(multi, tipo, mapa, numero, estado), errores}
        else
          {:error, diagnosticos} -> {tipados, estado, Enum.reverse(diagnosticos, errores)}
          {:error, diagnosticos, estado} -> {tipados, estado, Enum.reverse(diagnosticos, errores)}
        end
      end)

    case Enum.reverse(errores) ++ faltantes(multi, estado) do
      [] -> escribir_lineas(multi, Enum.reverse(tipados), estado, opts)
      diagnosticos -> {:error, diagnosticos}
    end
  end

  defp definicion_de(%__MODULE__{} = multi, tipo), do: Keyword.fetch!(multi.registros, tipo)

  defp escribir_lineas(%__MODULE__{} = multi, tipados, estado, opts) do
    terminador = Escritor.terminador(Keyword.get(opts, :terminador, :lf))
    truncar? = Keyword.get(opts, :truncar, false)

    {lineas, advertencias, errores} =
      Enum.reduce(tipados, {[], [], []}, fn {tipo, mapa, numero}, {lineas, advertencias, errores} ->
        with {:ok, mapa} <- con_discriminador(multi, tipo, mapa, numero),
             {:ok, mapa} <- con_controles(multi, tipo, mapa, numero, estado),
             {:ok, linea, nuevas} <-
               Escritor.escribir_linea(definicion_de(multi, tipo).layout, mapa, numero, truncar?) do
          {[linea <> terminador | lineas], Enum.reverse(nuevas, advertencias), errores}
        else
          {:error, diagnosticos} -> {lineas, advertencias, Enum.reverse(diagnosticos, errores)}
        end
      end)

    case errores do
      [] -> {:ok, lineas |> Enum.reverse() |> IO.iodata_to_binary(), Enum.reverse(advertencias)}
      errores -> {:error, Enum.reverse(errores)}
    end
  end

  # El código de tipo: si el layout lo declara como un campo de texto en las
  # posiciones del discriminador y el mapa no lo trae, sale el :valor del
  # tipo; si lo trae, tiene que ser uno de los valores del tipo. Con un
  # campo :constante no hay nada que poner: lo escribe el campo.
  defp con_discriminador(
         %__MODULE__{discriminador: %{posicion: posicion, largo: largo}} = multi,
         tipo,
         mapa,
         numero
       ) do
    %{layout: layout, valores: valores} = definicion_de(multi, tipo)

    campo =
      Enum.find(layout.campos, fn campo ->
        campo.posicion == posicion and campo.largo == largo and not Campo.constante?(campo)
      end)

    case {campo, campo && Map.get(mapa, campo.nombre)} do
      {nil, _} ->
        {:ok, mapa}

      {%Campo{nombre: nombre}, nil} ->
        {:ok, Map.put(mapa, nombre, hd(valores))}

      {%Campo{nombre: nombre}, dado} ->
        if is_binary(dado) and Enum.any?(valores, &Tipo.Constante.coincide?(&1, dado, " ")),
          do: {:ok, mapa},
          else:
            {:error,
             [
               Diagnostico.nuevo(
                 tipo: :estructura,
                 linea: numero,
                 campo: nombre,
                 esperado:
                   "el código de tipo de #{inspect(tipo)}: #{Enum.map_join(valores, " o ", &inspect/1)}",
                 recibido: inspect(dado),
                 causa_probable: "el registro dice ser #{inspect(tipo)} y trae otro código de tipo"
               )
             ]}
    end
  end

  defp con_discriminador(_multi, _tipo, mapa, _numero), do: {:ok, mapa}

  # Los controles que este tipo declara: si el mapa no los trae, se ponen
  # calculados; si los trae, tienen que cuadrar. Sin nada que sumar, cero.
  defp con_controles(%__MODULE__{} = multi, tipo, mapa, numero, estado) do
    multi.controles
    |> Enum.filter(&(&1.en == tipo))
    |> Enum.reduce({mapa, []}, fn control, {mapa, errores} ->
      case completar_control(control, mapa, numero, estado) do
        {:ok, mapa} -> {mapa, errores}
        {:error, diagnostico} -> {mapa, errores ++ [diagnostico]}
      end
    end)
    |> case do
      {mapa, []} -> {:ok, mapa}
      {_mapa, errores} -> {:error, errores}
    end
  end

  defp completar_control(control, mapa, numero, estado) do
    calculado = calcular(control, estado.sumas, grupo_de(control, mapa)) || 0

    case Map.get(mapa, control.campo) do
      nil ->
        {:ok, Map.put(mapa, control.campo, calculado)}

      declarado ->
        if iguales?(calculado, declarado),
          do: {:ok, mapa},
          else: {:error, no_cuadra_al_escribir(control, declarado, calculado, numero)}
    end
  end

  defp no_cuadra_al_escribir(control, declarado, calculado, numero) do
    de_que =
      case control do
        %{cuenta: tipo} -> "la cantidad de registros #{inspect(tipo)}"
        %{suma: {tipo, campo}} -> "la suma de #{inspect(campo)} de los #{inspect(tipo)}"
      end

    Diagnostico.nuevo(
      tipo: :control,
      linea: numero,
      campo: control.campo,
      esperado: "#{inspect(calculado)} en #{inspect(control.campo)}, #{de_que}, o el campo ausente",
      recibido: inspect(declarado),
      causa_probable:
        "el registro declara un valor distinto del calculado; no se sobreescribe en silencio: " <>
          "saque el campo del mapa para que salga calculado, o corrija los registros"
    )
  end

  # `{tipo, mapa}` siempre; el mapa solo cuando el discriminador apunta a un
  # campo :constante y el mapa trae su literal.
  defp tipar(%__MODULE__{} = multi, {tipo, mapa}, numero) when is_atom(tipo) and is_map(mapa) do
    if Keyword.has_key?(multi.registros, tipo),
      do: {:ok, tipo, mapa},
      else:
        {:error,
         [
           Diagnostico.nuevo(
             tipo: :estructura,
             linea: numero,
             esperado: "un tipo de registro de #{inspect(Keyword.keys(multi.registros))}",
             recibido: inspect(tipo),
             causa_probable: "el tipo no está en :registros del multiregistro"
           )
         ]}
  end

  defp tipar(%__MODULE__{discriminador: %{campo: campo}} = multi, mapa, numero)
       when is_map(mapa) and not is_struct(mapa) do
    literal = Map.get(mapa, campo)

    case Enum.find(multi.registros, fn {_tipo, d} ->
           is_binary(literal) and Enum.any?(d.valores, &Tipo.Constante.coincide?(&1, literal, " "))
         end) do
      {tipo, _definicion} ->
        {:ok, tipo, mapa}

      nil ->
        {:error,
         [
           Diagnostico.nuevo(
             tipo: :estructura,
             linea: numero,
             esperado: "un mapa con el literal de algún tipo en #{inspect(campo)}, o {tipo, mapa}",
             recibido: inspect(literal),
             causa_probable: "sin el literal no se sabe con qué layout escribir el registro"
           )
         ]}
    end
  end

  defp tipar(_multi, otro, numero) do
    {:error,
     [
       Diagnostico.nuevo(
         tipo: :entrada,
         linea: numero,
         esperado: "cada registro como {tipo, mapa}, como los que devuelve parsear/3",
         recibido: Entrada.describir(otro),
         causa_probable: "sin el tipo no se sabe con qué layout escribir el registro"
       )
     ]}
  end

  @doc """
  El multiregistro como datos, con el layout de cada tipo adentro: ver
  `AnchoFijo.Layout.a_mapa/1`. Un discriminador por función no se puede
  serializar y levanta `ArgumentError`.
  """
  @spec a_mapa(t()) :: map()
  def a_mapa(%__MODULE__{} = multi), do: AnchoFijo.Serializacion.multiregistro_a_mapa(multi)

  @doc "La vuelta de `a_mapa/1`, con los diagnósticos de `nuevo/1`."
  @spec desde_mapa(map()) :: {:ok, t()} | {:error, [Diagnostico.t()]}
  def desde_mapa(mapa), do: AnchoFijo.Serializacion.multiregistro_desde_mapa(mapa)

  @doc "El multiregistro como JSON."
  @spec a_json(t()) :: String.t()
  def a_json(%__MODULE__{} = multi), do: multi |> a_mapa() |> AnchoFijo.Json.codificar()

  @doc "Un multiregistro desde su JSON."
  @spec desde_json(binary()) :: {:ok, t()} | {:error, [Diagnostico.t()]}
  def desde_json(json) when is_binary(json) do
    case AnchoFijo.Json.decodificar(json) do
      {:ok, mapa} -> desde_mapa(mapa)
      {:error, motivo} -> {:error, [Layout.json_invalido(motivo)]}
    end
  end

  @doc """
  La especificación del multiregistro como texto: una tabla por tipo de
  registro y la lista de controles. Ver `AnchoFijo.Documentacion.documentar/2`.
  """
  @spec documentar(t(), keyword()) :: String.t()
  def documentar(%__MODULE__{} = multi, opts \\ []),
    do: AnchoFijo.Documentacion.documentar(multi, opts)

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
