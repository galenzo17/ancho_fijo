defmodule AnchoFijo.Tipo.Fecha do
  @moduledoc """
  El tipo `:fecha`: dígitos en el orden que `:formato` declara, leídos como
  `Date`.

  No hay default para `:formato` a propósito. Adivinar si `01022024` es el 1
  de febrero o el 2 de enero es justamente el error silencioso que esta
  librería existe para impedir: la definición tiene que decirlo.

  ## Formatos

  | `:formato` | ejemplo | lee |
  | --- | --- | --- |
  | `:aaaammdd` | `20240131` | 2024-01-31 |
  | `:ddmmaaaa` | `31012024` | 2024-01-31 |
  | `:mmddaaaa` | `01312024` | 2024-01-31 (orden estadounidense) |
  | `:aammdd` | `240131` | 2024-01-31 (SWIFT, NACHA) |
  | `:ddmmaa` | `310124` | 2024-01-31 |
  | `:mmddaa` | `013124` | 2024-01-31 |
  | `:aaaaddd` | `2024031` | 2024-01-31 (juliana, día del año) |
  | `:aaddd` | `24031` | 2024-01-31 (juliana de mainframe) |
  | `"DD/MM/AAAA"` | `31/01/2024` | 2024-01-31 (patrón explícito) |
  | `"AAAA-MM-DD"` | `2024-01-31` | 2024-01-31 |

  Cuando ninguno de los nombres calza, `:formato` acepta un patrón: los
  tokens `AAAA`, `AA`, `MM`, `DD` y `DDD` en el orden del archivo, y
  cualquier otro carácter es un separador literal que tiene que estar tal
  cual. El patrón tiene que tener año con mes y día, o año con día del año.

  ## Años de dos dígitos

  `AA` se expande con `:pivote`, el primer año de la ventana de cien:
  con el default, `2000`, `24` es 2024 y `99` es 2099; con `pivote: 1970`,
  `69` es 2069 y `70` es 1970. Es una decisión del formato, no de la
  librería, y por eso se declara. Al escribir, un año fuera de la ventana es
  un diagnóstico, no un `00` silencioso.

  ## Blancos y ceros

  Un campo en blanco y uno en ceros (`00000000`, `00/00/0000`) son la misma
  cosa en la práctica: el emisor no tenía el dato. Con `opcional: true` se
  leen como `nil`; sin eso, son un diagnóstico que lo explica.
  """

  @behaviour AnchoFijo.Tipo

  alias AnchoFijo.Campo
  alias AnchoFijo.Tipo
  alias AnchoFijo.Tipo.Patron
  alias AnchoFijo.Tipo.Patron.Validacion

  @impl true
  def opciones, do: [:formato, :pivote]

  @impl true
  def validar(campo) do
    Validacion.validar(campo, :fecha)
  end

  @impl true
  def leer(texto, %Campo{} = campo, contexto) do
    {:ok, patron} = Patron.compilar(campo.formato)

    if Patron.nulo?(patron, texto),
      do: vacia(campo, patron, texto, contexto),
      else: armar(campo, patron, texto, contexto)
  end

  defp vacia(%Campo{opcional: true}, _patron, _texto, _contexto), do: {:ok, nil}

  defp vacia(%Campo{} = campo, patron, texto, contexto) do
    {:error,
     Tipo.diagnostico(campo, contexto,
       esperado: "una fecha en formato #{patron.texto}",
       recibido: inspect(texto),
       causa_probable:
         "el emisor usa blancos o ceros para 'sin fecha'; declare opcional: true si es esperable"
     )}
  end

  defp armar(%Campo{} = campo, patron, texto, contexto) do
    with {:ok, partes} <- Patron.leer(patron, texto, campo.pivote),
         {:ok, fecha} <- a_date(partes) do
      {:ok, fecha}
    else
      {:error, causa} ->
        {:error,
         Tipo.diagnostico(campo, contexto,
           esperado: "una fecha válida en formato #{patron.texto}",
           recibido: inspect(texto),
           causa_probable: causa
         )}
    end
  end

  @doc false
  # Las partes leídas a un Date, con la causa de la fecha que no existe. Lo
  # usa también `Tipo.FechaHora`.
  @spec a_date(map()) :: {:ok, Date.t()} | {:error, String.t()}
  def a_date(%{anio: anio, dia_del_anio: dia}) do
    cond do
      anio == 0 ->
        {:error, "el año viene en cero"}

      dia < 1 ->
        {:error, "el día del año viene en cero"}

      dia > dias_del_anio(anio) ->
        {:error, "el día #{dia} no existe en el año #{anio}"}

      true ->
        {:ok, Date.add(Date.new!(anio, 1, 1), dia - 1)}
    end
  end

  # El mes y el día se revisan antes de `Date.new/3`, no después: la spec de
  # `Date.new/3` declara el mes en 1..12 y el día en 1..31, y dialyzer da por
  # imposible un mes 13 o un día 0 después de llamarla.
  def a_date(%{anio: anio, mes: mes, dia: dia}) do
    cond do
      mes < 1 or mes > 12 ->
        {:error, "el mes #{mes} no existe: puede que el formato sea el inverso"}

      dia < 1 ->
        {:error, "el día viene en cero"}

      true ->
        fecha(anio, mes, dia)
    end
  end

  defp fecha(anio, mes, dia) do
    case Date.new(anio, mes, dia) do
      {:ok, fecha} -> {:ok, fecha}
      {:error, _} when anio == 0 -> {:error, "el año viene en cero"}
      {:error, _} -> {:error, "el día no existe en ese mes"}
    end
  end

  defp dias_del_anio(anio), do: if(Date.leap_year?(Date.new!(anio, 1, 1)), do: 366, else: 365)

  @doc false
  @spec partes_de(Date.t()) :: map()
  def partes_de(%Date{} = fecha) do
    %{anio: fecha.year, mes: fecha.month, dia: fecha.day, dia_del_anio: Date.day_of_year(fecha)}
  end

  @impl true
  def escribir(%Date{} = fecha, %Campo{} = campo) do
    {:ok, patron} = Patron.compilar(campo.formato)
    Patron.escribir(patron, partes_de(fecha), campo.pivote)
  end

  def escribir(_otro, _campo), do: {:error, "se esperaba un Date"}
