defmodule AnchoFijo.Monto do
  @moduledoc """
  Un monto con su moneda: unidades mínimas, escala y código ISO 4217. Nunca
  un float.

  Un `:decimal` sin moneda devuelve `{unidades, precision}`, y eso no cambia.
  Con `moneda: :clp` en el layout, devuelve este struct, y la `:precision`
  pasa a ser una propiedad de la moneda y no una preferencia del layout: CLP
  no tiene decimales, USD tiene dos, KWD tiene tres, y leer pesos chilenos con
  `precision: 2` divide todo por cien sin que nadie se entere hasta la
  conciliación. Por eso un `:decimal` con `moneda: :clp` y `precision: 2` es
  un layout inválido.

      iex> layout = AnchoFijo.Layout.nuevo!(campos: [[nombre: :monto, largo: 10, tipo: :decimal, moneda: :clp]])
      iex> {:ok, [%{monto: monto}], []} = AnchoFijo.parsear(layout, "0000125000\\n")
      iex> monto
      #AnchoFijo.Monto<125.000 CLP>
      iex> monto.unidades
      125000

  ## Aritmética que no pierde el peso

  Las operaciones son sobre enteros y exigen la misma moneda. Sumar CLP con
  USD no es un error de tipos: es un error del dominio, y se devuelve como
  diagnóstico.

      iex> alias AnchoFijo.Monto
      iex> {:ok, total} = Monto.sumar(Monto.nuevo(1000, :clp), Monto.nuevo(250, :clp))
      iex> total
      #AnchoFijo.Monto<1.250 CLP>
      iex> {:error, diagnostico} = Monto.sumar(Monto.nuevo(1000, :clp), Monto.nuevo(250, :usd))
      iex> AnchoFijo.Diagnostico.mensaje(diagnostico)
      "moneda: se esperaba la misma moneda en los dos montos, llegó CLP y USD; no se pueden sumar montos de monedas distintas sin un tipo de cambio"

  ## La tabla ISO 4217 es acotada

  Trae las monedas de la región, las de reserva y todas las que tienen una
  escala distinta de dos, que son las que importan: con una moneda que no
  está en la tabla, la escala no se puede validar. Si la moneda falta y el
  layout declara `:precision`, el layout se construye con una advertencia;
  sin `:precision`, es un error. Ver `monedas/0`.
  """

  alias AnchoFijo.Diagnostico

  @type moneda :: atom()
  @type t :: %__MODULE__{unidades: integer(), precision: non_neg_integer(), moneda: moneda()}

  @enforce_keys [:unidades, :precision, :moneda]
  defstruct [:unidades, :precision, :moneda]

  # Escala ISO 4217: cantidad de decimales de la unidad. Dos es el default
  # del mundo; se listan completas las que no lo son y las que alguien va a
  # usar con esta librería.
  @escalas %{
    # Sin decimales
    clp: 0,
    jpy: 0,
    krw: 0,
    pyg: 0,
    vnd: 0,
    isk: 0,
    ugx: 0,
    rwf: 0,
    xof: 0,
    xaf: 0,
    xpf: 0,
    gnf: 0,
    djf: 0,
    kmf: 0,
    vuv: 0,
    # Tres decimales
    bhd: 3,
    kwd: 3,
    omr: 3,
    jod: 3,
    tnd: 3,
    iqd: 3,
    lyd: 3,
    # Dos decimales: la región y las de reserva
    usd: 2,
    eur: 2,
    gbp: 2,
    chf: 2,
    cad: 2,
    aud: 2,
    nzd: 2,
    cny: 2,
    inr: 2,
    brl: 2,
    ars: 2,
    mxn: 2,
    cop: 2,
    pen: 2,
    uyu: 2,
    bob: 2,
    gtq: 2,
    hnl: 2,
    nio: 2,
    crc: 2,
    pab: 2,
    dop: 2,
    sek: 2,
    nok: 2,
    dkk: 2,
    pln: 2,
    czk: 2,
    huf: 2,
    try: 2,
    zar: 2,
    ils: 2,
    sgd: 2,
    hkd: 2
  }

  @doc """
  Las monedas de la tabla, con su escala.

      iex> AnchoFijo.Monto.monedas()[:clp]
      0
      iex> AnchoFijo.Monto.monedas()[:kwd]
      3
  """
  @spec monedas() :: %{moneda() => non_neg_integer()}
  def monedas, do: @escalas

  @doc """
  La escala ISO 4217 de una moneda, o `:error` si no está en la tabla.

      iex> AnchoFijo.Monto.escala(:usd)
      {:ok, 2}
      iex> AnchoFijo.Monto.escala(:xyz)
      :error
  """
  @spec escala(moneda()) :: {:ok, non_neg_integer()} | :error
  def escala(moneda), do: Map.fetch(@escalas, moneda)

  @doc """
  Construye un monto desde unidades mínimas. Con dos argumentos, la escala
  es la de la tabla; con tres, la que se pasa (para una moneda que no está).

      iex> AnchoFijo.Monto.nuevo(125_000, :clp)
      #AnchoFijo.Monto<125.000 CLP>
      iex> AnchoFijo.Monto.nuevo(-123_456, :usd)
      #AnchoFijo.Monto<-1.234,56 USD>
      iex> AnchoFijo.Monto.nuevo(5, 1, :xyz)
      #AnchoFijo.Monto<0,5 XYZ>

  Una moneda que no está en la tabla sin escala es `ArgumentError`: no hay
  forma de saber qué significan las unidades.
  """
  @spec nuevo(integer(), moneda()) :: t()
  def nuevo(unidades, moneda) when is_integer(unidades) and is_atom(moneda) do
    case escala(moneda) do
      {:ok, precision} ->
        nuevo(unidades, precision, moneda)

      :error ->
        raise ArgumentError,
              "la moneda #{inspect(moneda)} no está en la tabla ISO 4217 de AnchoFijo.Monto; " <>
                "use nuevo/3 con la escala explícita"
    end
  end

  @spec nuevo(integer() | struct(), non_neg_integer(), moneda()) :: t()
  def nuevo(unidades, precision, moneda)
      when is_integer(unidades) and is_integer(precision) and precision >= 0 and is_atom(moneda) do
    %__MODULE__{unidades: unidades, precision: precision, moneda: moneda}
  end

  # Un `%Decimal{}` con la precisión dada; más decimales es un ArgumentError.
  def nuevo(%{__struct__: Decimal} = decimal, precision, moneda)
      when is_integer(precision) and precision >= 0 and is_atom(moneda) do
    case desde_decimal(decimal, precision, moneda) do
      {:ok, monto} -> monto
      {:error, diagnostico} -> raise ArgumentError, Diagnostico.mensaje(diagnostico)
    end
  end

  @doc """
  Un monto desde un `%Decimal{}`, con la escala de la moneda (o una precisión
  explícita). `{:error, diagnostico}` si el decimal tiene más decimales que
  la escala: no se redondea, porque redondear acá es donde se pierde el peso.

      iex> AnchoFijo.Monto.desde_decimal(Decimal.new("1234.56"), :usd)
      {:ok, AnchoFijo.Monto.nuevo(123_456, :usd)}
      iex> {:error, diagnostico} = AnchoFijo.Monto.desde_decimal(Decimal.new("1234.567"), :usd)
      iex> AnchoFijo.Diagnostico.mensaje(diagnostico)
      "moneda: se esperaba un decimal con a lo más 2 decimales, la escala de USD, llegó 1234.567; convierta o redondee antes, a propósito: la librería no decide por usted"
  """
  @compile {:no_warn_undefined, Decimal}
  @spec desde_decimal(struct(), moneda() | non_neg_integer(), moneda() | nil) ::
          {:ok, t()} | {:error, Diagnostico.t()}
  def desde_decimal(decimal, moneda_o_precision, moneda \\ nil)

  def desde_decimal(decimal, moneda, nil) when is_atom(moneda) do
    case escala(moneda) do
      {:ok, precision} ->
        desde_decimal(decimal, precision, moneda)

      :error ->
        raise ArgumentError,
              "la moneda #{inspect(moneda)} no está en la tabla ISO 4217 de AnchoFijo.Monto; " <>
                "use desde_decimal/3 con la escala explícita"
    end
  end

  def desde_decimal(%{__struct__: Decimal} = decimal, precision, moneda)
      when is_integer(precision) and precision >= 0 and is_atom(moneda) do
    escalado = Decimal.mult(decimal, Decimal.new(Integer.pow(10, precision)))

    if Decimal.integer?(escalado) do
      {:ok, nuevo(Decimal.to_integer(escalado), precision, moneda)}
    else
      {:error,
       incompatibles(
         "un decimal con a lo más #{precision} decimales, la escala de #{codigo(moneda)}",
         Decimal.to_string(decimal, :normal),
         "convierta o redondee antes, a propósito: la librería no decide por usted"
       )}
    end
  end

  @doc """
  El monto cero de una moneda, para empezar una reducción.

      iex> AnchoFijo.Monto.cero(:eur)
      #AnchoFijo.Monto<0,00 EUR>
  """
  @spec cero(moneda()) :: t()
  def cero(moneda), do: nuevo(0, moneda)

  @doc """
  Suma dos montos de la misma moneda. Monedas distintas son un diagnóstico.

      iex> alias AnchoFijo.Monto
      iex> {:ok, suma} = Monto.sumar(Monto.nuevo(100, :usd), Monto.nuevo(-30, :usd))
      iex> suma
      #AnchoFijo.Monto<0,70 USD>
  """
  @spec sumar(t(), t()) :: {:ok, t()} | {:error, Diagnostico.t()}
  def sumar(%__MODULE__{moneda: m, precision: p} = a, %__MODULE__{moneda: m, precision: p} = b) do
    {:ok, %__MODULE__{a | unidades: a.unidades + b.unidades}}
  end

  def sumar(%__MODULE__{moneda: m} = a, %__MODULE__{moneda: m} = b) do
    {:error,
     incompatibles(
       "la misma escala en los dos montos",
       "#{a.precision} y #{b.precision}",
       "los dos montos son #{codigo(m)} pero con escalas distintas; uno de los dos se construyó mal"
     )}
  end

  def sumar(%__MODULE__{} = a, %__MODULE__{} = b) do
    {:error,
     incompatibles(
       "la misma moneda en los dos montos",
       "#{codigo(a.moneda)} y #{codigo(b.moneda)}",
       "no se pueden sumar montos de monedas distintas sin un tipo de cambio"
     )}
  end

  @doc """
  Como `sumar/2`, pero devuelve el monto o levanta `AnchoFijo.Error`.
  """
  @spec sumar!(t(), t()) :: t()
  def sumar!(%__MODULE__{} = a, %__MODULE__{} = b) do
    case sumar(a, b) do
      {:ok, monto} -> monto
      {:error, diagnostico} -> raise AnchoFijo.Error, diagnostico
    end
  end

  @doc """
  El monto con el signo cambiado.

      iex> AnchoFijo.Monto.negar(AnchoFijo.Monto.nuevo(100, :usd))
      #AnchoFijo.Monto<-1,00 USD>
  """
  @spec negar(t()) :: t()
  def negar(%__MODULE__{} = monto), do: %__MODULE__{monto | unidades: -monto.unidades}

  @doc """
  Resta `b` de `a`. Misma regla que `sumar/2`.
  """
  @spec restar(t(), t()) :: {:ok, t()} | {:error, Diagnostico.t()}
  def restar(%__MODULE__{} = a, %__MODULE__{} = b), do: sumar(a, negar(b))

  @doc """
  Suma una lista de montos. La lista vacía necesita la moneda para saber de
  qué es el cero.

      iex> alias AnchoFijo.Monto
      iex> {:ok, total} = Monto.total([Monto.nuevo(10, :clp), Monto.nuevo(20, :clp), Monto.nuevo(30, :clp)])
      iex> total
      #AnchoFijo.Monto<60 CLP>
      iex> {:ok, cero} = Monto.total([], :clp)
      iex> cero
      #AnchoFijo.Monto<0 CLP>
  """
  @spec total([t()], moneda() | nil) :: {:ok, t()} | {:error, Diagnostico.t()}
  def total(montos, moneda \\ nil)

  def total([], nil),
    do:
      {:error,
       incompatibles(
         "una moneda para el total de una lista vacía",
         "ninguna",
         "pase la moneda como segundo argumento"
       )}

  def total([], moneda), do: {:ok, cero(moneda)}

  def total([primero | resto], _moneda) do
    Enum.reduce_while(resto, {:ok, primero}, fn monto, {:ok, acumulado} ->
      case sumar(acumulado, monto) do
        {:ok, suma} -> {:cont, {:ok, suma}}
        {:error, diagnostico} -> {:halt, {:error, diagnostico}}
      end
    end)
  end

  @doc """
  El monto como texto para presentación, con separador de miles y decimal.

      iex> AnchoFijo.Monto.formatear(AnchoFijo.Monto.nuevo(-1_234_567, :usd))
      "-12.345,67 USD"
      iex> AnchoFijo.Monto.formatear(AnchoFijo.Monto.nuevo(1_234_567, :usd), miles: ",", decimal: ".", codigo: false)
      "12,345.67"
      iex> AnchoFijo.Monto.formatear(AnchoFijo.Monto.nuevo(7, :usd))
      "0,07 USD"

  Opciones: `:miles` (default `"."`), `:decimal` (default `","`), `:codigo`
  (default `true`, el código ISO después del número).
  """
  @spec formatear(t(), keyword()) :: String.t()
  def formatear(%__MODULE__{} = monto, opts \\ []) do
    miles = Keyword.get(opts, :miles, ".")
    decimal = Keyword.get(opts, :decimal, ",")
    codigo? = Keyword.get(opts, :codigo, true)

    digitos =
      monto.unidades |> abs() |> Integer.to_string() |> String.pad_leading(monto.precision + 1, "0")

    {entera, fraccion} = String.split_at(digitos, String.length(digitos) - monto.precision)
    signo = if monto.unidades < 0, do: "-", else: ""

    numero =
      signo <> agrupar(entera, miles) <> if(fraccion == "", do: "", else: decimal <> fraccion)

    if codigo?, do: numero <> " " <> codigo(monto.moneda), else: numero
  end

  defp agrupar(entera, miles) do
    entera
    |> String.reverse()
    |> String.graphemes()
    |> Enum.chunk_every(3)
    |> Enum.map_join(miles, &Enum.join/1)
    |> String.reverse()
  end

  @doc """
  El monto como `Decimal`, para quien tenga esa librería. Levanta
  `ArgumentError` si `Decimal` no está disponible: es una dependencia
  opcional que esta librería no trae.

      iex> AnchoFijo.Monto.a_decimal(AnchoFijo.Monto.nuevo(-123_456, :usd))
      Decimal.new("-1234.56")
  """
  @compile {:no_warn_undefined, Decimal}
  @spec a_decimal(t()) :: term()
  def a_decimal(%__MODULE__{} = monto) do
    if Code.ensure_loaded?(Decimal) do
      signo = if monto.unidades < 0, do: -1, else: 1
      Decimal.new(signo, abs(monto.unidades), -monto.precision)
    else
      raise ArgumentError,
            "la librería Decimal no está disponible; agregue {:decimal, \"~> 2.0 or ~> 3.0\"} al proyecto"
    end
  end

  @doc false
  @spec codigo(moneda()) :: String.t()
  def codigo(moneda), do: moneda |> Atom.to_string() |> String.upcase()

  defp incompatibles(esperado, recibido, causa) do
    Diagnostico.nuevo(tipo: :moneda, esperado: esperado, recibido: recibido, causa_probable: causa)
  end

  defimpl Inspect do
    def inspect(monto, _opts), do: "#AnchoFijo.Monto<" <> AnchoFijo.Monto.formatear(monto) <> ">"
  end

  defimpl String.Chars do
    def to_string(monto), do: AnchoFijo.Monto.formatear(monto)
  end
end
