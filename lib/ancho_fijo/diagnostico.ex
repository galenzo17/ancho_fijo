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
  * `:estructura` — en un `AnchoFijo.Multiregistro`: un discriminador
    desconocido, un registro fuera de orden, repetido o faltante.
  * `:control` — en un `AnchoFijo.Multiregistro`: un total del trailer que
    no cuadra con los detalles.
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
          | :estructura
          | :control

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
  """
  @spec mensaje(t(), keyword()) :: String.t()
  def mensaje(%__MODULE__{} = diagnostico, opts \\ []) do
    revelar? = Keyword.get(opts, :revelar, false)

    IO.iodata_to_binary([
      contexto(diagnostico),
      ": ",
      nucleo(visible(diagnostico, revelar?)),
      causa(diagnostico)
    ])
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

  defp contexto(%__MODULE__{} = d) do
    segmentos =
      [prefijo_tipo(d.tipo), linea(d.linea), campo(d.campo, d.posicion)]
      |> Enum.reject(&is_nil/1)

    case segmentos do
      [] -> "entrada"
      lista -> Enum.join(lista, ", ")
    end
  end

  defp prefijo_tipo(:layout), do: "layout"
  defp prefijo_tipo(:entrada), do: "entrada"
  defp prefijo_tipo(:moneda), do: "moneda"
  defp prefijo_tipo(_otro), do: nil

  defp linea(nil), do: nil
  defp linea(numero), do: "línea #{numero}"

  defp campo(nil, _posicion), do: nil
  defp campo(nombre, nil), do: "campo #{inspect(nombre)}"
  defp campo(nombre, {desde, hasta}), do: "campo #{inspect(nombre)} (posiciones #{desde}-#{hasta})"

  # El plural ("se esperaban ... llegaron") es el caso frecuente porque casi
  # siempre se habla de bytes, dígitos o caracteres. El singular queda para
  # cuando no hay nada que contar y el sujeto es el archivo entero.
  defp nucleo(%__MODULE__{esperado: nil, recibido: nil}), do: "formato inconsistente"
  defp nucleo(%__MODULE__{esperado: nil, recibido: recibido}), do: "se recibió #{recibido}"

  defp nucleo(%__MODULE__{tipo: tipo, esperado: esperado, recibido: nil})
       when tipo in [:entrada, :layout, :moneda, :estructura, :control],
       do: "se esperaba #{esperado}"

  defp nucleo(%__MODULE__{tipo: tipo, esperado: esperado, recibido: recibido})
       when tipo in [:entrada, :layout, :moneda, :estructura, :control],
       do: "se esperaba #{esperado}, llegó #{recibido}"

  defp nucleo(%__MODULE__{esperado: esperado, recibido: nil}), do: "se esperaban #{esperado}"

  defp nucleo(%__MODULE__{esperado: esperado, recibido: recibido}),
    do: "se esperaban #{esperado}, llegaron #{recibido}"

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
end