end

defmodule AnchoFijo.Tipo.Patron.Validacion do
  @moduledoc false
  # La validación de :formato, :pivote y :largo que comparten los tres tipos.

  alias AnchoFijo.Campo
  alias AnchoFijo.Tipo
  alias AnchoFijo.Tipo.Patron

  @spec validar(Campo.t(), :fecha | :hora | :fecha_hora) :: [AnchoFijo.Diagnostico.t()]
  def validar(%Campo{} = campo, tipo) do
    case Patron.compilar(campo.formato) do
      {:ok, patron} ->
        validar_partes(campo, patron, tipo) ++ validar_largo(campo, patron) ++ validar_pivote(campo)

      {:error, descripcion} ->
        [
          Tipo.falla(
            campo,
            ":formato con #{descripcion}, por ejemplo #{ejemplo(tipo)}",
            campo.formato,
            "el orden de #{nombre(tipo)} no se adivina: hay que declararlo"
          )
        ]
    end
  end

  defp validar_partes(campo, patron, :fecha) do
    cond do
      Patron.con_hora?(patron) ->
        [falla(campo, patron, "solo tokens de fecha; para fecha y hora, tipo: :fecha_hora")]

      not Patron.fecha?(patron) ->
        [falla(campo, patron, "año con mes y día, o año con día del año (DDD)")]

      true ->
        []
    end
  end

  defp validar_partes(campo, patron, :hora) do
    cond do
      Patron.con_fecha?(patron) ->
        [falla(campo, patron, "solo tokens de hora; para fecha y hora, tipo: :fecha_hora")]

      not Patron.hora?(patron) ->
        [falla(campo, patron, "hora y minuto (HHMM), y segundos si los hay")]

      true ->
        []
    end
  end

  defp validar_partes(campo, patron, :fecha_hora) do
    cond do
      not Patron.fecha?(patron) ->
        [falla(campo, patron, "una fecha completa además de la hora")]

      not Patron.hora?(patron) ->
        [
          falla(
            campo,
            patron,
            "hora y minuto además de la fecha; para una fecha sola, tipo: :fecha"
          )
        ]

      true ->
        []
    end
  end

  defp falla(campo, patron, esperado) do
    Tipo.falla(campo, "un :formato con #{esperado}", patron.texto, nil)
  end

  defp validar_largo(%Campo{largo: largo}, %{largo: minimo})
       when is_integer(largo) and largo >= minimo,
       do: []

  defp validar_largo(%Campo{largo: largo} = campo, patron) do
    [
      Tipo.falla(
        campo,
        "un :largo de al menos #{patron.largo} para el formato #{patron.texto}",
        largo,
        nil
      )
    ]
  end

  defp validar_pivote(%Campo{pivote: pivote})
       when is_nil(pivote) or (is_integer(pivote) and pivote > 0),
       do: []

  defp validar_pivote(%Campo{pivote: pivote} = campo) do
    [Tipo.falla(campo, "un :pivote entero, el primer año de la ventana de cien", pivote, nil)]
  end

  defp nombre(:fecha), do: "una fecha"
  defp nombre(:hora), do: "una hora"
  defp nombre(:fecha_hora), do: "una fecha y hora"

  defp ejemplo(:fecha), do: ":aaaammdd o \"DD/MM/AAAA\""
  defp ejemplo(:hora), do: ":hhmmss o \"HH:MM\""
  defp ejemplo(:fecha_hora), do: ":aaaammddhhmmss o \"AAAA-MM-DD HH:MM:SS\""
end
