defmodule AnchoFijo.Documentacion do
  @moduledoc """
  La especificación del formato, generada desde el layout.

  La especificación de un archivo de ancho fijo vive dos veces: en el
  documento que se le manda al cliente o al banco (la tabla de posición,
  largo, tipo y descripción) y en el layout del código. Divergen con el
  tiempo y nadie se entera. Si el layout es la fuente de verdad, la tabla
  tiene que salir de él.

      iex> layout = AnchoFijo.Layout.nuevo!(
      ...>   nombre: "nómina",
      ...>   campos: [
      ...>     [nombre: :rut, largo: 10, tipo: :rut, descripcion: "RUT del beneficiario", ejemplo: "12345678-5"],
      ...>     [nombre: :monto, largo: 10, tipo: :decimal, precision: 2, descripcion: "Monto a pagar, en pesos con dos decimales"]
      ...>   ]
      ...> )
      iex> layout |> AnchoFijo.Documentacion.documentar() |> String.split("\\n")
      [
        "## nómina",
        "",
        "20 posiciones · UTF-8 · medido en bytes",
        "",
        "| Campo | Posiciones | Largo | Tipo | Formato | Opcional | Reglas | Descripción | Ejemplo |",
        "| --- | --- | --- | --- | --- | --- | --- | --- | --- |",
        "| `rut` | 1-10 | 10 | RUT | dígito verificador validado | no |  | RUT del beneficiario | `12345678-5` |",
        "| `monto` | 11-20 | 10 | decimal | 2 decimales implícitos | no |  | Monto a pagar, en pesos con dos decimales |  |",
        ""
      ]

  ## Opciones

    * `:formato` — `:markdown` (default), `:csv` o `:json`.
    * `:idioma` — `:es` (default) o `:en`: traduce los encabezados y los
      nombres de tipo, no los nombres de los campos, que son del formato.

  Con un `AnchoFijo.Multiregistro`, una tabla por tipo de registro más la
  sección de controles. `mix ancho_fijo.documentar` hace lo mismo desde la
  terminal, y `AnchoFijo.Layout.documentar/2` desde el layout.

  Las columnas de descripción y ejemplo salen de las opciones `descripcion:`
  y `ejemplo:` de cada campo, que el parser ignora: existen para esto.
  """

  alias AnchoFijo.Campo
  alias AnchoFijo.Json
  alias AnchoFijo.Layout
  alias AnchoFijo.Multiregistro
  alias AnchoFijo.Opciones

  @formatos [:markdown, :csv, :json]
  @idiomas [:es, :en]

  @doc """
  La especificación como texto, en el formato y el idioma pedidos.
  """
  @spec documentar(Layout.t() | Multiregistro.t() | Enumerable.t(), keyword()) :: String.t()
  def documentar(layout, opts \\ []) do
    opts = Opciones.validar!(opts, opciones(), "AnchoFijo.Documentacion.documentar/2")
    formato = Keyword.get(opts, :formato, :markdown)
    idioma = Keyword.get(opts, :idioma, :es)

    case formato do
      :markdown -> markdown(layout, idioma)
      :csv -> csv(layout, idioma)
      :json -> Json.codificar(a_mapa(layout, idioma))
    end
  end

  defp opciones do
    [
      {:formato, &(&1 in @formatos), inspect(@formatos)},
      {:idioma, &(&1 in @idiomas), inspect(@idiomas)}
    ]
  end

  @doc """
  La especificación como datos: para un layout, `%{nombre, largo, encoding,
  unidad, campos: [...]}` con una fila por campo; para un multiregistro,
  además `registros` (una entrada por tipo) y `controles`.
  """
  @spec a_mapa(Layout.t() | Multiregistro.t() | Enumerable.t(), :es | :en) :: map()
  def a_mapa(layout, idioma \\ :es)

  def a_mapa(%Multiregistro{} = multi, idioma) do
    %{
      nombre: multi.nombre,
      discriminador: describir_discriminador(multi.discriminador, idioma),
      registros:
        Enum.map(multi.registros, fn {tipo, d} ->
          Map.merge(a_mapa(d.layout, idioma), %{
            tipo: tipo,
            valores: d.valores,
            cantidad: cantidad(d.cantidad, idioma),
            ubicacion: d.ubicacion
          })
        end),
      controles: Enum.map(multi.controles, &describir_control(&1, idioma))
    }
  end

  def a_mapa(layout, idioma) do
    layout = Layout.coercer!(layout)

    %{
      nombre: layout.nombre,
      largo: layout.largo,
      encoding: layout.encoding,
      unidad: layout.unidad,
      campos: Enum.flat_map(layout.campos, &filas(&1, idioma))
    }
  end

  # Un grupo o una variante son una fila más las de sus campos internos, con
  # la ruta y las posiciones relativas al campo que los contiene.
  defp filas(%Campo{tipo: :grupo} = campo, idioma) do
    [fila(campo, idioma) | Enum.map(campo.campos, &fila(&1, idioma, "#{campo.nombre}[]."))]
  end

  defp filas(%Campo{tipo: :variante} = campo, idioma) do
    internas =
      campo.variantes
      |> Enum.sort_by(fn {clave, _} -> to_string(clave) end)
      |> Enum.flat_map(fn {clave, campos} ->
        Enum.map(campos, &fila(&1, idioma, "#{campo.nombre}{#{clave}}."))
      end)

    [fila(campo, idioma) | internas]
  end

  defp filas(campo, idioma), do: [fila(campo, idioma)]

  defp fila(%Campo{} = campo, idioma, ruta \\ "") do
    {desde, hasta} = Campo.rango(campo)

    %{
      nombre: if(ruta == "", do: campo.nombre, else: "#{ruta}#{campo.nombre}"),
      relativa: ruta != "",
      desde: desde,
      hasta: hasta,
      largo: campo.largo,
      tipo: nombre_de_tipo(campo, idioma),
      formato: formato_de(campo, idioma),
      opcional: campo.opcional,
      reglas: AnchoFijo.Reglas.describir(campo, idioma),
      descripcion: campo.descripcion,
      ejemplo: campo.ejemplo
    }
  end

  # ------------------------------------------------------------- markdown

  defp markdown(%Multiregistro{} = multi, idioma) do
    titulo = multi.nombre || t(:multiregistro, idioma)

    tablas =
      Enum.map(multi.registros, fn {tipo, d} ->
        subtitulo = "### #{tipo}" <> detalle_de_tipo(d, idioma)
        subtitulo <> "\n\n" <> tabla_markdown(d.layout, idioma)
      end)

    controles =
      case multi.controles do
        [] ->
          []

        controles ->
          [
            "### #{t(:controles, idioma)}\n\n" <>
              Enum.map_join(controles, "\n", &("- " <> describir_control(&1, idioma)))
          ]
      end

    Enum.join(
      ["## #{titulo}\n\n#{describir_discriminador(multi.discriminador, idioma)}"] ++
        tablas ++ controles,
      "\n\n"
    ) <> "\n"
  end

  defp markdown(layout, idioma) do
    layout = Layout.coercer!(layout)
    titulo = layout.nombre || t(:layout, idioma)

    "## #{titulo}\n\n#{resumen_del_layout(layout, idioma)}\n\n" <>
      tabla_markdown(layout, idioma) <> "\n"
  end

  defp detalle_de_tipo(d, idioma) do
    partes =
      [
        if(d.valores != [], do: Enum.map_join(d.valores, "/", &inspect/1)),
        cantidad(d.cantidad, idioma),
        d.ubicacion && t(d.ubicacion, idioma)
      ]
      |> Enum.reject(&is_nil/1)

    " (" <> Enum.join(partes, ", ") <> ")"
  end

  defp resumen_del_layout(%Layout{} = layout, idioma) do
    "#{layout.largo} #{t(:posiciones, idioma)} · #{encoding(layout.encoding)} · " <>
      "#{t(:medido_en, idioma)} #{t(layout.unidad, idioma)}"
  end

  defp tabla_markdown(%Layout{} = layout, idioma) do
    encabezados = Enum.map(columnas(), &t(&1, idioma))

    filas =
      Enum.flat_map(layout.campos, fn campo ->
        Enum.map(filas(campo, idioma), fn f ->
          [
            "`#{f.nombre}`",
            posiciones(f, idioma),
            f.largo,
            f.tipo,
            f.formato || "",
            t(if(f.opcional, do: :si, else: :no), idioma),
            Enum.join(f.reglas, "; "),
            f.descripcion || "",
            if(f.ejemplo, do: "`#{f.ejemplo}`", else: "")
          ]
        end)
      end)

    separador = Enum.map(encabezados, fn _ -> "---" end)

    Enum.map_join([encabezados, separador | filas], "\n", fn celdas ->
      "| " <> Enum.map_join(celdas, " | ", &celda/1) <> " |"
    end)
  end

  defp celda(valor), do: valor |> to_string() |> String.replace("|", "\\|")

  # Las posiciones de un campo interno son relativas al grupo o variante.
  defp posiciones(%{relativa: true} = f, idioma),
    do: "#{f.desde}-#{f.hasta} (#{t(:relativas, idioma)})"

  defp posiciones(f, _idioma), do: "#{f.desde}-#{f.hasta}"

  # ------------------------------------------------------------------ csv

  defp csv(%Multiregistro{} = multi, idioma) do
    encabezados = [t(:registro, idioma) | Enum.map(columnas(), &t(&1, idioma))]

    filas =
      Enum.flat_map(multi.registros, fn {tipo, d} ->
        d.layout.campos
        |> Enum.flat_map(&filas(&1, idioma))
        |> Enum.map(&[tipo | celdas_csv(&1, idioma)])
      end)

    lineas_csv([encabezados | filas])
  end

  defp csv(layout, idioma) do
    layout = Layout.coercer!(layout)
    encabezados = Enum.map(columnas(), &t(&1, idioma))
    filas = layout.campos |> Enum.flat_map(&filas(&1, idioma)) |> Enum.map(&celdas_csv(&1, idioma))
    lineas_csv([encabezados | filas])
  end

  defp celdas_csv(f, idioma) do
    [
      f.nombre,
      posiciones(f, idioma),
      f.largo,
      f.tipo,
      f.formato || "",
      t(if(f.opcional, do: :si, else: :no), idioma),
      Enum.join(f.reglas, "; "),
      f.descripcion || "",
      f.ejemplo || ""
    ]
  end

  defp lineas_csv(filas) do
    Enum.map_join(filas, "\n", fn celdas -> Enum.map_join(celdas, ";", &campo_csv/1) end) <> "\n"
  end

  # Punto y coma como separador, que es lo que Excel en español espera; las
  # comillas se duplican y lo que trae separador, comillas o saltos va entre
  # comillas.
  defp campo_csv(valor) do
    texto = to_string(valor)

    if String.contains?(texto, [";", "\"", "\n", "\r"]),
      do: "\"" <> String.replace(texto, "\"", "\"\"") <> "\"",
      else: texto
  end

  # --------------------------------------------------------- descripciones

  defp columnas,
    do: [
      :campo,
      :posiciones_col,
      :largo,
      :tipo,
      :formato,
      :opcional,
      :reglas,
      :descripcion,
      :ejemplo
    ]

  # Los nombres de tipo traducibles; `decimal` y `RUT` son iguales en los dos
  # idiomas y un módulo propio se muestra por su nombre.
  @tipos_traducibles [
    :texto,
    :entero,
    :fecha,
    :hora,
    :fecha_hora,
    :constante,
    :relleno,
    :grupo,
    :variante
  ]

  defp nombre_de_tipo(%Campo{tipo: tipo}, idioma) when tipo in @tipos_traducibles,
    do: t(tipo, idioma)

  defp nombre_de_tipo(%Campo{tipo: :decimal}, _idioma), do: "decimal"
  defp nombre_de_tipo(%Campo{tipo: :rut}, _idioma), do: "RUT"
  defp nombre_de_tipo(%Campo{tipo: modulo}, _idioma), do: inspect(modulo)

  # Lo que define al campo además del tipo: el formato de una fecha, la
  # precisión o la moneda de un decimal, el literal de una constante, el
  # carácter de un relleno, la validación de un RUT, el encoding propio.
  defp formato_de(%Campo{} = campo, idioma) do
    (rasgos_numericos(campo, idioma) ++ rasgos_del_tipo(campo, idioma))
    |> Enum.filter(&is_binary/1)
    |> case do
      [] -> nil
      partes -> Enum.join(partes, ", ")
    end
  end

  defp rasgos_numericos(%Campo{} = campo, idioma) do
    [
      campo.formato && formato_texto(campo.formato),
      campo.moneda &&
        "#{Campo.nombre_moneda(campo.moneda)} (#{campo.precision} #{t(:decimales, idioma)})",
      is_nil(campo.moneda) && campo.precision &&
        "#{campo.precision} #{t(:decimales_implicitos, idioma)}",
      campo.separador != :implicito && "#{t(:separador, idioma)} #{t(campo.separador, idioma)}",
      campo.signo == :final && t(:signo_final, idioma),
      campo.pivote && "#{t(:pivote, idioma)} #{campo.pivote}"
    ]
  end

  defp rasgos_del_tipo(%Campo{} = campo, idioma) do
    [
      campo.valor && "#{t(:literal, idioma)} #{inspect(campo.valor)}",
      campo.tipo == :relleno && "#{t(:relleno_de, idioma)} #{inspect(campo.relleno)}",
      campo.tipo == :rut && t(dv(campo.dv), idioma),
      campo.encoding && encoding(campo.encoding),
      campo.tipo == :grupo && "#{campo.repetir} #{t(:repeticiones, idioma)}",
      campo.tipo == :variante && "#{t(:segun, idioma)} `#{campo.segun}`"
    ]
  end

  defp dv(:validar), do: :dv_validar
  defp dv(:no_validar), do: :dv_no_validar
  defp dv(:ausente), do: :dv_ausente

  defp formato_texto(formato) when is_atom(formato),
    do: formato |> Atom.to_string() |> String.upcase()

  defp formato_texto(formato) when is_binary(formato), do: formato

  defp encoding(:utf8), do: "UTF-8"
  defp encoding(:latin1), do: "latin-1"
  defp encoding(:cp1252), do: "Windows-1252"

  defp describir_discriminador(%{campo: campo, posicion: p, largo: l}, idioma),
    do:
      "#{t(:discriminador_campo, idioma)} `#{campo}` (#{t(:posiciones, idioma)} #{p}-#{p + l - 1})"

  defp describir_discriminador(%{posicion: p, largo: l}, idioma),
    do: "#{t(:discriminador_posicion, idioma)} #{p}-#{p + l - 1}"

  defp describir_discriminador(%{por: :largo}, idioma), do: t(:discriminador_largo, idioma)

  defp describir_discriminador(%{por: :posicion_en_archivo}, idioma),
    do: t(:discriminador_archivo, idioma)

  defp describir_discriminador(%{por: :funcion}, idioma), do: t(:discriminador_funcion, idioma)

  defp describir_control(%{cuenta: tipo} = control, idioma) do
    "`#{control.en}.#{control.campo}` = #{t(:cantidad_de, idioma)} `#{tipo}`" <>
      grupo(control, idioma)
  end

  defp describir_control(%{suma: {tipo, campo}} = control, idioma) do
    "`#{control.en}.#{control.campo}` = #{t(:suma_de, idioma)} `#{tipo}.#{campo}`" <>
      grupo(control, idioma)
  end

  defp grupo(%{agrupar_por: campo}, idioma), do: " #{t(:por_cada, idioma)} `#{campo}`"
  defp grupo(_control, _idioma), do: ""

  defp cantidad(:uno, idioma), do: t(:exactamente_uno, idioma)
  defp cantidad(:opcional, idioma), do: t(:cero_o_uno, idioma)
  defp cantidad(:varios, idioma), do: t(:cero_o_mas, idioma)
  defp cantidad(:al_menos_uno, idioma), do: t(:al_menos_uno, idioma)

  @textos %{
    campo: {"Campo", "Field"},
    posiciones_col: {"Posiciones", "Positions"},
    largo: {"Largo", "Length"},
    tipo: {"Tipo", "Type"},
    formato: {"Formato", "Format"},
    opcional: {"Opcional", "Optional"},
    reglas: {"Reglas", "Rules"},
    descripcion: {"Descripción", "Description"},
    ejemplo: {"Ejemplo", "Example"},
    registro: {"Registro", "Record"},
    si: {"sí", "yes"},
    no: {"no", "no"},
    texto: {"texto", "text"},
    entero: {"entero", "integer"},
    fecha: {"fecha", "date"},
    hora: {"hora", "time"},
    fecha_hora: {"fecha y hora", "datetime"},
    constante: {"constante", "constant"},
    relleno: {"relleno", "filler"},
    decimales: {"decimales", "decimals"},
    decimales_implicitos: {"decimales implícitos", "implicit decimals"},
    separador: {"separador", "separator"},
    punto: {"punto", "dot"},
    coma: {"coma", "comma"},
    signo_final: {"signo al final", "trailing sign"},
    literal: {"literal", "literal"},
    relleno_de: {"relleno de", "padded with"},
    grupo: {"grupo", "group"},
    variante: {"variante", "variant"},
    repeticiones: {"repeticiones", "repetitions"},
    segun: {"según", "by"},
    relativas: {"relativas", "relative"},
    dv_validar: {"dígito verificador validado", "check digit validated"},
    dv_no_validar: {"dígito verificador sin validar", "check digit not validated"},
    dv_ausente: {"sin dígito verificador", "without check digit"},
    pivote: {"pivote", "pivot"},
    posiciones: {"posiciones", "positions"},
    medido_en: {"medido en", "measured in"},
    bytes: {"bytes", "bytes"},
    caracteres: {"caracteres", "characters"},
    layout: {"Layout", "Layout"},
    multiregistro: {"Multiregistro", "Multi-record file"},
    controles: {"Controles", "Controls"},
    cantidad_de: {"cantidad de", "count of"},
    suma_de: {"suma de", "sum of"},
    por_cada: {"por cada", "per"},
    exactamente_uno: {"exactamente uno", "exactly one"},
    cero_o_uno: {"cero o uno", "zero or one"},
    cero_o_mas: {"cero o más", "zero or more"},
    al_menos_uno: {"al menos uno", "at least one"},
    primera: {"primera línea", "first line"},
    ultima: {"última línea", "last line"},
    resto: {"las demás líneas", "the other lines"},
    discriminador_campo: {"Tipo de registro por el campo", "Record type by field"},
    discriminador_posicion:
      {"Tipo de registro por el código en las posiciones", "Record type by the code at positions"},
    discriminador_largo:
      {"Tipo de registro por el largo de la línea", "Record type by line length"},
    discriminador_archivo:
      {"Tipo de registro por la posición en el archivo", "Record type by position in the file"},
    discriminador_funcion:
      {"Tipo de registro decidido por una función", "Record type decided by a function"}
  }

  defp t(clave, idioma) do
    {es, en} = Map.fetch!(@textos, clave)
    if idioma == :en, do: en, else: es
  end
end
