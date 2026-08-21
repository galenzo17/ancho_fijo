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
  """
  @type tipo ::
          :layout
          | :entrada
          | :largo_de_linea
          | :encoding
          | :campo_invalido
          | :relleno_completado

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

  @type t :: %__MODULE__{
          tipo: tipo(),
          gravedad: gravedad(),
          linea: pos_integer() | nil,
          campo: atom() | nil,
          posicion: {pos_integer(), pos_integer()} | nil,
          esperado: String.t() | nil,
          recibido: String.t() | nil,
          causa_probable: String.t() | nil,
          contenido: String.t() | nil
        }

  defstruct tipo: :campo_invalido,
            gravedad: :error,
            linea: nil,
            campo: nil,
            posicion: nil,
            esperado: nil,
            recibido: nil,
            causa_probable: nil,
            contenido: nil

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
      contenido: texto(Map.get(atributos, :contenido))
    }
  end

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
  """
  @spec mensaje(t()) :: String.t()
  def mensaje(%__MODULE__{} = diagnostico) do
    IO.iodata_to_binary([
      contexto(diagnostico),
      ": ",
      nucleo(diagnostico),
      causa(diagnostico)
    ])
  end

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
  """
  @spec reporte([t()]) :: String.t()
  def reporte(diagnosticos) when is_list(diagnosticos) do
    Enum.map_join(diagnosticos, "\n", &mensaje/1)
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
       when tipo in [:entrada, :layout],
       do: "se esperaba #{esperado}"

  defp nucleo(%__MODULE__{tipo: tipo, esperado: esperado, recibido: recibido})
       when tipo in [:entrada, :layout],
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
end

defmodule AnchoFijo.Error do
  @moduledoc """
  Excepción que envuelve uno o más `AnchoFijo.Diagnostico`.

  Solo la levantan las funciones con `!` (`AnchoFijo.Layout.nuevo!/1` y
  `AnchoFijo.stream/3`), reservadas para errores del programador —un layout mal
  definido— y no para datos sucios, que siempre se devuelven como valor.
  """

  defexception [:diagnosticos]

  @type t :: %__MODULE__{diagnosticos: [AnchoFijo.Diagnostico.t()]}

  @impl true
  def exception(diagnosticos) when is_list(diagnosticos) do
    %__MODULE__{diagnosticos: diagnosticos}
  end

  @impl true
  def exception(diagnostico), do: %__MODULE__{diagnosticos: [diagnostico]}

  @impl true
  def message(%__MODULE__{diagnosticos: diagnosticos}) do
    AnchoFijo.Diagnostico.reporte(diagnosticos)
  end
end
