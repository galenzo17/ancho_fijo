defmodule AnchoFijo.TipoHora do
  @moduledoc false
  # Un tipo de campo propio, definido fuera de la librería: una hora HHMM (o
  # HHMMSS con `segundos: true`) que se lee como `Time`. Existe para probar
  # que el behaviour alcanza para un tipo real con una opción propia.

  @behaviour AnchoFijo.Tipo

  alias AnchoFijo.Tipo

  @impl true
  def opciones, do: [:segundos]

  @impl true
  def validar(campo) do
    segundos? = Map.get(campo.opciones, :segundos, false)

    cond do
      not is_boolean(segundos?) ->
        [Tipo.falla(campo, ":segundos true o false", segundos?, nil)]

      campo.largo != if(segundos?, do: 6, else: 4) ->
        [
          Tipo.falla(
            campo,
            "un :largo de #{if segundos?, do: 6, else: 4} para la hora",
            campo.largo,
            nil
          )
        ]

      true ->
        []
    end
  end

  @impl true
  def leer("", campo, contexto), do: {:error, Tipo.vacio(campo, contexto)}

  def leer(texto, campo, contexto) do
    segundos? = Map.get(campo.opciones, :segundos, false)

    with true <- Tipo.solo_digitos?(texto),
         {:ok, hora, minuto, segundo} <- partes(texto, segundos?),
         {:ok, time} <- Time.new(hora, minuto, segundo) do
      {:ok, time}
    else
      _ ->
        {:error,
         Tipo.diagnostico(campo, contexto,
           esperado: "una hora #{if segundos?, do: "HHMMSS", else: "HHMM"}",
           recibido: inspect(texto),
           causa_probable: "hay caracteres no numéricos o la hora no existe"
         )}
    end
  end

  defp partes(<<h::binary-2, m::binary-2>>, false),
    do: {:ok, String.to_integer(h), String.to_integer(m), 0}

  defp partes(<<h::binary-2, m::binary-2, s::binary-2>>, true),
    do: {:ok, String.to_integer(h), String.to_integer(m), String.to_integer(s)}

  defp partes(_texto, _segundos?), do: :error

  # El inverso de leer/3: HHMM, o HHMMSS con `segundos: true`. Un valor que
  # no es un Time es la causa que Campo.formatear/3 va a poner en el
  # diagnóstico.
  @impl true
  def escribir(%Time{} = hora, campo) do
    formato = if Map.get(campo.opciones, :segundos, false), do: "%H%M%S", else: "%H%M"
    {:ok, Calendar.strftime(hora, formato)}
  end

  def escribir(_otro, _campo), do: {:error, "se esperaba un Time"}
end

defmodule AnchoFijo.TipoSoloLectura do
  @moduledoc false
  # Un tipo propio que no implementa escribir/2: se lee, no se escribe.
  @behaviour AnchoFijo.Tipo

  @impl true
  def opciones, do: []

  @impl true
  def validar(_campo), do: []

  @impl true
  def leer(texto, _campo, _contexto), do: {:ok, texto}
end

defmodule AnchoFijo.TipoAnchoEquivocado do
  @moduledoc false
  # Un escribir/2 que devuelve un texto de otro ancho que el del campo: el
  # bug más fácil de cometer en un tipo propio, y la librería tiene que
  # atajarlo antes de que la línea salga corrida.
  @behaviour AnchoFijo.Tipo

  @impl true
  def opciones, do: []

  @impl true
  def validar(_campo), do: []

  @impl true
  def leer(texto, _campo, _contexto), do: {:ok, texto}

  @impl true
  def escribir(valor, _campo), do: {:ok, valor <> "!"}
end

defmodule AnchoFijo.TipoIncompleto do
  @moduledoc false
  # Dice ser un tipo pero no implementa leer/3.
  def opciones, do: []
  def validar(_campo), do: []
end
