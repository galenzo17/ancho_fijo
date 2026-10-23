defmodule AnchoFijo.Test.Generadores do
  @moduledoc """
  Generadores de `StreamData` para probar un layout por propiedades: un
  registro válido para cualquier layout, a partir del tipo y las opciones
  de cada campo, y una línea inválida con el campo roto anotado.

      use ExUnitProperties
      import AnchoFijo.Test
      alias AnchoFijo.Test.Generadores

      property "escribir y leer da lo mismo" do
        check all registro <- Generadores.registro(@layout) do
          assert_round_trip(@layout, registro)
        end
      end

      property "una línea rota se diagnostica en el campo roto" do
        check all %{linea: linea, campo: campo} <- Generadores.linea_invalida(@layout) do
          @layout |> AnchoFijo.parsear(linea) |> assert_diagnostico(campo: campo)
        end
      end

  Hace falta `{:stream_data, "~> 1.1", only: :test}` en el proyecto: sin
  esa librería este módulo no define nada, y la decisión se toma al
  compilar, como con `:telemetry`. Un tipo propio participa implementando
  el callback opcional `c:AnchoFijo.Tipo.generador/1`; sin él, el
  generador levanta `ArgumentError` con el nombre del campo.

  Lo que se genera respeta el campo: el largo, el signo, la precisión o la
  moneda, el formato de fecha (y la ventana del pivote para años de dos
  dígitos), el dígito verificador del RUT, `opcional: true` (a veces `nil`),
  el literal de una constante. Los rellenos no van al registro. En un
  multiregistro, `registro/1` genera la lista de `{tipo, mapa}` con la
  estructura que la definición exige, y los controles los calcula
  `escribir/3`.
  """

  @compile {:no_warn_undefined, [StreamData, AnchoFijo.Test.Generadores.Impl]}

  @doc "Si `StreamData` estaba disponible al compilar la librería."
  @spec disponible?() :: boolean()
  def disponible?, do: Code.ensure_loaded?(StreamData)

  @doc """
  Un registro válido para el layout: un mapa con un valor por campo que
  `AnchoFijo.escribir/3` escribe y `parsear/3` vuelve a leer igual. Con un
  multiregistro, la lista de `{tipo, mapa}` en el orden del archivo.
  """
  @spec registro(AnchoFijo.Layout.t() | AnchoFijo.Multiregistro.t() | Enumerable.t()) :: term()
  def registro(layout), do: impl().registro(layout)

  @doc "Una línea válida para el layout, sin terminador: el registro escrito."
  @spec linea(AnchoFijo.Layout.t() | Enumerable.t()) :: term()
  def linea(layout), do: impl().linea(layout)

  @doc """
  Una línea con exactamente un campo roto (un número, una fecha, una hora,
  un RUT o una constante con letras donde no van), como
  `%{linea: binario, campo: nombre, registro: el_registro_sano}`: lo que
  hace falta para probar que el diagnóstico apunta al campo. Levanta
  `ArgumentError` si el layout no tiene ningún campo que se pueda romper.
  """
  @spec linea_invalida(AnchoFijo.Layout.t() | Enumerable.t()) :: term()
  def linea_invalida(layout), do: impl().linea_invalida(layout)

  defp impl do
    if disponible?() do
      AnchoFijo.Test.Generadores.Impl
    else
      raise ArgumentError,
            "AnchoFijo.Test.Generadores necesita StreamData: agregue {:stream_data, \"~> 1.1\", only: :test} " <>
              "al proyecto y recompile la librería (mix deps.compile ancho_fijo --force)"
    end
  end
end

