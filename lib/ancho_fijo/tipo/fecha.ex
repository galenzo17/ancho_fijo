defmodule AnchoFijo.Tipo.Fecha do
  @moduledoc """
  El tipo `:fecha`: ocho dígitos en el orden que `:formato` declara
  (`:aaaammdd` o `:ddmmaaaa`), leídos como `Date`.

  No hay default para `:formato` a propósito. Adivinar si `01022024` es el 1
  de febrero o el 2 de enero es justamente el error silencioso que esta
  librería existe para impedir: la definición tiene que decirlo.
  """

  @behaviour AnchoFijo.Tipo

  alias AnchoFijo.Campo
  alias AnchoFijo.Tipo

  @formatos [:aaaammdd, :ddmmaaaa]

  @impl true
  def opciones, do: [:formato]

  @impl true
  def validar(campo), do: validar_formato(campo) ++ validar_largo(campo)

  defp validar_formato(%Campo{formato: formato}) when formato in @formatos, do: []

  defp validar_formato(%Campo{formato: formato} = campo) do
    [
      Tipo.falla(
        campo,
        ":formato en #{inspect(@formatos)}",
        formato,
        "el orden de una fecha no se adivina: hay que declararlo"
      )
    ]
  end

  defp validar_largo(%Campo{largo: largo}) when is_integer(largo) and largo >= 8, do: []

  defp validar_largo(%Campo{largo: largo} = campo) do
    [Tipo.falla(campo, "un :largo de al menos 8 para una fecha", largo, nil)]
  end

  # Un campo :fecha en blanco y uno en ceros son la misma cosa en la práctica:
  # el sistema emisor no tenía el dato. Los formatos bancarios usan ambos.
  @impl true
  def leer(texto, campo, contexto) do
    if nula?(texto), do: vacia(campo, texto, contexto), else: armar(campo, texto, contexto)
  end

  # Un campo :fecha en blanco y uno en ceros son la misma cosa en la práctica:
  # el sistema emisor no tenía el dato. Los formatos bancarios usan ambos.
  defp nula?(""), do: true
  defp nula?(texto), do: solo_el_byte?(texto, ?0)

  defp solo_el_byte?(<<byte, resto::binary>>, byte), do: solo_el_byte?(resto, byte)
  defp solo_el_byte?("", _byte), do: true
  defp solo_el_byte?(_otro, _byte), do: false

  defp vacia(%Campo{opcional: true}, _texto, _contexto), do: {:ok, nil}

  defp vacia(%Campo{} = campo, texto, contexto) do
    {:error,
     Tipo.diagnostico(campo, contexto,
       esperado: "una fecha en formato #{descripcion(campo.formato)}",
       recibido: inspect(texto),
       causa_probable:
         "el emisor usa blancos o ceros para 'sin fecha'; declare opcional: true si es esperable"
     )}
  end

  defp armar(%Campo{} = campo, texto, contexto) do
    with 8 <- String.length(texto),
         {:ok, anio, mes, dia} <- desarmar(texto, campo.formato),
         {:ok, fecha} <- Date.new(anio, mes, dia) do
      {:ok, fecha}
    else
      _invalida -> {:error, error(campo, texto, contexto)}
    end
  end

  defp desarmar(texto, :aaaammdd) do
    with {:ok, anio} <- tramo(texto, 0, 4),
         {:ok, mes} <- tramo(texto, 4, 2),
         {:ok, dia} <- tramo(texto, 6, 2),
         do: {:ok, anio, mes, dia}
  end

  defp desarmar(texto, :ddmmaaaa) do
    with {:ok, dia} <- tramo(texto, 0, 2),
         {:ok, mes} <- tramo(texto, 2, 2),
         {:ok, anio} <- tramo(texto, 4, 4),
         do: {:ok, anio, mes, dia}
  end

  defp tramo(texto, desde, largo) do
    case Integer.parse(binary_part(texto, desde, largo)) do
      {numero, ""} -> {:ok, numero}
      _no_numerico -> :error
    end
  end

  defp error(%Campo{} = campo, texto, contexto) do
    Tipo.diagnostico(campo, contexto,
      esperado: "una fecha válida en formato #{descripcion(campo.formato)}",
      recibido: inspect(texto),
      causa_probable: causa(texto, campo.formato)
    )
  end

  defp causa(texto, formato) do
    if String.length(texto) == 8 and Regex.match?(~r/\A\d{8}\z/, texto) do
      causa_numerica(texto, formato)
    else
      "se esperaban 8 dígitos; el campo puede estar corrido o traer separadores"
    end
  end

  defp causa_numerica(texto, formato) do
    {:ok, anio, mes, dia} = desarmar(texto, formato)

    cond do
      mes < 1 or mes > 12 -> "el mes #{mes} no existe: puede que el formato sea el inverso"
      dia < 1 -> "el día viene en cero"
      anio == 0 -> "el año viene en cero"
      true -> "el día no existe en ese mes"
    end
  end

  defp descripcion(:aaaammdd), do: "AAAAMMDD"
  defp descripcion(:ddmmaaaa), do: "DDMMAAAA"
  defp descripcion(otro), do: inspect(otro)
end
