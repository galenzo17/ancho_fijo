defmodule AnchoFijo.Serializacion do
  @moduledoc false
  # Layouts como datos: a un mapa de claves string sin átomos ni funciones, y
  # de vuelta. Es lo que `Layout.a_mapa/1`, `Layout.desde_mapa/1` y las
  # mismas de `Multiregistro` hacen; vive aparte para que los dos módulos
  # compartan la conversión de valores.
  #
  # El esquema tiene versión (`"version" => 1`): si algún día cambia la forma,
  # `desde_mapa/1` sabe qué recibió. El JSON Schema está en
  # priv/layout.schema.json.

  alias AnchoFijo.Campo
  alias AnchoFijo.Diagnostico
  alias AnchoFijo.Layout
  alias AnchoFijo.Multiregistro
  alias AnchoFijo.Tipo
  alias AnchoFijo.Tipo.Patron

  @compile {:no_warn_undefined, Decimal}

  @version 1

  @tipos_internos Map.new(Tipo.internos(), fn {atomo, _modulo} -> {Atom.to_string(atomo), atomo} end)

  # Opciones de campo cuyo valor es un átomo que viaja como string.
  @atomicas [:trim, :separador, :moneda, :signo, :dv, :como, :encoding]
  @claves_layout [
    :nombre,
    :encoding,
    :unidad,
    :relleno_final,
    :largo,
    :identidad,
    :decimales_como,
    :campos
  ]
  @atomicas_layout [:encoding, :unidad, :relleno_final, :decimales_como]
  @cantidades ["uno", "opcional", "varios", "al_menos_uno"]
  @ubicaciones ["primera", "resto", "ultima"]

  @spec version() :: pos_integer()
  def version, do: @version

  # ------------------------------------------------------------- a mapa

  @spec layout_a_mapa(Layout.t()) :: map()
  def layout_a_mapa(%Layout{} = layout) do
    %{
      "version" => @version,
      "nombre" => layout.nombre,
      "encoding" => Atom.to_string(layout.encoding),
      "unidad" => Atom.to_string(layout.unidad),
      "relleno_final" => Atom.to_string(layout.relleno_final),
      "largo" => layout.largo,
      "identidad" =>
        layout.identidad && %{"campos" => Enum.map(layout.identidad.campos, &Atom.to_string/1)},
      "decimales_como" => layout.decimales_como && Atom.to_string(layout.decimales_como),
      "campos" => Enum.map(layout.campos, &campo_a_mapa/1)
    }
    |> sin_nulos()
  end

  # Lo declarado y lo que difiere del default del struct; nunca el módulo
  # resuelto ni la posición implícita (que sí va: con posiciones explícitas
  # el mapa se lee igual aunque el lector no conozca el encadenamiento).
  @spec campo_a_mapa(Campo.t()) :: map()
  def campo_a_mapa(%Campo{} = campo) do
    # El default de :sensible depende del tipo: un RUT lo es salvo que se diga.
    defaults =
      %Campo{}
      |> Map.from_struct()
      |> Map.put(:sensible, campo.modulo == Tipo.Rut)

    declaradas =
      campo
      |> Map.from_struct()
      |> Map.drop([:nombre, :posicion, :largo, :tipo, :modulo, :opciones, :reglas])
      |> Enum.reject(fn {clave, valor} -> Map.get(defaults, clave) == valor end)
      |> Map.new(fn {clave, valor} -> {Atom.to_string(clave), valor_a_dato(valor)} end)

    # Las reglas salen planas, como se declaran en `Campo.nuevo/1`.
    reglas =
      campo.reglas
      |> Map.from_struct()
      |> Enum.reject(fn {_clave, valor} -> is_nil(valor) end)
      |> Map.new(fn {clave, valor} -> {Atom.to_string(clave), valor_a_dato(valor)} end)

    propias =
      Map.new(campo.opciones, fn {clave, valor} -> {Atom.to_string(clave), valor_a_dato(valor)} end)

    %{
      "nombre" => Atom.to_string(campo.nombre),
      "posicion" => campo.posicion,
      "largo" => campo.largo,
      "tipo" => tipo_a_dato(campo.tipo)
    }
    |> Map.merge(declaradas)
    |> Map.merge(reglas)
    |> Map.merge(propias)
  end

  defp tipo_a_dato(tipo) do
    nombre = Atom.to_string(tipo)
    if Map.has_key?(@tipos_internos, nombre), do: nombre, else: inspect(tipo)
  end

  defp valor_a_dato([%Campo{} | _] = campos), do: Enum.map(campos, &campo_a_mapa/1)

  defp valor_a_dato(%Regex{} = patron),
    do: %{"patron" => Regex.source(patron), "opciones" => Regex.opts(patron) |> to_string()}

  defp valor_a_dato(%Date{} = fecha), do: Date.to_iso8601(fecha)
  defp valor_a_dato(%Time{} = hora), do: Time.to_iso8601(hora)
  defp valor_a_dato(%NaiveDateTime{} = valor), do: NaiveDateTime.to_iso8601(valor)
  defp valor_a_dato(%{__struct__: Decimal} = decimal), do: Decimal.to_string(decimal, :normal)

  defp valor_a_dato(%AnchoFijo.Monto{} = monto),
    do: [monto.unidades, monto.precision, Atom.to_string(monto.moneda)]

  defp valor_a_dato(condicion)
       when is_list(condicion) and condicion != [] and is_tuple(hd(condicion)),
       do: Map.new(condicion, fn {clave, valor} -> {Atom.to_string(clave), valor_a_dato(valor)} end)

  defp valor_a_dato(%{} = variantes) when not is_struct(variantes),
    do: Map.new(variantes, fn {clave, campos} -> {valor_a_dato(clave), valor_a_dato(campos)} end)

  defp valor_a_dato(valor) when is_boolean(valor) or is_nil(valor), do: valor
  defp valor_a_dato(valor) when is_atom(valor), do: Atom.to_string(valor)
  defp valor_a_dato({a, b}), do: [valor_a_dato(a), valor_a_dato(b)]
  defp valor_a_dato(valor) when is_list(valor), do: Enum.map(valor, &valor_a_dato/1)

  defp valor_a_dato(valor) when is_function(valor),
    do:
      raise(
        ArgumentError,
        "una función (en: o generador:) no se puede serializar; use una lista o quítela antes de a_mapa/1"
      )

  defp valor_a_dato(%{__struct__: modulo} = valor) when modulo != Decimal,
    do: raise(ArgumentError, "#{inspect(valor)} no se puede serializar como dato del layout")

  defp valor_a_dato(valor), do: valor

  @spec multiregistro_a_mapa(Multiregistro.t()) :: map()
  def multiregistro_a_mapa(%Multiregistro{} = multi) do
    %{
      "version" => @version,
      "nombre" => multi.nombre,
      "orden" => Atom.to_string(multi.orden),
      "discriminador" => discriminador_a_mapa(multi.discriminador),
      "registros" =>
        Enum.map(multi.registros, fn {tipo, d} ->
          sin_nulos(%{
            "tipo" => Atom.to_string(tipo),
            "valor" => if(d.valores == [], do: nil, else: d.valores),
            "cantidad" => Atom.to_string(d.cantidad),
            "ubicacion" => d.ubicacion && Atom.to_string(d.ubicacion),
            "layout" => layout_a_mapa(d.layout)
          })
        end),
      "controles" => Enum.map(multi.controles, &control_a_mapa/1)
    }
    |> sin_nulos()
  end

  defp discriminador_a_mapa(%{por: :funcion}) do
    raise ArgumentError,
          "un discriminador por función no se puede serializar: no hay forma de guardar una función como dato; " <>
            "use :largo, :posicion_en_archivo, [posicion:, largo:] o [campo:]"
  end

  defp discriminador_a_mapa(%{por: por}), do: %{"por" => Atom.to_string(por)}
  defp discriminador_a_mapa(%{campo: campo}), do: %{"campo" => Atom.to_string(campo)}
  defp discriminador_a_mapa(%{posicion: p, largo: l}), do: %{"posicion" => p, "largo" => l}

  defp control_a_mapa(control) do
    base = %{"en" => Atom.to_string(control.en), "campo" => Atom.to_string(control.campo)}

    base
    |> Map.merge(
      case control do
        %{cuenta: tipo} -> %{"cuenta" => Atom.to_string(tipo)}
        %{suma: {tipo, campo}} -> %{"suma" => [Atom.to_string(tipo), Atom.to_string(campo)]}
      end
    )
    |> Map.merge(
      if(control[:agrupar_por],
        do: %{"agrupar_por" => Atom.to_string(control.agrupar_por)},
        else: %{}
      )
    )
  end

  defp sin_nulos(mapa), do: mapa |> Enum.reject(fn {_k, v} -> is_nil(v) end) |> Map.new()

  # ------------------------------------------------------------ desde mapa
  #
  # Un valor que no se puede convertir (una fecha que no existe, un patrón
  # que no compila, un decimal que no es número) no levanta: queda como
  # diagnóstico `:layout` con el campo y la clave, se saca de la definición
  # y el resto sigue a `nuevo/1`, para que todos los problemas salgan juntos.

  @spec layout_desde_mapa(term()) :: {:ok, Layout.t()} | {:error, [Diagnostico.t()]}
  def layout_desde_mapa(mapa) when is_map(mapa) do
    with :ok <- validar_version(mapa) do
      {definicion, invalidos} = layout_mapa_a_definicion(mapa)
      con_invalidos(Layout.nuevo(definicion), invalidos)
    end
  end

  def layout_desde_mapa(otro), do: {:error, [falla("un mapa con la definición del layout", otro)]}

  defp con_invalidos(resultado, []), do: resultado
  defp con_invalidos({:ok, _construido}, invalidos), do: {:error, invalidos}
  defp con_invalidos({:error, otros}, invalidos), do: {:error, invalidos ++ otros}

  defp validar_version(mapa) do
    case Map.get(mapa, "version", @version) do
      @version ->
        :ok

      otra ->
        {:error,
         [
           falla(
             "version #{@version} del esquema de serialización",
             otra,
             "el mapa viene de otra versión de la librería; regenérelo con a_mapa/1"
           )
         ]}
    end
  end

  # La definición para `Layout.nuevo/1` y los diagnósticos de lo que no se
  # pudo convertir. También la usa cada tipo de un multiregistro.
  defp layout_mapa_a_definicion(mapa) when is_map(mapa) do
    {pares, invalidos} =
      mapa
      |> Map.delete("version")
      |> Enum.map_reduce([], fn {clave, valor}, acumulados ->
        {par, nuevos} = clave_layout(clave, valor)
        {par, acumulados ++ nuevos}
      end)

    {Map.new(pares), invalidos}
  end

  defp layout_mapa_a_definicion(otro), do: {otro, []}

  # Las claves conocidas vuelven a átomo; una desconocida queda como string y
  # `Layout.nuevo/1` la reclama, que es la misma política que con un átomo
  # mal escrito.
  defp clave_layout("campos", campos) when is_list(campos) do
    {convertidos, invalidos} = campos_desde_datos(campos)
    {{:campos, convertidos}, invalidos}
  end

  defp clave_layout("identidad", %{"campos" => campos}) when is_list(campos),
    do: {{:identidad, [campos: Enum.map(campos, &a_atomo/1)]}, []}

  defp clave_layout(clave, valor) do
    case atomo_conocido(clave, @claves_layout) do
      nil -> {{clave, valor}, []}
      atomo when atomo in @atomicas_layout -> {{atomo, a_atomo(valor)}, []}
      atomo -> {{atomo, valor}, []}
    end
  end

  defp campos_desde_datos(campos) do
    Enum.map_reduce(campos, [], fn campo, acumulados ->
      {atributos, invalidos} = campo_desde_mapa(campo)
      {atributos, acumulados ++ invalidos}
    end)
  end

  @spec campo_desde_mapa(term()) :: {map() | term(), [Diagnostico.t()]}
  def campo_desde_mapa(mapa) when is_map(mapa) do
    tipo = tipo_desde_dato(Map.get(mapa, "tipo", "texto"))
    conocidas = Campo.claves() ++ opciones_propias(tipo)
    nombre = mapa |> Map.get("nombre") |> a_atomo()

    {pares, invalidos} =
      mapa
      |> Map.put("tipo", tipo)
      |> Enum.map_reduce([], fn {clave, valor}, acumulados ->
        case valor_campo(clave, valor, tipo, conocidas) do
          {:ok, par} ->
            {par, acumulados}

          {:ok, par, anidados} ->
            {par, acumulados ++ anidados}

          {:error, esperado, causa} ->
            {nil, acumulados ++ [invalido(nombre, clave, esperado, valor, causa)]}
        end
      end)

    {pares |> Enum.reject(&is_nil/1) |> Map.new(), invalidos}
  end

  def campo_desde_mapa(otro), do: {otro, []}

  defp valor_campo("tipo", tipo, _tipo, _conocidas), do: {:ok, {:tipo, tipo}}
  defp valor_campo("nombre", nombre, _tipo, _conocidas), do: {:ok, {:nombre, a_atomo(nombre)}}
  defp valor_campo("segun", segun, _tipo, _conocidas), do: {:ok, {:segun, a_atomo(segun)}}

  defp valor_campo("formato", formato, _tipo, _conocidas),
    do: {:ok, {:formato, formato_desde_dato(formato)}}

  defp valor_campo("patron", %{"patron" => fuente} = patron, _tipo, _conocidas) do
    opciones = Map.get(patron, "opciones", "")

    with true <- is_binary(fuente) and is_binary(opciones),
         {:ok, regex} <- Regex.compile(fuente, opciones) do
      {:ok, {:patron, regex}}
    else
      false ->
        {:error, ~s(un "patron" con la expresión regular y sus "opciones" como texto), nil}

      {:error, {motivo, posicion}} when is_integer(posicion) ->
        {:error, "una expresión regular que compile",
         "#{motivo} en la posición #{posicion} del patrón"}

      {:error, {:invalid_option, opcion}} ->
        {:error, "una expresión regular que compile", "la opción #{inspect(opcion)} no existe"}

      {:error, motivo} ->
        {:error, "una expresión regular que compile", "Regex.compile/2 dijo #{inspect(motivo)}"}
    end
  end

  defp valor_campo("rango", [min, max], tipo, _conocidas) do
    with {:ok, min} <- rango_desde_dato(min, tipo),
         {:ok, max} <- rango_desde_dato(max, tipo) do
      {:ok, {:rango, {min, max}}}
    end
  end

  defp valor_campo(clave, condicion, _tipo, _conocidas)
       when clave in ["requerido_si", "prohibido_si"] and is_map(condicion),
       do: {:ok, {String.to_atom(clave), condicion_desde_dato(condicion)}}

  defp valor_campo("campos", campos, _tipo, _conocidas) when is_list(campos) do
    {convertidos, invalidos} = campos_desde_datos(campos)
    {:ok, {:campos, convertidos}, invalidos}
  end

  # Un valor que no es una lista de campos queda como vino: `Campo.nuevo/1`
  # ya lo reclama.
  defp valor_campo("variantes", variantes, _tipo, _conocidas) when is_map(variantes) do
    if Enum.all?(variantes, fn {_valor, campos} -> is_list(campos) end) do
      {pares, invalidos} =
        Enum.map_reduce(variantes, [], fn {valor, campos}, acumulados ->
          {convertidos, nuevos} = campos_desde_datos(campos)
          {{valor, convertidos}, acumulados ++ nuevos}
        end)

      {:ok, {:variantes, Map.new(pares)}, invalidos}
    else
      {:ok, {:variantes, variantes}}
    end
  end

  defp valor_campo(clave, valor, _tipo, conocidas), do: {:ok, clave_campo(clave, valor, conocidas)}

  defp clave_campo(clave, valor, conocidas) do
    case atomo_conocido(clave, conocidas) do
      nil ->
        {clave, valor}

      atomo when atomo in @atomicas ->
        {atomo, if(is_binary(valor), do: a_atomo(valor), else: valor)}

      atomo ->
        {atomo, valor}
    end
  end

  # Un tipo interno por su nombre; un módulo por el suyo, solo si existe:
  # `String.to_existing_atom/1` no crea átomos desde un JSON ajeno, y un
  # módulo que no está queda como string para que `Campo.nuevo/1` lo reclame.
  defp tipo_desde_dato(nombre) when is_map_key(@tipos_internos, nombre),
    do: Map.fetch!(@tipos_internos, nombre)

  defp tipo_desde_dato(nombre) when is_binary(nombre) do
    String.to_existing_atom("Elixir." <> nombre)
  rescue
    ArgumentError -> nombre
  end

  defp tipo_desde_dato(otro), do: otro

  # Los extremos de un rango vuelven al tipo del campo: enteros, tuplas,
  # fechas y horas ISO, decimales como string. Lo que no se puede leer es un
  # `{:error, esperado, causa}`, nunca una excepción: el mapa lo escribió
  # alguien a mano.
  @rango_decimal ~s|un entero, [unidades, precision], [unidades, precision, "moneda"] o un decimal como texto ("1234.56")|

  defp rango_desde_dato(nil, _tipo), do: {:ok, nil}

  defp rango_desde_dato(valor, :fecha) when is_binary(valor),
    do: iso(Date.from_iso8601(valor), "una fecha ISO 8601 (AAAA-MM-DD)")

  defp rango_desde_dato(_valor, :fecha),
    do: {:error, "una fecha ISO 8601 (AAAA-MM-DD) como texto", nil}

  defp rango_desde_dato(valor, :hora) when is_binary(valor),
    do: iso(Time.from_iso8601(valor), "una hora ISO 8601 (HH:MM:SS)")

  defp rango_desde_dato(_valor, :hora), do: {:error, "una hora ISO 8601 (HH:MM:SS) como texto", nil}

  defp rango_desde_dato(valor, :fecha_hora) when is_binary(valor),
    do: iso(NaiveDateTime.from_iso8601(valor), "una fecha y hora ISO 8601 (AAAA-MM-DDTHH:MM:SS)")

  defp rango_desde_dato(_valor, :fecha_hora),
    do: {:error, "una fecha y hora ISO 8601 (AAAA-MM-DDTHH:MM:SS) como texto", nil}

  defp rango_desde_dato(valor, :entero) when is_integer(valor), do: {:ok, valor}
  defp rango_desde_dato(_valor, :entero), do: {:error, "un entero", nil}

  defp rango_desde_dato(valor, :decimal) when is_integer(valor), do: {:ok, valor}

  defp rango_desde_dato([u, p], :decimal) when is_integer(u) and is_integer(p) and p >= 0,
    do: {:ok, {u, p}}

  defp rango_desde_dato([u, p, moneda], :decimal)
       when is_integer(u) and is_integer(p) and p >= 0 and is_binary(moneda),
       do: {:ok, AnchoFijo.Monto.nuevo(u, p, a_atomo(moneda))}

  defp rango_desde_dato(valor, :decimal) when is_binary(valor), do: decimal_desde_dato(valor)
  defp rango_desde_dato(_valor, :decimal), do: {:error, @rango_decimal, nil}

  # Un tipo propio decide qué es un rango; el extremo viaja como vino.
  defp rango_desde_dato(valor, _tipo), do: {:ok, valor}

  defp iso({:ok, valor}, _esperado), do: {:ok, valor}

  defp iso({:error, motivo}, esperado),
    do: {:error, esperado, "Elixir no la lee: #{inspect(motivo)}"}

  defp decimal_desde_dato(valor) do
    if Tipo.Decimal.decimal_disponible?() do
      case Decimal.parse(valor) do
        {decimal, ""} -> {:ok, decimal}
        _otro -> {:error, @rango_decimal, nil}
      end
    else
      {:error,
       "un extremo decimal como [unidades, precision], o la librería Decimal para leerlo como texto",
       "agregue {:decimal, \"~> 2.0 or ~> 3.0\"} a las dependencias, o escriba el extremo como [unidades, precision]"}
    end
  end

  defp condicion_desde_dato(condicion) do
    [campo: condicion |> Map.get("campo") |> a_atomo()] ++
      if(Map.has_key?(condicion, "en"), do: [en: Map.get(condicion, "en")], else: [])
  end

  defp opciones_propias(modulo) when is_atom(modulo) do
    case Tipo.resolver(modulo) do
      {:ok, modulo} -> modulo.opciones()
      {:error, _} -> []
    end
  end

  defp opciones_propias(_otro), do: []

  # Un nombre de formato conocido vuelve a átomo; un patrón ("DD/MM/AAAA") es
  # un string y queda así.
  defp formato_desde_dato(formato) when is_binary(formato) do
    nombres = Map.new(Patron.nombrados(), fn {atomo, _} -> {Atom.to_string(atomo), atomo} end)
    Map.get(nombres, formato, formato)
  end

  defp formato_desde_dato(otro), do: otro

  defp atomo_conocido(clave, conocidas) when is_binary(clave) do
    Enum.find(conocidas, &(Atom.to_string(&1) == clave))
  end

  defp atomo_conocido(clave, conocidas) when is_atom(clave),
    do: if(clave in conocidas, do: clave, else: nil)

  defp atomo_conocido(_otra, _conocidas), do: nil

  # Los nombres de campo y de tipo de registro son del layout, que es
  # configuración y no datos del archivo: crear el átomo es lo correcto. Lo
  # que no puede ser un átomo (bytes que no son UTF-8, más de 255
  # caracteres) queda como vino, y `nuevo/1` lo reclama.
  defp a_atomo(valor) when is_binary(valor) and byte_size(valor) <= 255 do
    if String.valid?(valor), do: String.to_atom(valor), else: valor
  end

  defp a_atomo(valor), do: valor

  @spec multiregistro_desde_mapa(term()) :: {:ok, Multiregistro.t()} | {:error, [Diagnostico.t()]}
  def multiregistro_desde_mapa(mapa) when is_map(mapa) do
    with :ok <- validar_version(mapa) do
      {pares, invalidos} =
        mapa
        |> Map.delete("version")
        |> Enum.map_reduce([], fn
          {"nombre", nombre}, acumulados ->
            {{:nombre, nombre}, acumulados}

          {"orden", orden}, acumulados ->
            {{:orden, a_atomo(orden)}, acumulados}

          {"discriminador", d}, acumulados ->
            {{:discriminador, discriminador_desde_mapa(d)}, acumulados}

          {"registros", registros}, acumulados when is_list(registros) ->
            {convertidos, nuevos} = registros_desde_datos(registros)
            {{:registros, convertidos}, acumulados ++ nuevos}

          {"controles", controles}, acumulados when is_list(controles) ->
            {{:controles, Enum.map(controles, &control_desde_mapa/1)}, acumulados}

          {clave, valor}, acumulados ->
            {{clave, valor}, acumulados}
        end)

      con_invalidos(Multiregistro.nuevo(Map.new(pares)), invalidos)
    end
  end

  def multiregistro_desde_mapa(otro),
    do: {:error, [falla("un mapa con la definición del multiregistro", otro)]}

  defp registros_desde_datos(registros) do
    Enum.map_reduce(registros, [], fn registro, acumulados ->
      {convertido, invalidos} = registro_desde_mapa(registro)
      {convertido, acumulados ++ invalidos}
    end)
  end

  defp discriminador_desde_mapa(%{"por" => por}) when is_binary(por), do: [por: a_atomo(por)]
  defp discriminador_desde_mapa(%{"campo" => campo}), do: [campo: a_atomo(campo)]
  defp discriminador_desde_mapa(%{"posicion" => p, "largo" => l}), do: [posicion: p, largo: l]
  defp discriminador_desde_mapa(%{"largo" => l}), do: [largo: l]
  defp discriminador_desde_mapa(otro), do: otro

  # El layout de cada tipo se pasa como definición para que `Multiregistro.nuevo/1`
  # lo construya y reporte sus diagnósticos con el tipo como campo; lo que no
  # se pudo convertir sale igual, con el campo o, si no lo hay, el tipo.
  defp registro_desde_mapa(%{"tipo" => tipo} = registro) do
    {layout, invalidos} = registro |> Map.get("layout") |> layout_mapa_a_definicion()

    definicion =
      [
        valor: Map.get(registro, "valor"),
        cantidad: registro |> Map.get("cantidad") |> atomo_en(@cantidades),
        ubicacion: registro |> Map.get("ubicacion") |> atomo_en(@ubicaciones),
        layout: layout
      ]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    {{a_atomo(tipo), definicion},
     Enum.map(invalidos, fn %Diagnostico{} = d ->
       %Diagnostico{d | campo: d.campo || a_atomo(tipo)}
     end)}
  end

  defp registro_desde_mapa(otro), do: {otro, []}

  defp atomo_en(nil, _validos), do: nil

  defp atomo_en(valor, validos) when is_binary(valor) do
    if valor in validos, do: String.to_atom(valor), else: valor
  end

  defp atomo_en(valor, _validos), do: valor

  defp control_desde_mapa(%{"en" => en, "campo" => campo} = control) do
    [en: a_atomo(en), campo: a_atomo(campo)] ++
      case control do
        %{"cuenta" => tipo} -> [cuenta: a_atomo(tipo)]
        %{"suma" => [tipo, sumado]} -> [suma: {a_atomo(tipo), a_atomo(sumado)}]
        _ -> []
      end ++
      if(Map.has_key?(control, "agrupar_por"),
        do: [agrupar_por: a_atomo(control["agrupar_por"])],
        else: []
      )
  end

  defp control_desde_mapa(otro), do: otro

  # Un valor del mapa que no se pudo convertir: el campo, la clave como la
  # escribió quien editó el mapa, y lo recibido.
  defp invalido(nombre, clave, esperado, recibido, causa) do
    Diagnostico.nuevo(
      tipo: :layout,
      campo: nombre,
      esperado: ~s("#{clave}": #{esperado}),
      recibido: inspect(recibido),
      causa_probable: causa
    )
  end

  defp falla(esperado, recibido, causa \\ nil) do
    Diagnostico.nuevo(
      tipo: :layout,
      esperado: esperado,
      recibido: inspect(recibido),
      causa_probable: causa
    )
  end
end
