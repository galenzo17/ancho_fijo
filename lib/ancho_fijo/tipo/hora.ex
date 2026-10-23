defmodule AnchoFijo.Tipo.Hora do
  @moduledoc """
  El tipo `:hora`: una hora del día leída como `Time`, en el orden que
  `:formato` declara.

  | `:formato` | ejemplo | lee |
  | --- | --- | --- |
  | `:hhmmss` | `093015` | 09:30:15 |
  | `:hhmm` | `0930` | 09:30:00 |
  | `"HH:MM:SS"` | `09:30:15` | 09:30:15 (patrón explícito) |

  Un patrón tiene hora y minuto, y segundos si el archivo los trae. Un
  campo en blanco es "sin hora": `nil` con `opcional: true`, un diagnóstico
  sin eso. Los ceros **no**: `0000` es la medianoche, una hora que existe,
  y se lee como `~T[00:00:00]`. Es la diferencia con `:fecha`, donde
  `00000000` no puede ser una fecha. Una hora que no existe (`2460`) es un
  diagnóstico con la parte que falla.
  """

  @behaviour AnchoFijo.Tipo

  alias AnchoFijo.Campo
  alias AnchoFijo.Tipo
  alias AnchoFijo.Tipo.Patron
  alias AnchoFijo.Tipo.Patron.Validacion

  @impl true
  def opciones, do: [:formato]

  @impl true
  def validar(campo), do: Validacion.validar(campo, :hora)

  @impl true
  def leer(texto, %Campo{} = campo, contexto) do
    {:ok, patron} = Patron.compilar(campo.formato)

    if texto == "",
      do: vacia(campo, patron, texto, contexto),
      else: armar(campo, patron, texto, contexto)
  end

  defp vacia(%Campo{opcional: true}, _patron, _texto, _contexto), do: {:ok, nil}

  defp vacia(%Campo{} = campo, patron, texto, contexto) do
    {:error,
     Tipo.diagnostico(campo, contexto,
       esperado: "una hora en formato #{patron.texto}",
       recibido: inspect(texto),
       causa_probable:
         "el emisor usa blancos para 'sin hora'; declare opcional: true si es esperable"
     )}
  end

  defp armar(%Campo{} = campo, patron, texto, contexto) do
    with {:ok, partes} <- Patron.leer(patron, texto, nil),
         {:ok, hora} <- a_time(partes) do
      {:ok, hora}
    else
      {:error, causa} ->
        {:error,
         Tipo.diagnostico(campo, contexto,
           esperado: "una hora válida en formato #{patron.texto}",
           recibido: inspect(texto),
           causa_probable: causa
         )}
    end
  end

  @doc false
  # Las partes leídas a un Time, con la causa de la hora que no existe. Lo
  # usa también `Tipo.FechaHora`.
  @spec a_time(map()) :: {:ok, Time.t()} | {:error, String.t()}
  def a_time(partes) do
    hora = Map.fetch!(partes, :hora)
    minuto = Map.fetch!(partes, :minuto)
    segundo = Map.get(partes, :segundo, 0)

    case Time.new(hora, minuto, segundo) do
      {:ok, time} ->
        {:ok, time}

      {:error, _} ->
        cond do
          hora > 23 -> {:error, "la hora #{hora} no existe: el día tiene 24"}
          minuto > 59 -> {:error, "el minuto #{minuto} no existe"}
          true -> {:error, "el segundo #{segundo} no existe"}
        end
    end
  end

  @doc false
  @spec partes_de(Time.t()) :: map()
  def partes_de(%Time{} = hora), do: %{hora: hora.hour, minuto: hora.minute, segundo: hora.second}

  @impl true
  def escribir(%Time{} = hora, %Campo{} = campo) do
    {:ok, patron} = Patron.compilar(campo.formato)
    Patron.escribir(patron, partes_de(hora), nil)
  end

  def escribir(_otro, _campo), do: {:error, "se esperaba un Time"}
end
