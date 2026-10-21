defmodule AnchoFijo.Diagnostico do
  @moduledoc """
  Un error que se puede leer, pegar en un correo y mandarle al banco.

  Esta librería no devuelve `{:error, :invalid}`. Cada falla es un
  `%AnchoFijo.Diagnostico{}` que responde cuatro preguntas: **dónde** pasó
  (línea, campo, posiciones), **qué se esperaba**, **qué llegó** y **cuál es la
  causa probable**.

      iex> alias AnchoFijo.Diagnostico
      iex> d = Diagnostico.nuevo(
      ...>   tipo: :largo_de_linea,
      ...>   linea: 42,
      ...>   esperado: "120 caracteres",
      ...>   recibido: "118",
      ...>   causa_probable: "posible campo faltante o archivo delimitado"
      ...> )
      iex> Diagnostico.mensaje(d)
      "línea 42: se esperaban 120 caracteres, llegaron 118; posible campo faltante o archivo delimitado"

  La causa probable es una hipótesis, no un veredicto. Existe porque en una
  integración bancaria el ciclo de feedback es de días: quien lee el error a las
  3 AM necesita una pista de dónde mirar, no solo la constatación de que algo
  falló.

  ## Para el usuario final y para una API

  El mensaje de arriba es para quien integra. Una pantalla de carga de
  archivos necesita otra cosa: decirle al usuario "línea 42: el monto no es
  válido" en su idioma, sin opciones ni nombres de módulos, y una API
  necesita el diagnóstico como JSON. Para eso:

    * `mensaje/2` con `audiencia: :usuario` omite la causa probable (que
      habla de opciones del layout) y la sintaxis de átomos, y con
      `idioma: :en` redacta el marco en inglés. Lo que los tipos describen
      en `:esperado` y `:recibido` ("8 dígitos con 2 decimales implícitos")
      se muestra tal cual: es prosa que la librería produce en español.
    * `a_mapa/2` y `desde_mapa/1`: el diagnóstico como mapa de claves
      estables, con el mensaje incluido, y la vuelta. Con `Jason` en el
      proyecto, un diagnóstico se codifica a JSON directo (`Jason.Encoder`
      opcional, con la misma estrategia que `Decimal`).
    * `resumen/2`: totales por gravedad, por tipo y por campo, las primeras
      líneas afectadas y el veredicto (`:aceptable`,
      `:aceptable_con_observaciones` o `:rechazable`), con un texto en el
      idioma pedido. Es lo que una pantalla de carga muestra arriba de la
      tabla.

  Todas respetan `:sensible`: el valor redactado no sale en ninguna, salvo
  con `revelar: true`.

  ## Datos personales

  El mismo mensaje que se pega en un correo termina en un `Logger.error`, en
  Sentry y en un ticket. Si el campo que falló es un RUT o un nombre, ese es el
  camino por el que los datos de miles de beneficiarios salen del sistema sin
  que nadie lo haya decidido. Por eso un diagnóstico de un campo declarado
  `sensible: true` (y `:rut` lo es por default) tiene dos representaciones:

    * `mensaje/1`, `reporte/1`, `to_string/1` e `inspect/1` muestran la
      **forma** del valor, no el valor: `<10 caracteres: 4 dígitos, 1 letra,
      3 dígitos, "-", 1 dígito>`. Es lo que hace falta para entender qué falló
      (hay una letra donde debía haber un dígito) sin que viaje la identidad.
    * `mensaje(diagnostico, revelar: true)` y `reporte(lista, revelar: true)`
      muestran el valor completo, para uso local e interactivo.

  El valor completo sigue en `:recibido` del struct: la redacción es de las
  representaciones, no del dato, y quien lo necesita lo lee a propósito.
  """

  @typedoc """
  Familia del problema, para poder filtrar o agrupar sin parsear el mensaje.

  * `:layout` — la definición del formato es inconsistente consigo misma.
  * `:entrada` — no se pudo leer el archivo o el argumento no es un binario.
  * `:largo_de_linea` — la línea no mide lo que el layout declara.
  * `:encoding` — hay bytes que no corresponden al encoding declarado.
  * `:campo_invalido` — el contenido del campo no calza con su tipo.
  * `:relleno_completado` — la línea llegó corta y el layout autorizó completar
    el relleno faltante. Siempre de gravedad `:advertencia`.
  * `:moneda` — una operación entre montos incompatibles. Ver `AnchoFijo.Monto`.
  * `:campo_truncado` — al escribir, un `:texto` no cabía y se pidió
    `truncar: true`. Siempre de gravedad `:advertencia`.
  * `:doble_codificacion` — un `:texto` trae UTF-8 decodificado como latin-1
    y vuelto a codificar (`operaciÃ³n`); el diagnóstico trae el texto
    reparado y dice si se aplicó. Siempre de gravedad `:advertencia`.
  * `:estructura` — en un `AnchoFijo.Multiregistro`: un discriminador
    desconocido, un registro fuera de orden, repetido o faltante.
  * `:control` — en un `AnchoFijo.Multiregistro`: un total del trailer que
    no cuadra con los detalles.
  * `:identidad` — la misma identidad declarada con otro contenido, o un
    archivo sin primer registro que identificar. Ver `AnchoFijo.Identidad`.
  """
  @type tipo ::
          :layout
          | :entrada
          | :largo_de_linea
          | :encoding
          | :campo_invalido
          | :relleno_completado
          | :moneda
          | :campo_truncado
          | :doble_codificacion
          | :estructura
          | :control
          | :identidad

  @typedoc """
  Si el problema impide leer el dato o solo merece quedar anotado.

  * `:error` — el dato no se pudo leer, o se leyó algo que no corresponde.
  * `:advertencia` — se leyó un valor confiable, pero hubo que asumir algo para
    llegar a él, y quien procesa el archivo debería saberlo.

  La distinción es de dominio, no de severidad abstracta: una advertencia dice
  "esto se resolvió con un supuesto". Si el supuesto era falso, el dato ya está
  mal y nadie se enteró. Por eso una advertencia se reporta siempre, también en
  modo `:estricto`, en vez de descartarse por no ser un error.
  """
  @type gravedad :: :error | :advertencia

  @typedoc """
  `:sensible` marca que `:recibido` y `:contenido` traen datos personales y
  que las representaciones de texto deben mostrar `:redactado` en su lugar.
  """
  @type t :: %__MODULE__{
          tipo: tipo(),
          gravedad: gravedad(),
          linea: pos_integer() | nil,
          campo: atom() | nil,
          posicion: {pos_integer(), pos_integer()} | nil,
          esperado: String.t() | nil,
          recibido: String.t() | nil,
          causa_probable: String.t() | nil,
          contenido: String.t() | nil,
          sensible: boolean(),
          redactado: String.t() | nil
        }

  defstruct tipo: :campo_invalido,
            gravedad: :error,
            linea: nil,
            campo: nil,
            posicion: nil,
            esperado: nil,
            recibido: nil,
            causa_probable: nil,
            contenido: nil,
            sensible: false,
            redactado: nil

  @doc """
  Construye un diagnóstico desde una keyword list o mapa de atributos.

  Los valores de `:esperado` y `:recibido` se normalizan a texto: lo que no sea
  binario pasa por `inspect/1`, para que un diagnóstico nunca falle al armarse.

      iex> AnchoFijo.Diagnostico.nuevo(tipo: :campo_invalido, campo: :monto, esperado: 12, recibido: nil)
      %AnchoFijo.Diagnostico{tipo: :campo_invalido, campo: :monto, esperado: "12", recibido: nil}
  """
  @spec nuevo(Enumerable.t()) :: t()
  def nuevo(atributos) do
    atributos = Map.new(atributos)

    %__MODULE__{
      tipo: Map.get(atributos, :tipo, :campo_invalido),
      gravedad: Map.get(atributos, :gravedad, :error),
      linea: Map.get(atributos, :linea),
      campo: Map.get(atributos, :campo),
      posicion: Map.get(atributos, :posicion),
      esperado: texto(Map.get(atributos, :esperado)),
      recibido: texto(Map.get(atributos, :recibido)),
      causa_probable: texto(Map.get(atributos, :causa_probable)),
      contenido: texto(Map.get(atributos, :contenido)),
      sensible: Map.get(atributos, :sensible, false),
      redactado: texto(Map.get(atributos, :redactado))
    }
  end

  @doc """
  Marca el diagnóstico como sensible y guarda la forma del valor para las
  representaciones redactadas.

  `valor` es el texto que se recibió en el campo. Cuando el diagnóstico no es
  sobre un valor —una línea corta, un byte inválido— se pasa `nil` y lo que
  se muestra redactado es el mismo `:recibido`, que no trae el dato; el
  `:contenido` sí queda oculto en `inspect/1`.

      iex> alias AnchoFijo.Diagnostico
      iex> d = Diagnostico.nuevo(campo: :rut, esperado: "un RUT", recibido: ~s("1234A678-5"))
      iex> Diagnostico.mensaje(Diagnostico.marcar_sensible(d, "1234A678-5"))
      "campo :rut: se esperaban un RUT, llegaron <10 caracteres: 4 dígitos, 1 letra, 3 dígitos, \\"-\\", 1 dígito>"
  """
  @spec marcar_sensible(t(), String.t() | nil) :: t()
  def marcar_sensible(%__MODULE__{} = diagnostico, valor) when is_binary(valor) and valor != "" do
    %__MODULE__{diagnostico | sensible: true, redactado: forma(valor)}
  end

  def marcar_sensible(%__MODULE__{} = diagnostico, _sin_valor) do
    %__MODULE__{diagnostico | sensible: true, redactado: diagnostico.recibido}
  end

  @doc """
  Describe la forma de un valor sin revelarlo: cuántos caracteres y de qué
  clase, en el orden en que aparecen.

  Es la política de redacción de la librería. Una máscara parcial
  (`1234****-*`) deja ver lo suficiente para reidentificar y oculta justo lo
  que hace falta para depurar; la supresión total no dice nada. La forma dice
  dónde hay una letra en vez de un dígito sin decir cuál.

      iex> AnchoFijo.Diagnostico.forma("1234A678-5")
      "<10 caracteres: 4 dígitos, 1 letra, 3 dígitos, \\"-\\", 1 dígito>"

      iex> AnchoFijo.Diagnostico.forma("JOSÉ MUÑOZ")
      "<10 caracteres: 4 letras, 1 espacio, 5 letras>"

      iex> AnchoFijo.Diagnostico.forma("")
      "<vacío>"

  Un binario que no es UTF-8 válido se describe por bytes:

      iex> AnchoFijo.Diagnostico.forma(<<74, 79, 83, 201>>)
      "<4 bytes: 3 letras, 1 byte no ASCII>"
  """
  @spec forma(binary()) :: String.t()
  def forma(""), do: "<vacío>"

  def forma(valor) when is_binary(valor) do
    if String.valid?(valor) do
      piezas = valor |> String.graphemes() |> Enum.map(&clase/1)
      "<#{String.length(valor)} caracteres: #{describir_clases(piezas)}>"
    else
      piezas = valor |> :binary.bin_to_list() |> Enum.map(&clase_de_byte/1)
      "<#{byte_size(valor)} bytes: #{describir_clases(piezas)}>"
    end
  end

  defp clase(grafema) do
    cond do
      grafema =~ ~r/^\d$/u -> :digito
      grafema =~ ~r/^\p{L}$/u -> :letra
      grafema =~ ~r/^\s$/u -> :espacio
      grafema =~ ~r/^[\p{P}\p{S}]$/u -> {:literal, grafema}
      true -> :control
    end
  end

  defp clase_de_byte(byte) when byte in ?0..?9, do: :digito
  defp clase_de_byte(byte) when byte in ?a..?z or byte in ?A..?Z, do: :letra
  defp clase_de_byte(byte) when byte in [?\s, ?\t], do: :espacio
  defp clase_de_byte(byte) when byte in 33..126, do: {:literal, <<byte>>}
  defp clase_de_byte(byte) when byte < 128, do: :control
  defp clase_de_byte(_byte), do: :byte_no_ascii

  defp describir_clases(piezas) do
    piezas
    |> Enum.chunk_by(& &1)
    |> Enum.map_join(", ", fn [clase | _] = grupo -> describir_grupo(clase, length(grupo)) end)
  end

  defp describir_grupo({:literal, caracter}, 1), do: inspect(caracter)
  defp describir_grupo({:literal, caracter}, n), do: "#{n} × #{inspect(caracter)}"
  defp describir_grupo(clase, n), do: "#{n} #{nombre_de_clase(clase, n)}"

  defp nombre_de_clase(:digito, 1), do: "dígito"
  defp nombre_de_clase(:digito, _n), do: "dígitos"
  defp nombre_de_clase(:letra, 1), do: "letra"
  defp nombre_de_clase(:letra, _n), do: "letras"
  defp nombre_de_clase(:espacio, 1), do: "espacio"
  defp nombre_de_clase(:espacio, _n), do: "espacios"
  defp nombre_de_clase(:control, 1), do: "carácter de control"
  defp nombre_de_clase(:control, _n), do: "caracteres de control"
  defp nombre_de_clase(:byte_no_ascii, 1), do: "byte no ASCII"
  defp nombre_de_clase(:byte_no_ascii, _n), do: "bytes no ASCII"

  @doc """
  Redacta el diagnóstico como una sola línea de texto en español.

      iex> alias AnchoFijo.Diagnostico
      iex> d = Diagnostico.nuevo(
      ...>   tipo: :campo_invalido,
      ...>   linea: 7,
      ...>   campo: :monto,
      ...>   posicion: {21, 32},
      ...>   esperado: "12 dígitos",
      ...>   recibido: "\\"0001234A567\\"",
      ...>   causa_probable: "hay un carácter no numérico en el monto"
      ...> )
      iex> Diagnostico.mensaje(d)
      "línea 7, campo :monto (posiciones 21-32): se esperaban 12 dígitos, llegaron \\"0001234A567\\"; hay un carácter no numérico en el monto"

  Sin causa probable el mensaje simplemente la omite:

      iex> AnchoFijo.Diagnostico.nuevo(tipo: :entrada, esperado: "un archivo legible", recibido: ":enoent")
      ...> |> AnchoFijo.Diagnostico.mensaje()
      "entrada: se esperaba un archivo legible, llegó :enoent"

  Un diagnóstico sensible muestra la forma del valor; con `revelar: true`, el
  valor:

      iex> alias AnchoFijo.Diagnostico
      iex> d = Diagnostico.nuevo(campo: :rut, esperado: "un RUT", recibido: ~s("1234A678-5"))
      ...>     |> Diagnostico.marcar_sensible("1234A678-5")
      iex> Diagnostico.mensaje(d)
      "campo :rut: se esperaban un RUT, llegaron <10 caracteres: 4 dígitos, 1 letra, 3 dígitos, \\"-\\", 1 dígito>"
      iex> Diagnostico.mensaje(d, revelar: true)
      "campo :rut: se esperaban un RUT, llegaron \\"1234A678-5\\""

  Con `audiencia: :usuario` y/o `idioma: :en`, el mensaje para una pantalla
  de carga, sin la causa probable ni la sintaxis de átomos:

      iex> alias AnchoFijo.Diagnostico
      iex> d = Diagnostico.nuevo(tipo: :campo_invalido, linea: 42, campo: :monto, posicion: {11, 22},
      ...>   esperado: "8 dígitos con 2 decimales implícitos", recibido: ~s("AB"),
      ...>   causa_probable: "hay caracteres no numéricos; declare separador: :punto si el archivo usa punto")
      iex> Diagnostico.mensaje(d)
      "línea 42, campo :monto (posiciones 11-22): se esperaban 8 dígitos con 2 decimales implícitos, llegaron \\"AB\\"; hay caracteres no numéricos; declare separador: :punto si el archivo usa punto"
      iex> Diagnostico.mensaje(d, idioma: :en)
      "line 42, field :monto (positions 11-22): expected 8 dígitos con 2 decimales implícitos, got \\"AB\\"; hay caracteres no numéricos; declare separador: :punto si el archivo usa punto"
      iex> Diagnostico.mensaje(d, audiencia: :usuario)
      "Línea 42, campo monto: el valor no es válido (se esperaba 8 dígitos con 2 decimales implícitos, llegó \\"AB\\")."
      iex> Diagnostico.mensaje(d, audiencia: :usuario, idioma: :en)
      "Line 42, field monto: the value is not valid (expected 8 dígitos con 2 decimales implícitos, got \\"AB\\")."
  """
  @spec mensaje(t(), keyword()) :: String.t()
  def mensaje(%__MODULE__{} = diagnostico, opts \\ []) do
    revelar? = Keyword.get(opts, :revelar, false)
    idioma = Keyword.get(opts, :idioma, :es)
    d = visible(diagnostico, revelar?)

    case Keyword.get(opts, :audiencia, :desarrollador) do
      :usuario -> para_usuario(d, idioma)
      _desarrollador -> para_desarrollador(d, idioma)
    end
  end

  defp para_desarrollador(%__MODULE__{} = d, idioma) do
    IO.iodata_to_binary([contexto(d, idioma), ": ", nucleo(d, idioma), causa(d)])
  end

  # Para el usuario: dónde, qué clase de problema (por tipo, en su idioma) y
  # el detalle entre paréntesis. Sin la causa probable, que habla de opciones
  # del layout, y sin los dos puntos de los átomos.
  defp para_usuario(%__MODULE__{} = d, idioma) do
    donde = ubicacion_para_usuario(d, idioma)
    detalle = detalle_para_usuario(d, idioma)
    frase = explicacion(d.tipo, idioma)

    frase = if donde == "", do: mayuscula_inicial(frase), else: frase
    IO.iodata_to_binary([donde, frase, detalle, "."])
  end

  defp mayuscula_inicial(texto) do
    {primera, resto} = String.split_at(texto, 1)
    String.upcase(primera) <> resto
  end

  defp ubicacion_para_usuario(%__MODULE__{linea: nil, campo: nil}, _idioma), do: ""

  defp ubicacion_para_usuario(%__MODULE__{} = d, idioma) do
    partes =
      [
        d.linea && "#{palabra(:linea, idioma, :mayuscula)} #{d.linea}",
        d.campo &&
          "#{palabra(:campo, idioma, if(d.linea, do: :minuscula, else: :mayuscula))} #{d.campo}"
      ]
      |> Enum.reject(&is_nil/1)

    Enum.join(partes, ", ") <> ": "
  end

  defp detalle_para_usuario(%__MODULE__{esperado: nil, recibido: nil}, _idioma), do: ""

  defp detalle_para_usuario(%__MODULE__{esperado: esperado, recibido: nil}, idioma),
    do: " (#{palabra(:se_esperaba, idioma)} #{esperado})"

  defp detalle_para_usuario(%__MODULE__{esperado: nil, recibido: recibido}, idioma),
    do: " (#{palabra(:llego, idioma)} #{recibido})"

  defp detalle_para_usuario(%__MODULE__{esperado: esperado, recibido: recibido}, idioma),
    do: " (#{palabra(:se_esperaba, idioma)} #{esperado}, #{palabra(:llego, idioma)} #{recibido})"

  # La explicación por tipo es la única parte del mensaje que la librería
  # puede traducir entera: lo que :esperado y :recibido describen lo redacta
  # cada tipo, en español.
  @explicaciones %{
    layout: {"la definición del formato es inválida", "the format definition is invalid"},
    entrada: {"el archivo no se pudo leer", "the file could not be read"},
    largo_de_linea:
      {"la línea no tiene el largo esperado", "the line does not have the expected length"},
    encoding: {"hay caracteres que no se pueden leer", "there are characters that cannot be read"},
    campo_invalido: {"el valor no es válido", "the value is not valid"},
    relleno_completado:
      {"la línea venía corta y se completó con relleno", "the line was short and was padded"},
    moneda: {"las monedas no son compatibles", "the currencies are not compatible"},
    campo_truncado: {"el texto no cabía y se recortó", "the text did not fit and was truncated"},
    doble_codificacion:
      {"el texto viene con la codificación duplicada", "the text is double-encoded"},
    estructura:
      {"la estructura del archivo no es la esperada", "the file structure is not the expected one"},
    control: {"los totales no cuadran", "the totals do not add up"},
    identidad:
      {"el archivo ya fue procesado o su identidad no es válida",
       "the file was already processed or its identity is not valid"}
  }

  @doc """
  La explicación de un tipo de diagnóstico para el usuario final, en el
  idioma pedido.

      iex> AnchoFijo.Diagnostico.explicacion(:control, :en)
      "the totals do not add up"
  """
  @spec explicacion(tipo(), :es | :en) :: String.t()
  def explicacion(tipo, idioma) do
    {es, en} =
      Map.get(
        @explicaciones,
        tipo,
        {"hay un problema con el archivo", "there is a problem with the file"}
      )

    if idioma == :en, do: en, else: es
  end

  @palabras %{
    linea: {"línea", "line"},
    campo: {"campo", "field"},
    posiciones: {"posiciones", "positions"},
    se_esperaba: {"se esperaba", "expected"},
    llego: {"llegó", "got"},
    se_esperaban: {"se esperaban", "expected"},
    llegaron: {"llegaron", "got"},
    se_recibio: {"se recibió", "got"},
    formato_inconsistente: {"formato inconsistente", "inconsistent format"},
    entrada: {"entrada", "input"},
    estructura: {"estructura", "structure"},
    layout: {"layout", "layout"},
    moneda: {"moneda", "currency"},
    identidad: {"identidad", "identity"}
  }

  defp palabra(clave, idioma, caja \\ :minuscula) do
    {es, en} = Map.fetch!(@palabras, clave)
    texto = if idioma == :en, do: en, else: es
    if caja == :mayuscula, do: String.capitalize(texto), else: texto
  end

  # Lo que las representaciones de texto ven: el diagnóstico tal cual, o con
  # la forma en lugar del valor si es sensible y no se pidió revelar.
  defp visible(%__MODULE__{sensible: true, redactado: redactado} = d, false),
    do: %__MODULE__{d | recibido: redactado}

  defp visible(%__MODULE__{} = d, _revelar?), do: d

  @doc """
  Redacta una lista de diagnósticos como texto multilínea, uno por renglón.

      iex> alias AnchoFijo.Diagnostico
      iex> [
      ...>   Diagnostico.nuevo(tipo: :largo_de_linea, linea: 3, esperado: "40 bytes", recibido: "38"),
      ...>   Diagnostico.nuevo(tipo: :largo_de_linea, linea: 9, esperado: "40 bytes", recibido: "41")
      ...> ]
      ...> |> Diagnostico.reporte()
      ...> |> String.split("\\n")
      ["línea 3: se esperaban 40 bytes, llegaron 38", "línea 9: se esperaban 40 bytes, llegaron 41"]

  Acepta `revelar: true` igual que `mensaje/2`.
  """
  @spec reporte([t()], keyword()) :: String.t()
  def reporte(diagnosticos, opts \\ []) when is_list(diagnosticos) do
    Enum.map_join(diagnosticos, "\n", &mensaje(&1, opts))
  end

  @doc """
  El diagnóstico como mapa de claves estables, para una API o para
  guardarlo: `:tipo`, `:gravedad`, `:linea`, `:campo`, `:posicion` (como
  `[desde, hasta]`), `:esperado`, `:recibido`, `:causa_probable`,
  `:contenido`, `:sensible` y `:mensaje`. Acepta las opciones de
  `mensaje/2`; sin `revelar: true`, un diagnóstico sensible lleva la forma
  del valor en `:recibido` y `nil` en `:contenido`.

      iex> alias AnchoFijo.Diagnostico
      iex> d = Diagnostico.nuevo(tipo: :largo_de_linea, linea: 3, esperado: "40 bytes", recibido: "38")
      iex> Diagnostico.a_mapa(d)
      %{tipo: :largo_de_linea, gravedad: :error, linea: 3, campo: nil, posicion: nil, esperado: "40 bytes", recibido: "38", causa_probable: nil, contenido: nil, sensible: false, mensaje: "línea 3: se esperaban 40 bytes, llegaron 38"}
      iex> Diagnostico.desde_mapa(Diagnostico.a_mapa(d)) == d
      true
  """
  @spec a_mapa(t(), keyword()) :: map()
  def a_mapa(%__MODULE__{} = diagnostico, opts \\ []) do
    d = visible(diagnostico, Keyword.get(opts, :revelar, false))
    revelado? = not diagnostico.sensible or Keyword.get(opts, :revelar, false)

    %{
      tipo: d.tipo,
      gravedad: d.gravedad,
      linea: d.linea,
      campo: d.campo,
      posicion: d.posicion && Tuple.to_list(d.posicion),
      esperado: d.esperado,
      recibido: d.recibido,
      causa_probable: d.causa_probable,
      contenido: if(revelado?, do: d.contenido),
      sensible: d.sensible,
      mensaje: mensaje(diagnostico, opts)
    }
  end

  @doc """
  La vuelta de `a_mapa/2`: desde un mapa con claves átomo o string (como
  llega de un JSON). Lo que no viene queda en su default; un diagnóstico
  sensible vuelve con el valor redactado, que es lo único que viajó.

      iex> alias AnchoFijo.Diagnostico
      iex> Diagnostico.desde_mapa(%{"tipo" => "control", "linea" => 5, "campo" => "total", "posicion" => [9, 24], "esperado" => "1250", "recibido" => "1000"})
      %AnchoFijo.Diagnostico{tipo: :control, linea: 5, campo: :total, posicion: {9, 24}, esperado: "1250", recibido: "1000"}
  """
  @spec desde_mapa(map()) :: t()
  def desde_mapa(mapa) when is_map(mapa) do
    leer = fn clave -> Map.get(mapa, clave) || Map.get(mapa, Atom.to_string(clave)) end
    sensible? = leer.(:sensible) == true

    nuevo(
      tipo: atomo(leer.(:tipo), :campo_invalido),
      gravedad: atomo(leer.(:gravedad), :error),
      linea: leer.(:linea),
      campo: atomo(leer.(:campo), nil),
      posicion: posicion_desde(leer.(:posicion)),
      esperado: leer.(:esperado),
      recibido: leer.(:recibido),
      causa_probable: leer.(:causa_probable),
      contenido: leer.(:contenido),
      sensible: sensible?,
      redactado: if(sensible?, do: leer.(:recibido))
    )
  end

  # Los tipos, gravedades y campos son átomos conocidos o declarados por el
  # layout: `String.to_existing_atom/1` evita crear átomos desde un JSON
  # ajeno; uno que no existe queda como string en :campo.
  defp atomo(nil, default), do: default
  defp atomo(valor, _default) when is_atom(valor), do: valor

  defp atomo(valor, default) when is_binary(valor) do
    String.to_existing_atom(valor)
  rescue
    ArgumentError -> if is_nil(default), do: valor, else: default
  end

  defp posicion_desde([desde, hasta]) when is_integer(desde) and is_integer(hasta),
    do: {desde, hasta}

  defp posicion_desde({_, _} = posicion), do: posicion
  defp posicion_desde(_otro), do: nil

  @typedoc "El resumen de una lista de diagnósticos, para una pantalla de carga."
  @type resumen :: %{
          total: non_neg_integer(),
          errores: non_neg_integer(),
          advertencias: non_neg_integer(),
          por_tipo: %{tipo() => non_neg_integer()},
          por_campo: %{atom() => non_neg_integer()},
          lineas_afectadas: [pos_integer()],
          lineas_con_error: non_neg_integer(),
          veredicto: :aceptable | :aceptable_con_observaciones | :rechazable,
          texto: String.t()
        }

  @doc """
  Resume una lista de diagnósticos: totales por gravedad, por tipo y por
  campo, las primeras líneas afectadas (`lineas: 10` por default), cuántas
  líneas tienen errores, y el veredicto: `:rechazable` si hay algún error,
  `:aceptable_con_observaciones` si solo hay advertencias, `:aceptable` si
  no hay nada. `:texto` lo dice en una frase, en el `idioma:` pedido.

      iex> alias AnchoFijo.Diagnostico
      iex> diagnosticos = [
      ...>   Diagnostico.nuevo(tipo: :campo_invalido, linea: 2, campo: :monto),
      ...>   Diagnostico.nuevo(tipo: :campo_invalido, linea: 7, campo: :monto),
      ...>   Diagnostico.nuevo(tipo: :relleno_completado, gravedad: :advertencia, linea: 9)
      ...> ]
      iex> resumen = Diagnostico.resumen(diagnosticos)
      iex> {resumen.veredicto, resumen.errores, resumen.advertencias, resumen.por_campo, resumen.lineas_afectadas}
      {:rechazable, 2, 1, %{monto: 2}, [2, 7, 9]}
      iex> resumen.texto
      "2 errores en 2 líneas y 1 advertencia: el archivo se rechaza"
      iex> Diagnostico.resumen(diagnosticos, idioma: :en).texto
      "2 errors in 2 lines and 1 warning: the file is rejected"
      iex> Diagnostico.resumen([]).texto
      "sin observaciones: el archivo se acepta"
  """
  @spec resumen([t()], keyword()) :: resumen()
  def resumen(diagnosticos, opts \\ []) when is_list(diagnosticos) do
    {errores, advertencias} = separar(diagnosticos)
    idioma = Keyword.get(opts, :idioma, :es)

    lineas =
      diagnosticos |> Enum.map(& &1.linea) |> Enum.reject(&is_nil/1) |> Enum.uniq() |> Enum.sort()

    lineas_con_error =
      errores |> Enum.map(& &1.linea) |> Enum.reject(&is_nil/1) |> Enum.uniq() |> length()

    veredicto =
      cond do
        errores != [] -> :rechazable
        advertencias != [] -> :aceptable_con_observaciones
        true -> :aceptable
      end

    %{
      total: length(diagnosticos),
      errores: length(errores),
      advertencias: length(advertencias),
      por_tipo: Enum.frequencies_by(diagnosticos, & &1.tipo),
      por_campo: diagnosticos |> Enum.reject(&is_nil(&1.campo)) |> Enum.frequencies_by(& &1.campo),
      lineas_afectadas: Enum.take(lineas, Keyword.get(opts, :lineas, 10)),
      lineas_con_error: lineas_con_error,
      veredicto: veredicto,
      texto:
        texto_del_resumen(
          length(errores),
          lineas_con_error,
          length(advertencias),
          veredicto,
          idioma
        )
    }
  end

  defp texto_del_resumen(0, _lineas, 0, _veredicto, :en),
    do: "no observations: the file is accepted"

  defp texto_del_resumen(0, _lineas, 0, _veredicto, _es),
    do: "sin observaciones: el archivo se acepta"

  defp texto_del_resumen(errores, lineas, advertencias, veredicto, idioma) do
    partes =
      [
        if(errores > 0,
          do:
            "#{plural(errores, :error, idioma)} #{palabra_en(idioma)} #{plural(lineas, :linea, idioma)}"
        ),
        if(advertencias > 0, do: plural(advertencias, :advertencia, idioma))
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(if(idioma == :en, do: " and ", else: " y "))

    cierre =
      case {veredicto, idioma} do
        {:rechazable, :en} -> "the file is rejected"
        {:rechazable, _} -> "el archivo se rechaza"
        {_, :en} -> "the file is accepted with observations"
        {_, _} -> "el archivo se acepta con observaciones"
      end

    partes <> ": " <> cierre
  end

  defp palabra_en(:en), do: "in"
  defp palabra_en(_es), do: "en"

  defp plural(1, :error, :en), do: "1 error"
  defp plural(n, :error, :en), do: "#{n} errors"
  defp plural(1, :error, _es), do: "1 error"
  defp plural(n, :error, _es), do: "#{n} errores"
  defp plural(1, :linea, :en), do: "1 line"
  defp plural(n, :linea, :en), do: "#{n} lines"
  defp plural(1, :linea, _es), do: "1 línea"
  defp plural(n, :linea, _es), do: "#{n} líneas"
  defp plural(1, :advertencia, :en), do: "1 warning"
  defp plural(n, :advertencia, :en), do: "#{n} warnings"
  defp plural(1, :advertencia, _es), do: "1 advertencia"
  defp plural(n, :advertencia, _es), do: "#{n} advertencias"

  @doc """
  Separa una lista de diagnósticos en errores y advertencias, en ese orden.

  Existe porque el modo `:tolerante` devuelve las dos gravedades en una sola
  lista, y quien decide si el lote se procesa o se devuelve al emisor necesita
  esa partición sin escribirla en cada llamada.

      iex> alias AnchoFijo.Diagnostico
      iex> {errores, advertencias} = Diagnostico.separar([
      ...>   Diagnostico.nuevo(tipo: :campo_invalido, linea: 2),
      ...>   Diagnostico.nuevo(tipo: :relleno_completado, gravedad: :advertencia, linea: 5)
      ...> ])
      iex> {Enum.map(errores, & &1.linea), Enum.map(advertencias, & &1.linea)}
      {[2], [5]}
  """
  @spec separar([t()]) :: {[t()], [t()]}
  def separar(diagnosticos) when is_list(diagnosticos) do
    Enum.split_with(diagnosticos, &(&1.gravedad == :error))
  end

  @doc """
  `true` si la lista no trae ningún diagnóstico de gravedad `:error`.

      iex> alias AnchoFijo.Diagnostico
      iex> Diagnostico.solo_advertencias?([Diagnostico.nuevo(gravedad: :advertencia)])
      true
      iex> Diagnostico.solo_advertencias?([Diagnostico.nuevo(tipo: :campo_invalido)])
      false
  """
  @spec solo_advertencias?([t()]) :: boolean()
  def solo_advertencias?(diagnosticos) when is_list(diagnosticos) do
    Enum.all?(diagnosticos, &(&1.gravedad == :advertencia))
  end

  defp contexto(%__MODULE__{} = d, idioma) do
    segmentos =
      [prefijo_tipo(d.tipo, idioma), linea(d.linea, idioma), campo(d.campo, d.posicion, idioma)]
      |> Enum.reject(&is_nil/1)

    case segmentos do
      [] -> sin_contexto(d.tipo, idioma)
      lista -> Enum.join(lista, ", ")
    end
  end

  # Un diagnóstico sin línea ni campo habla del archivo entero. Si es de
  # estructura (un trailer que no llegó), decirlo: "entrada:" culparía a la
  # lectura del archivo, que estuvo bien.
  defp sin_contexto(:estructura, idioma), do: palabra(:estructura, idioma)
  defp sin_contexto(_otro, idioma), do: palabra(:entrada, idioma)

  defp prefijo_tipo(tipo, idioma) when tipo in [:layout, :entrada, :moneda, :identidad],
    do: palabra(tipo, idioma)

  defp prefijo_tipo(_otro, _idioma), do: nil

  defp linea(nil, _idioma), do: nil
  defp linea(numero, idioma), do: "#{palabra(:linea, idioma)} #{numero}"

  defp campo(nil, _posicion, _idioma), do: nil
  defp campo(nombre, nil, idioma), do: "#{palabra(:campo, idioma)} #{inspect(nombre)}"

  defp campo(nombre, {desde, hasta}, idioma),
    do:
      "#{palabra(:campo, idioma)} #{inspect(nombre)} (#{palabra(:posiciones, idioma)} #{desde}-#{hasta})"

  # El plural ("se esperaban ... llegaron") es el caso frecuente porque casi
  # siempre se habla de bytes, dígitos o caracteres. El singular queda para
  # cuando no hay nada que contar y el sujeto es el archivo entero. En
  # inglés no hay distinción.
  defp nucleo(%__MODULE__{esperado: nil, recibido: nil}, idioma),
    do: palabra(:formato_inconsistente, idioma)

  defp nucleo(%__MODULE__{esperado: nil, recibido: recibido}, idioma),
    do: "#{palabra(:se_recibio, idioma)} #{recibido}"

  defp nucleo(%__MODULE__{esperado: esperado, recibido: nil} = d, idioma),
    do: "#{esperaba(d, idioma)} #{esperado}"

  defp nucleo(%__MODULE__{esperado: esperado, recibido: recibido} = d, idioma),
    do: "#{esperaba(d, idioma)} #{esperado}, #{llego(d, idioma)} #{recibido}"

  @singulares [:entrada, :layout, :moneda, :estructura, :control, :identidad]

  defp esperaba(%__MODULE__{tipo: tipo}, idioma) when tipo in @singulares,
    do: palabra(:se_esperaba, idioma)

  defp esperaba(_d, idioma), do: palabra(:se_esperaban, idioma)

  defp llego(%__MODULE__{tipo: tipo}, idioma) when tipo in @singulares, do: palabra(:llego, idioma)
  defp llego(_d, idioma), do: palabra(:llegaron, idioma)

  defp causa(%__MODULE__{causa_probable: nil}), do: ""
  defp causa(%__MODULE__{causa_probable: causa}), do: "; " <> causa

  defp texto(nil), do: nil
  defp texto(valor) when is_binary(valor), do: valor
  defp texto(valor), do: inspect(valor)

  defimpl String.Chars do
    def to_string(diagnostico), do: AnchoFijo.Diagnostico.mensaje(diagnostico)
  end

  # `Logger.error(inspect(diagnostico))` es el camino más común hacia el log,
  # así que `inspect/1` redacta igual que `mensaje/1`: `:recibido` muestra la
  # forma y `:contenido` se oculta. Es el mismo patrón que Ecto con
  # `redact: true`. El struct sigue entero; solo cambia cómo se imprime.
  defimpl Inspect do
    import Inspect.Algebra

    def inspect(%{sensible: true} = diagnostico, opts) do
      redactado = %{
        diagnostico
        | recibido: diagnostico.redactado,
          contenido: diagnostico.contenido && "**redactado**"
      }

      concat(["#AnchoFijo.Diagnostico", to_doc(Map.from_struct(redactado), opts)])
    end

    def inspect(diagnostico, opts), do: Inspect.Any.inspect(diagnostico, opts)
  end

  # Con Jason en el proyecto que compila la librería, un diagnóstico se
  # codifica como su `a_mapa/1`: redactado, con el mensaje. La decisión se
  # toma al compilar, como con :telemetry y Decimal; sin Jason no se define
  # nada y el paquete sigue sin dependencias de runtime.
  if Code.ensure_loaded?(Jason) do
    defimpl Jason.Encoder do
      def encode(diagnostico, opts) do
        Jason.Encode.map(AnchoFijo.Diagnostico.a_mapa(diagnostico), opts)
      end
    end
  end
end
