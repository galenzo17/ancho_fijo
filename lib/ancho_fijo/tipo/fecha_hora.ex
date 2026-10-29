defmodule AnchoFijo.Tipo.FechaHora do
  @moduledoc """
  El tipo `:fecha_hora`: fecha y hora en un solo campo, leídas como
  `NaiveDateTime`. Sin zona horaria: un archivo de ancho fijo no la trae, y
  ponerle una sería inventar un dato.

  | `:formato` | ejemplo | lee |
  | --- | --- | --- |
  | `:aaaammddhhmmss` | `20240131093015` | 2024-01-31 09:30:15 |
  | `:aaaammddhhmm` | `202401310930` | 2024-01-31 09:30:00 |
  | `:ddmmaaaahhmmss` | `31012024093015` | 2024-01-31 09:30:15 |
  | `:ddmmaaaahhmm` | `310120240930` | 2024-01-31 09:30:00 |
  | `"AAAA-MM-DD HH:MM:SS"` | `2024-01-31 09:30:15` | 2024-01-31 09:30:15 (patrón explícito) |

  Los tokens, el `:pivote` para años de dos dígitos y la política de blancos
  y ceros son los de `AnchoFijo.Tipo.Fecha` y `AnchoFijo.Tipo.Hora`. Un `MM`
  después de `HH` es minuto; antes, mes.
  """

  @behaviour AnchoFijo.Tipo

  alias AnchoFijo.Campo
  alias AnchoFijo.Tipo
  alias AnchoFijo.Tipo.Fecha
  alias AnchoFijo.Tipo.Hora
  alias AnchoFijo.Tipo.Patron
  alias AnchoFijo.Tipo.Patron.Validacion

  @impl true
  def opciones, do: [:formato, :pivote]

  @impl true
  def validar(campo), do: Validacion.validar(campo, :fecha_hora)

  @impl true
  def leer(texto, %Campo{} = campo, contexto) do
    patron = Patron.de(campo)

    case Patron.leer_o_nulo(patron, texto, campo.pivote) do
      :nulo -> vacia(campo, patron, texto, contexto)
      resultado -> armar(campo, patron, texto, contexto, resultado)
    end
  end

  defp vacia(%Campo{opcional: true}, _patron, _texto, _contexto), do: {:ok, nil}

  defp vacia(%Campo{} = campo, patron, texto, contexto) do
    {:error,
     Tipo.diagnostico(campo, contexto,
       esperado: "una fecha y hora en formato #{patron.texto}",
       recibido: inspect(texto),
       causa_probable:
         "el emisor usa blancos o ceros para 'sin dato'; declare opcional: true si es esperable"
     )}
  end

  defp armar(%Campo{} = campo, patron, texto, contexto, leido) do
    with {:ok, partes} <- leido,
         {:ok, fecha} <- Fecha.a_date(partes),
         {:ok, hora} <- Hora.a_time(partes) do
      NaiveDateTime.new(fecha, hora)
    else
      {:error, causa} ->
        {:error,
         Tipo.diagnostico(campo, contexto,
           esperado: "una fecha y hora válidas en formato #{patron.texto}",
           recibido: inspect(texto),
           causa_probable: causa
         )}
    end
  end

  @impl true
  def escribir(%NaiveDateTime{} = valor, %Campo{} = campo) do
    patron = Patron.de(campo)

    partes =
      Map.merge(
        Fecha.partes_de(NaiveDateTime.to_date(valor)),
        Hora.partes_de(NaiveDateTime.to_time(valor))
      )

    Patron.escribir(patron, partes, campo.pivote)
  end

  def escribir(_otro, _campo), do: {:error, "se esperaba un NaiveDateTime"}
end