# La implementación existe solo con StreamData: un `defmodule` dentro del `if`
# no se expande cuando la condición es falsa, así que ni el import ni los
# alias dejan rastro en un proyecto sin la librería.
if Code.ensure_loaded?(StreamData) do
  defmodule AnchoFijo.Test.Generadores.Impl do
    @moduledoc false

    import StreamData

    alias AnchoFijo.Campo
    alias AnchoFijo.Escritor
    alias AnchoFijo.Layout
    alias AnchoFijo.Monto
    alias AnchoFijo.Multiregistro
    alias AnchoFijo.Parser
    alias AnchoFijo.Rut
    alias AnchoFijo.Tipo.Patron

    @letras [?a..?z, ?A..?Z]

    def registro(%Multiregistro{} = multi), do: registros_de(multi)

    def registro(layout) do
      layout = Layout.coercer!(layout)
      registro_de_campos(layout.campos, layout)
    end

    # Las variantes se generan después, con el valor del campo que las elige
    # ya decidido; y ese campo solo toma valores que tengan variante.
    defp registro_de_campos(campos, layout) do
      variantes = Enum.filter(campos, &(&1.tipo == :variante))
      forzados = Map.new(variantes, fn v -> {v.segun, Map.keys(v.variantes)} end)

      base =
        campos
        |> Enum.reject(&(Campo.relleno?(&1) or &1.tipo == :variante))
        |> Enum.map(fn campo ->
          case Map.fetch(forzados, campo.nombre) do
            {:ok, claves} -> {campo.nombre, member_of(claves)}
            :error -> {campo.nombre, valor(campo, layout)}
          end
        end)
        |> fixed_map()

      bind(base, fn mapa ->
        variantes
        |> Enum.map(fn v ->
          campos_de_variante = Map.fetch!(v.variantes, Map.fetch!(mapa, v.segun))
          {v.nombre, registro_de_campos(campos_de_variante, layout)}
        end)
        |> fixed_map()
        |> map(&Map.merge(mapa, &1))
      end)
    end

    def linea(layout) do
      layout = Layout.coercer!(layout)

      map(registro(layout), fn registro ->
        {:ok, linea, _} = Escritor.escribir_linea(layout, registro, 1)
        linea
      end)
    end

    def linea_invalida(layout) do
      layout = Layout.coercer!(layout)
      rompibles = Enum.filter(layout.campos, &rompible?/1)

      if rompibles == [] do
        raise ArgumentError,
              "el layout no tiene campos numéricos, de fecha, de hora, RUT ni constantes que romper"
      end

      bind(registro(layout), fn registro ->
        {:ok, linea, _} = Escritor.escribir_linea(layout, registro, 1)

        map(member_of(rompibles), fn campo ->
          %{linea: romper(linea, campo, layout), campo: campo.nombre, registro: registro}
        end)
      end)
    end

    defp rompible?(campo),
      do: campo.tipo in [:entero, :decimal, :fecha, :hora, :fecha_hora, :rut, :constante]

    # Letras donde el campo espera dígitos (o el literal): el largo se
    # conserva para que el único diagnóstico sea el del campo.
    defp romper(linea, campo, %Layout{unidad: :caracteres}) do
      {desde, _} = Campo.rango(campo)

      String.slice(linea, 0, desde - 1) <>
        String.duplicate("X", campo.largo) <>
        String.slice(linea, desde - 1 + campo.largo, String.length(linea))
    end

    defp romper(linea, campo, _layout) do
      desde = campo.posicion - 1

      binary_part(linea, 0, desde) <>
        String.duplicate("X", campo.largo) <>
        binary_part(linea, desde + campo.largo, byte_size(linea) - desde - campo.largo)
    end

    # ---------------------------------------------------------- por campo

    # Un opcional es nil a veces; el resto de las veces, un valor del tipo.
    defp valor(%Campo{opcional: true} = campo, layout),
      do: one_of([constant(nil), por_tipo(campo, layout)])

    defp valor(%Campo{} = campo, layout), do: por_tipo(campo, layout)

    defp por_tipo(%Campo{tipo: :texto} = campo, layout), do: texto(campo, layout)
    defp por_tipo(%Campo{tipo: :entero} = campo, _layout), do: entero(campo)
    defp por_tipo(%Campo{tipo: :decimal} = campo, _layout), do: decimal(campo)
    defp por_tipo(%Campo{tipo: :fecha} = campo, _layout), do: fecha(campo)
    defp por_tipo(%Campo{tipo: :hora} = campo, _layout), do: hora(campo)
    defp por_tipo(%Campo{tipo: :fecha_hora} = campo, _layout), do: fecha_hora(campo)
    defp por_tipo(%Campo{tipo: :rut} = campo, _layout), do: rut(campo)

    defp por_tipo(%Campo{tipo: :constante, valor: literal}, _layout),
      do: constant(literal)

    defp por_tipo(%Campo{tipo: :grupo} = campo, layout),
      do: fixed_list(List.duplicate(registro_de_campos(campo.campos, layout), campo.repetir))

    defp por_tipo(%Campo{modulo: modulo} = campo, _layout) do
      if function_exported?(modulo, :generador, 1) do
        modulo.generador(campo)
      else
        raise ArgumentError,
              "el campo #{inspect(campo.nombre)} es de tipo #{inspect(modulo)}, que no implementa " <>
                "generador/1; impleméntelo para generar registros con ese layout"
      end
    end

    # Letras y nada más: sin dígitos que un relleno "0" recorte, sin espacios
    # que el trim coma. Con trim: false el texto mide exacto; un opcional
    # nunca es "", que se leería como nil.
    defp texto(%Campo{trim: false, largo: largo}, _layout),
      do: string(@letras, length: largo)

    defp texto(%Campo{largo: largo} = campo, _layout) do
      minimo = if campo.opcional, do: 1, else: 0
      string(@letras, min_length: minimo, max_length: largo)
    end

    defp entero(%Campo{largo: largo}), do: integer(rango(largo))

    # Con un solo dígito no hay lugar para el signo.
    defp rango(1), do: 0..9
    defp rango(digitos), do: -(Integer.pow(10, digitos - 1) - 1)..(Integer.pow(10, digitos) - 1)

    defp decimal(%Campo{largo: largo, separador: separador} = campo) do
      digitos = if separador == :implicito, do: largo, else: max(largo - 1, 1)
      map(integer(rango(digitos)), &valor_decimal(&1, campo))
    end

    # La forma que el campo lee: Decimal, Monto o la tupla.
    defp valor_decimal(unidades, %Campo{como: :decimal, precision: precision}),
      do: Decimal.new(if(unidades < 0, do: -1, else: 1), abs(unidades), -precision)

    defp valor_decimal(unidades, %Campo{moneda: moneda, precision: precision})
         when not is_nil(moneda),
         do: Monto.nuevo(unidades, precision, moneda)

    defp valor_decimal(unidades, %Campo{precision: precision}), do: {unidades, precision}

    defp fecha(%Campo{} = campo) do
      {:ok, patron} = Patron.compilar(campo.formato)

      map(integer(0..36_524), fn dias ->
        Date.add(desde(patron, campo.pivote), dias)
      end)
    end

    # Con año de dos dígitos, la fecha tiene que caer en la ventana del pivote.
    defp desde(%{partes: partes}, pivote) do
      if :anio2 in partes,
        do: Date.new!(pivote || Patron.pivote_default(), 1, 1),
        else: ~D[1950-01-01]
    end

    defp hora(%Campo{} = campo) do
      {:ok, patron} = Patron.compilar(campo.formato)
      con_segundos? = :segundo in patron.partes

      map(integer(0..86_399), fn segundos ->
        hora = Time.add(~T[00:00:00], segundos, :second)
        if con_segundos?, do: hora, else: %{hora | second: 0}
      end)
    end

    defp fecha_hora(%Campo{} = campo) do
      {:ok, patron} = Patron.compilar(campo.formato)
      con_segundos? = :segundo in patron.partes

      map(
        tuple({integer(0..36_524), integer(0..86_399)}),
        fn {dias, segundos} ->
          fecha = Date.add(desde(patron, campo.pivote), dias)
          hora = Time.add(~T[00:00:00], segundos, :second)
          hora = if con_segundos?, do: hora, else: %{hora | second: 0}
          NaiveDateTime.new!(fecha, hora)
        end
      )
    end

    # El cuerpo cabe en el campo: con guion y dígito verificador si hay
    # lugar, sin guion si no, y solo el cuerpo con dv: :ausente.
    defp rut(%Campo{dv: :ausente, largo: largo}) do
      map(
        integer(1..(Integer.pow(10, min(largo, 8)) - 1)),
        &Integer.to_string/1
      )
    end

    defp rut(%Campo{largo: largo}) do
      map(integer(1..(Integer.pow(10, min(largo - 1, 8)) - 1)), fn cuerpo ->
        Integer.to_string(cuerpo) <> "-" <> Rut.digito_verificador(cuerpo)
      end)
    end

    # ------------------------------------------------------ multiregistro

    # Un registro por tipo según su cantidad, en el orden de la definición;
    # sin los campos de control (los calcula escribir/3) ni los que cubre el
    # discriminador: la línea se escribe, se le pone el código de tipo y se
    # vuelve a leer, así el registro generado es exactamente lo que el
    # archivo diría.
    defp registros_de(%Multiregistro{} = multi) do
      multi.registros
      |> Enum.map(fn {tipo, d} ->
        list_of(registro_de_tipo(multi, tipo, d), cantidad(d.cantidad))
      end)
      |> fixed_list()
      |> map(&List.flatten/1)
    end

    defp cantidad(:uno), do: [length: 1]
    defp cantidad(:opcional), do: [max_length: 1]
    defp cantidad(:al_menos_uno), do: [min_length: 1, max_length: 4]
    defp cantidad(:varios), do: [max_length: 4]

    defp registro_de_tipo(%Multiregistro{} = multi, tipo, %{layout: layout} = definicion) do
      controles = multi.controles |> Enum.filter(&(&1.en == tipo)) |> Enum.map(& &1.campo)

      layout
      |> registro()
      |> map(fn mapa -> releer(multi, layout, definicion, mapa) end)
      |> filter(&(not is_nil(&1)))
      |> map(fn mapa -> {tipo, Map.drop(mapa, controles)} end)
    end

    defp releer(%Multiregistro{discriminador: discriminador}, layout, definicion, mapa) do
      with {:ok, linea, _} <- Escritor.escribir_linea(layout, mapa, 1),
           linea = con_codigo(linea, discriminador, definicion),
           {:ok, releido, _} <- Parser.parsear_linea(layout, linea, 1) do
        releido
      else
        _ -> nil
      end
    end

    defp con_codigo(linea, %{posicion: posicion, largo: largo}, %{valores: [valor | _]}) do
      desde = posicion - 1

      binary_part(linea, 0, desde) <>
        valor <> binary_part(linea, desde + largo, byte_size(linea) - desde - largo)
    end

    defp con_codigo(linea, _discriminador, _definicion), do: linea
  end
end
