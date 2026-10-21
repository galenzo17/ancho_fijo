defmodule AnchoFijo.Layout do
  @moduledoc """
  La definición del formato, como data.

  Un layout es una lista de campos más tres decisiones globales: en qué encoding
  viene el archivo, si las posiciones se cuentan en bytes o en caracteres, y qué
  largo total se espera por línea. Cambiar de formato es cambiar este mapa, no
  escribir código.

      iex> alias AnchoFijo.Layout
      iex> {:ok, layout} = Layout.nuevo(
      ...>   nombre: "nómina banco X",
      ...>   encoding: :latin1,
      ...>   campos: [
      ...>     [nombre: :rut, largo: 10],
      ...>     [nombre: :beneficiario, largo: 30],
      ...>     [nombre: :monto, largo: 12, tipo: :decimal, precision: 2]
      ...>   ]
      ...> )
      iex> Layout.largo(layout)
      52

  Las posiciones son 1-based porque así vienen en todas las especificaciones
  bancarias del mundo: cuando el anexo dice "posiciones 21 a 32", el layout dice
  lo mismo. Si se omiten, cada campo se encadena al anterior.

  ## Validación de la definición misma

  `nuevo/1` revisa el layout antes de ver un archivo. Distingue dos gravedades,
  y la distinción es de dominio: un solapamiento es siempre un error de
  transcripción del anexo, mientras que un hueco suele ser una zona reservada
  legítima del formato. Los huecos quedan en `:advertencias` y no impiden
  parsear.

      iex> alias AnchoFijo.Layout
      iex> {:error, [diagnostico]} = Layout.nuevo(campos: [
      ...>   [nombre: :rut, posicion: 1, largo: 10],
      ...>   [nombre: :nombre, posicion: 8, largo: 20]
      ...> ])
      iex> AnchoFijo.Diagnostico.mensaje(diagnostico)
      "layout, campo :nombre (posiciones 8-27): se esperaba que empezara en la posición 11 o después, llegó 8; se solapa con el campo :rut (posiciones 1-10)"

      iex> alias AnchoFijo.Layout
      iex> {:ok, layout} = Layout.nuevo(campos: [
      ...>   [nombre: :rut, posicion: 1, largo: 10],
      ...>   [nombre: :nombre, posicion: 14, largo: 20]
      ...> ])
      iex> AnchoFijo.Diagnostico.mensaje(hd(layout.advertencias))
      "layout, campo :nombre (posiciones 14-33): se esperaba que empezara en la posición 11, llegó 14; quedan 3 posiciones sin declarar entre :rut y :nombre; si el formato tiene relleno ahí, ignore esta advertencia"

  ## Opciones

    * `:campos` — obligatorio. Lista de definiciones de `AnchoFijo.Campo`
      (keyword lists, mapas o structs ya construidos).
    * `:encoding` — `:utf8` (default) o `:latin1`.
    * `:unidad` — `:bytes` (default) o `:caracteres`. Ver más abajo.
    * `:relleno_final` — `:estricto` (default) o `:tolerar`. Ver más abajo.
    * `:largo` — largo total esperado por línea. Si se omite, se infiere del
      último campo.
    * `:nombre` — etiqueta libre para identificar el layout en logs.
    * `:identidad` — `[campos: [:lote, :fecha]]`: los campos del primer
      registro que identifican el lote. Ver `AnchoFijo.Identidad`.

  ## Líneas cortas por relleno recortado

  Hay emisores que recortan los espacios finales de cada línea, o solo de la
  última. Con el default `:estricto` esa línea es un diagnóstico de largo y la
  fila se bota. Con `relleno_final: :tolerar`, si lo que falta cabe completo en
  el relleno del final de la línea, se completa y queda una advertencia.

  La condición es estrecha a propósito: se tolera **relleno** faltante, no bytes
  faltantes. Si el tramo que falta alcanza a un campo que no es relleno —un
  monto con ceros a la izquierda, una fecha— sigue siendo error, porque
  completar con espacios ahí no repone el dato: lo inventa.

  ## Bytes o caracteres

  El default es `:bytes` porque un formato de ancho fijo se define sobre el
  archivo físico: cuando el banco dice "120 posiciones", cuenta bytes. Con
  latin-1 da lo mismo, un byte es un carácter. Con UTF-8 no: si el archivo trae
  acentos y el emisor contó caracteres, hay que declarar `unidad: :caracteres` o
  cada línea con una "ñ" se corre un byte.
  """

  alias AnchoFijo.Campo
  alias AnchoFijo.Diagnostico
  alias AnchoFijo.Opciones

  @opciones [
    :campos,
    :encoding,
    :unidad,
    :relleno_final,
    :largo,
    :nombre,
    :identidad,
    :decimales_como
  ]
  @encodings [:utf8, :latin1]
  @unidades [:bytes, :caracteres]
  @rellenos_finales [:estricto, :tolerar]

  @type t :: %__MODULE__{
          nombre: String.t() | nil,
          campos: [Campo.t()],
          largo: pos_integer(),
          encoding: :utf8 | :latin1,
          unidad: :bytes | :caracteres,
          relleno_final: :estricto | :tolerar,
          advertencias: [Diagnostico.t()],
          identidad: %{campos: [atom()]} | nil,
          decimales_como: :decimal | nil
        }

  defstruct nombre: nil,
            campos: [],
            largo: nil,
            encoding: :utf8,
            unidad: :bytes,
            relleno_final: :estricto,
            advertencias: [],
            identidad: nil,
            decimales_como: nil

  @doc """
  Valida y construye un layout.

  Devuelve `{:ok, layout}` —posiblemente con `:advertencias`— o
  `{:error, diagnosticos}` con todos los problemas encontrados, no solo el
  primero: corregir una definición de 40 campos de a un error por compilación es
  una forma lenta de perder el día.

      iex> {:ok, layout} = AnchoFijo.Layout.nuevo(campos: [[nombre: :codigo, largo: 4, tipo: :entero]])
      iex> layout.largo
      4

      iex> {:error, [diagnostico]} = AnchoFijo.Layout.nuevo(campos: [])
      iex> AnchoFijo.Diagnostico.mensaje(diagnostico)
      "layout: se esperaba al menos un campo en :campos, llegó una lista vacía; un layout sin campos no puede leer nada"
  """
  @spec nuevo(term()) :: {:ok, t()} | {:error, [Diagnostico.t()]}
  def nuevo(atributos) do
    with {:ok, atributos} <- a_mapa(atributos),
         :ok <- validar_claves(atributos),
         {:ok, globales} <- validar_globales(atributos),
         {:ok, campos} <- construir_campos(Map.get(atributos, :campos, []), globales),
         campos = posicionar(campos),
         :ok <- validar_disposicion(campos),
         :ok <- validar_encodings(campos, globales),
         {:ok, identidad} <- validar_identidad(Map.get(atributos, :identidad), campos),
         {:ok, largo, advertencias} <- resolver_largo(campos, globales, atributos) do
      {:ok,
       struct(
         %__MODULE__{},
         Map.merge(globales, %{
           campos: campos,
           largo: largo,
           advertencias: advertencias,
           identidad: identidad
         })
       )}
    end
  end

  # Los campos que identifican el lote tienen que existir en el layout. Es
  # una lista y no un solo campo porque la identidad real suele ser número de
  # lote más fecha: el número solo se repite cada año.
  defp validar_identidad(nil, _campos), do: {:ok, nil}

  defp validar_identidad(identidad, campos) do
    nombres = Enum.map(campos, & &1.nombre)
    declarados = if Keyword.keyword?(identidad), do: Keyword.get(identidad, :campos), else: nil

    cond do
      not is_list(declarados) or declarados == [] ->
        {:error, [falla("identidad: [campos: [...]] con al menos un campo", identidad, nil)]}

      declarados -- nombres != [] ->
        {:error,
         [
           falla(
             "campos de identidad que existan en el layout",
             inspect(declarados -- nombres),
             "la identidad se lee del primer registro con este mismo layout"
           )
         ]}

      true ->
        {:ok, %{campos: declarados}}
    end
  end

  @doc """
  Igual que `nuevo/1` pero levanta `AnchoFijo.Error` con el reporte completo.

      iex> AnchoFijo.Layout.nuevo!(campos: [[nombre: :a, largo: 2]]).unidad
      :bytes

      iex> AnchoFijo.Layout.nuevo!(campos: [[nombre: :a, largo: 0]])
      ** (AnchoFijo.Error) layout, campo :a: se esperaba un :largo entero mayor que cero, llegó 0; revise la especificación del formato
  """
  @spec nuevo!(Enumerable.t()) :: t()
  def nuevo!(atributos) do
    case nuevo(atributos) do
      {:ok, layout} -> layout
      {:error, diagnosticos} -> raise AnchoFijo.Error, diagnosticos
    end
  end

  @doc """
  Acepta un layout ya construido o una definición y devuelve siempre `{:ok, layout}`.

  Es lo que usan `AnchoFijo.parsear/3` y `AnchoFijo.stream/3` para que el
  llamador pueda pasar la definición en línea sin ceremonia.

      iex> {:ok, layout} = AnchoFijo.Layout.coercer(campos: [[nombre: :a, largo: 2]])
      iex> AnchoFijo.Layout.coercer(layout)
      {:ok, layout}
  """
  @spec coercer(term()) :: {:ok, t()} | {:error, [Diagnostico.t()]}
  def coercer(%__MODULE__{} = layout), do: {:ok, layout}
  def coercer(atributos), do: nuevo(atributos)

  @doc "Como `coercer/1`, pero levanta `AnchoFijo.Error`."
  @spec coercer!(t() | term()) :: t()
  def coercer!(layout) do
    case coercer(layout) do
      {:ok, layout} -> layout
      {:error, diagnosticos} -> raise AnchoFijo.Error, diagnosticos
    end
  end

  @doc """
  La especificación del layout como texto, para el documento que se manda
  al banco o al cliente. Ver `AnchoFijo.Documentacion.documentar/2`.
  """
  @spec documentar(t() | term(), keyword()) :: String.t()
  def documentar(layout, opts \\ []), do: AnchoFijo.Documentacion.documentar(layout, opts)

  @doc """
  Largo total de línea que el layout espera.

      iex> AnchoFijo.Layout.largo(AnchoFijo.Layout.nuevo!(campos: [[nombre: :a, largo: 7]]))
      7
  """
  @spec largo(t()) :: pos_integer()
  def largo(%__MODULE__{largo: largo}), do: largo

  @doc """
  Busca un campo por nombre.

      iex> layout = AnchoFijo.Layout.nuevo!(campos: [[nombre: :a, largo: 2], [nombre: :b, largo: 3]])
      iex> AnchoFijo.Layout.campo(layout, :b) |> AnchoFijo.Campo.rango()
      {3, 5}
      iex> AnchoFijo.Layout.campo(layout, :inexistente)
      nil
  """
  @spec campo(t(), atom()) :: Campo.t() | nil
  def campo(%__MODULE__{campos: campos}, nombre) do
    Enum.find(campos, &(&1.nombre == nombre))
  end

  @doc """
  Nombres de los campos, en orden de posición.

      iex> AnchoFijo.Layout.nuevo!(campos: [[nombre: :a, largo: 2], [nombre: :b, largo: 3]])
      ...> |> AnchoFijo.Layout.nombres()
      [:a, :b]
  """
  @spec nombres(t()) :: [atom()]
  def nombres(%__MODULE__{campos: campos}), do: Enum.map(campos, & &1.nombre)

  @doc """
  Contexto de lectura que el layout entrega a cada campo.

      iex> AnchoFijo.Layout.nuevo!(campos: [[nombre: :a, largo: 2]], encoding: :latin1)
      ...> |> AnchoFijo.Layout.contexto(9)
      %{encoding: :latin1, unidad: :bytes, linea: 9}
  """
  @spec contexto(t(), pos_integer() | nil) :: Campo.contexto()
  def contexto(%__MODULE__{} = layout, linea) do
    %{encoding: layout.encoding, unidad: layout.unidad, linea: linea}
  end

  defp a_mapa(atributos) do
    case Opciones.a_mapa(atributos) do
      {:ok, mapa} ->
        {:ok, mapa}

      :error ->
        {:error,
         [
           falla(
             "la definición del layout como keyword list o mapa",
             atributos,
             "el argumento no es una definición de layout"
           )
         ]}
    end
  end

  # Una clave que no existe no se ignora: `campo: [...]` en vez de `campos:`
  # o `enconding:` en vez de `encoding:` dejarían un layout distinto del que
  # se escribió, sin ninguna señal. `:advertencias` se admite porque viene en
  # un `Map.from_struct/1` de otro layout.
  defp validar_claves(atributos) do
    case Opciones.claves_desconocidas(atributos, [:advertencias | @opciones]) do
      [] ->
        :ok

      desconocidas ->
        {:error,
         Enum.map(desconocidas, fn clave ->
           falla(
             "opciones en #{inspect(@opciones)}",
             clave,
             "la opción no existe y se ignoraría en silencio; probablemente un error de tipeo"
           )
         end)}
    end
  end

  defp validar_globales(atributos) do
    encoding = Map.get(atributos, :encoding, :utf8)
    unidad = Map.get(atributos, :unidad, :bytes)

    relleno_final = Map.get(atributos, :relleno_final, :estricto)
    decimales_como = Map.get(atributos, :decimales_como)

    diagnosticos =
      Enum.concat([
        validar_en(encoding, @encodings, :encoding),
        validar_en(unidad, @unidades, :unidad),
        validar_en(relleno_final, @rellenos_finales, :relleno_final),
        validar_en(decimales_como, [nil, :decimal], :decimales_como),
        validar_nombre(Map.get(atributos, :nombre))
      ])

    case diagnosticos do
      [] ->
        {:ok,
         %{
           encoding: encoding,
           unidad: unidad,
           relleno_final: relleno_final,
           nombre: Map.get(atributos, :nombre),
           decimales_como: decimales_como
         }}

      diagnosticos ->
        {:error, diagnosticos}
    end
  end

  defp validar_nombre(nombre) when is_binary(nombre) or is_nil(nombre), do: []

  defp validar_nombre(nombre) do
    [
      falla(
        "un :nombre binario, o ninguno",
        nombre,
        "el nombre del layout es una etiqueta para logs"
      )
    ]
  end

  defp validar_en(valor, permitidos, opcion) do
    if valor in permitidos do
      []
    else
      [
        falla(
          "#{inspect(opcion)} en #{inspect(permitidos)}",
          valor,
          nil
        )
      ]
    end
  end

  # `decimales_como: :decimal` es el default de `como:` para los campos
  # :decimal que no lo declaran; el campo se reconstruye para que la
  # validación (Decimal disponible) corra igual que si lo hubiera declarado.
  defp construir_campos(definiciones, %{decimales_como: nil}), do: construir_campos(definiciones)

  defp construir_campos(definiciones, %{decimales_como: como}) when is_list(definiciones) do
    definiciones
    |> Enum.map(&con_decimales_como(&1, como))
    |> construir_campos()
  end

  defp construir_campos(definiciones, _globales), do: construir_campos(definiciones)

  defp con_decimales_como(%Campo{tipo: :decimal, como: nil} = campo, como),
    do: campo |> Map.from_struct() |> Map.put(:como, como)

  defp con_decimales_como(definicion, como) do
    case Opciones.a_mapa(definicion) do
      {:ok, %{tipo: :decimal} = mapa} -> Map.put_new(mapa, :como, como)
      _otra -> definicion
    end
  end

  defp construir_campos([]) do
    {:error,
     [
       falla(
         "al menos un campo en :campos",
         "una lista vacía",
         "un layout sin campos no puede leer nada"
       )
     ]}
  end

  defp construir_campos(definiciones) when is_list(definiciones) do
    {campos, diagnosticos} =
      Enum.reduce(definiciones, {[], []}, fn definicion, {campos, diagnosticos} ->
        case construir_campo(definicion) do
          {:ok, campo} -> {[campo | campos], diagnosticos}
          {:error, nuevos} -> {campos, diagnosticos ++ nuevos}
        end
      end)

    case diagnosticos do
      [] -> validar_nombres_unicos(Enum.reverse(campos))
      diagnosticos -> {:error, diagnosticos}
    end
  end

  defp construir_campos(otro) do
    {:error, [falla("una lista de campos en :campos", otro, nil)]}
  end

  defp construir_campo(%Campo{} = campo), do: {:ok, campo}
  defp construir_campo(definicion), do: Campo.nuevo(definicion)

  defp validar_nombres_unicos(campos) do
    duplicados =
      campos
      |> Enum.frequencies_by(& &1.nombre)
      |> Enum.filter(fn {_nombre, veces} -> veces > 1 end)
      |> Enum.map(fn {nombre, veces} ->
        falla(
          "nombres de campo únicos",
          "#{inspect(nombre)} #{veces} veces",
          "el registro es un mapa: el segundo campo con ese nombre sobrescribiría al primero"
        )
      end)

    case duplicados do
      [] -> {:ok, campos}
      duplicados -> {:error, duplicados}
    end
  end

  # Las posiciones explícitas y las encadenadas se pueden mezclar: quien
  # transcribe un anexo de 60 campos suele copiar las posiciones de los primeros
  # y dejar que el resto se acomode. Cualquier inconsistencia que eso produzca
  # aparece igual en la validación de solapamientos.
  defp posicionar(campos) do
    campos
    |> Enum.map_reduce(1, fn %Campo{} = campo, siguiente ->
      campo = %Campo{campo | posicion: campo.posicion || siguiente}
      {campo, Campo.fin(campo) + 1}
    end)
    |> elem(0)
    |> Enum.sort_by(& &1.posicion)
  end

  # Con `unidad: :caracteres` la línea se decodifica entera con el encoding
  # del layout antes de cortar los campos: un encoding por campo no tendría
  # dónde aplicarse, y aceptarlo sería ignorarlo en silencio.
  defp validar_encodings(campos, %{unidad: :caracteres}) do
    case Enum.filter(campos, &(not is_nil(&1.encoding))) do
      [] ->
        :ok

      [campo | _] ->
        {:error,
         [
           Diagnostico.nuevo(
             tipo: :layout,
             campo: campo.nombre,
             esperado: "ningún :encoding por campo con unidad: :caracteres",
             recibido: inspect(campo.encoding),
             causa_probable:
               "con :caracteres la línea se decodifica entera con el encoding del layout; " <>
                 "el encoding por campo solo aplica con unidad: :bytes"
           )
         ]}
    end
  end

  defp validar_encodings(_campos, _globales), do: :ok

  defp validar_disposicion(campos) do
    diagnosticos =
      campos
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.flat_map(fn [anterior, actual] -> validar_par(anterior, actual) end)

    case diagnosticos do
      [] -> :ok
      diagnosticos -> {:error, diagnosticos}
    end
  end

  defp validar_par(anterior, actual) do
    fin_anterior = Campo.fin(anterior)

    if actual.posicion <= fin_anterior do
      [solapamiento(anterior, actual, fin_anterior)]
    else
      []
    end
  end

  defp solapamiento(anterior, actual, fin_anterior) do
    Diagnostico.nuevo(
      tipo: :layout,
      campo: actual.nombre,
      posicion: Campo.rango(actual),
      esperado: "que empezara en la posición #{fin_anterior + 1} o después",
      recibido: actual.posicion,
      causa_probable: "se solapa con el campo #{inspect(anterior.nombre)} #{rango_texto(anterior)}"
    )
  end

  defp resolver_largo(campos, globales, atributos) do
    ocupado = campos |> Enum.map(&Campo.fin/1) |> Enum.max()
    declarado = Map.get(atributos, :largo)
    unidad = Campo.nombre_unidad(globales.unidad)

    case declarado do
      nil ->
        {:ok, ocupado, huecos(campos, ocupado, ocupado, unidad)}

      largo when is_integer(largo) and largo >= ocupado ->
        {:ok, largo, huecos(campos, ocupado, largo, unidad)}

      largo ->
        {:error, [largo_insuficiente(largo, ocupado, unidad)]}
    end
  end

  defp largo_insuficiente(declarado, ocupado, unidad) do
    Diagnostico.nuevo(
      tipo: :layout,
      esperado: "un :largo de al menos #{ocupado} #{unidad}, que es lo que ocupan los campos",
      recibido: declarado,
      causa_probable:
        "el :largo declarado no alcanza para los campos definidos; sobra un campo o falta largo"
    )
  end

  defp huecos(campos, ocupado, largo, unidad) do
    intermedios =
      campos
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.flat_map(fn [anterior, actual] -> hueco_entre(anterior, actual) end)

    intermedios ++
      hueco_inicial(campos) ++
      hueco_final(ocupado, largo, unidad) ++
      monedas_sin_tabla(campos)
  end

  # Una moneda fuera de la tabla ISO 4217 con :precision explícita se acepta,
  # pero la escala quedó sin verificar y hay que decirlo.
  defp monedas_sin_tabla(campos) do
    campos
    |> Enum.filter(fn campo ->
      campo.modulo == AnchoFijo.Tipo.Decimal and not is_nil(campo.moneda)
    end)
    |> Enum.reject(fn campo -> match?({:ok, _}, AnchoFijo.Monto.escala(campo.moneda)) end)
    |> Enum.map(fn campo ->
      Diagnostico.nuevo(
        tipo: :layout,
        campo: campo.nombre,
        posicion: Campo.rango(campo),
        esperado: "una :moneda de la tabla ISO 4217 de AnchoFijo.Monto",
        recibido: campo.moneda,
        causa_probable:
          "la moneda no está en la tabla, así que la precision: #{campo.precision} declarada " <>
            "no se pudo verificar contra su escala"
      )
    end)
  end

  defp hueco_entre(anterior, actual) do
    esperada = Campo.fin(anterior) + 1

    if actual.posicion > esperada do
      [
        Diagnostico.nuevo(
          tipo: :layout,
          campo: actual.nombre,
          posicion: Campo.rango(actual),
          esperado: "que empezara en la posición #{esperada}",
          recibido: actual.posicion,
          causa_probable:
            "quedan #{actual.posicion - esperada} posiciones sin declarar entre " <>
              "#{inspect(anterior.nombre)} y #{inspect(actual.nombre)}; " <>
              "si el formato tiene relleno ahí, ignore esta advertencia"
        )
      ]
    else
      []
    end
  end

  defp hueco_inicial([%Campo{} = primero | _resto]) do
    if primero.posicion > 1 do
      [
        Diagnostico.nuevo(
          tipo: :layout,
          campo: primero.nombre,
          posicion: Campo.rango(primero),
          esperado: "que el primer campo empezara en la posición 1",
          recibido: primero.posicion,
          causa_probable: "las primeras #{primero.posicion - 1} posiciones de cada línea se ignoran"
        )
      ]
    else
      []
    end
  end

  defp hueco_final(ocupado, largo, unidad) when largo > ocupado do
    [
      Diagnostico.nuevo(
        tipo: :layout,
        esperado: "que los campos cubrieran los #{largo} #{unidad} declarados",
        recibido: ocupado,
        causa_probable:
          "las últimas #{largo - ocupado} posiciones de cada línea se ignoran; " <>
            "es normal si el formato reserva relleno al final"
      )
    ]
  end

  defp hueco_final(_ocupado, _largo, _unidad), do: []

  defp rango_texto(campo) do
    {desde, hasta} = Campo.rango(campo)
    "(posiciones #{desde}-#{hasta})"
  end

  defp falla(esperado, recibido, causa) do
    Diagnostico.nuevo(tipo: :layout, esperado: esperado, recibido: recibido, causa_probable: causa)
  end
end
