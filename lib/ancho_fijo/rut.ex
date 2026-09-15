defmodule AnchoFijo.Rut do
  @moduledoc """
  RUT chileno: normalización a la forma canónica y validación del dígito
  verificador.

  Un RUT es un cuerpo numérico y un dígito verificador (DV) calculado con
  módulo 11, del `0` al `9` o `K`. Las nóminas lo traen de todas las formas:
  `12345678-5`, `123456785`, `12.345.678-5`, `0000123456785`, con `k` o `K`.
  Este módulo lleva cualquiera de ellas a `"12345678-5"`.

      iex> AnchoFijo.Rut.normalizar("12.345.678-5")
      {:ok, "12345678-5"}

      iex> AnchoFijo.Rut.normalizar("0000123456785")
      {:ok, "12345678-5"}

      iex> AnchoFijo.Rut.normalizar("12345678-9")
      {:error, {:dv, "5", "9"}}

  ## La validación es parte del tipo

  Un RUT con el DV malo es exactamente el error silencioso que esta librería
  existe para impedir: el archivo parsea, y el banco lo rechaza días después.
  Por eso el default valida. Hay dos salidas explícitas para los formatos que
  no lo permiten:

    * `:no_validar` — el campo trae DV pero el emisor no lo garantiza y quien
      procesa prefiere recibir el dato y decidir después.
    * `:ausente` — el campo trae solo el cuerpo, sin DV. Se normaliza a los
      dígitos sin ceros a la izquierda, `"12345678"`, y no hay nada que
      validar.
  """

  @typedoc "Qué hacer con el dígito verificador."
  @type dv :: :validar | :no_validar | :ausente

  @typedoc """
  Por qué un texto no es un RUT: el formato no calza, o el DV no cuadra. En el
  segundo caso vienen el DV que correspondía y el que llegó.
  """
  @type motivo :: {:formato, String.t()} | {:dv, String.t(), String.t()}

  @modos [:validar, :no_validar, :ausente]

  @doc """
  Modos aceptados para el dígito verificador.

      iex> AnchoFijo.Rut.modos()
      [:validar, :no_validar, :ausente]
  """
  @spec modos() :: [dv()]
  def modos, do: @modos

  @doc """
  Normaliza un RUT a `"cuerpo-DV"`, sin puntos ni ceros a la izquierda y con
  la `K` en mayúscula.

      iex> AnchoFijo.Rut.normalizar("010000013k")
      {:ok, "10000013-K"}

      iex> AnchoFijo.Rut.normalizar("12345678", :ausente)
      {:ok, "12345678"}

      iex> AnchoFijo.Rut.normalizar("12345678-9", :no_validar)
      {:ok, "12345678-9"}

      iex> AnchoFijo.Rut.normalizar("1234567A-9")
      {:error, {:formato, "se esperaban dígitos, opcionalmente con puntos y guion, y un DV del 0 al 9 o K"}}
  """
  @spec normalizar(String.t(), dv()) :: {:ok, String.t()} | {:error, motivo()}
  def normalizar(texto, modo \\ :validar)

  def normalizar(texto, :ausente) when is_binary(texto) do
    with {:ok, cuerpo} <- cuerpo(limpiar(texto)) do
      {:ok, Integer.to_string(cuerpo)}
    end
  end

  def normalizar(texto, modo) when is_binary(texto) and modo in [:validar, :no_validar] do
    with {:ok, digitos, dv} <- separar(limpiar(texto)),
         {:ok, cuerpo} <- cuerpo(digitos),
         :ok <- verificar(cuerpo, dv, modo) do
      {:ok, "#{cuerpo}-#{dv}"}
    end
  end

  @doc """
  Si el texto es un RUT con dígito verificador válido.

      iex> AnchoFijo.Rut.valido?("12.345.678-5")
      true

      iex> AnchoFijo.Rut.valido?("12.345.678-9")
      false
  """
  @spec valido?(String.t()) :: boolean()
  def valido?(texto) when is_binary(texto), do: match?({:ok, _}, normalizar(texto))

  @doc """
  Dígito verificador de un cuerpo de RUT, por módulo 11: `"0"` a `"9"` o `"K"`.

      iex> AnchoFijo.Rut.digito_verificador(12_345_678)
      "5"

      iex> AnchoFijo.Rut.digito_verificador(10_000_013)
      "K"

      iex> AnchoFijo.Rut.digito_verificador(10_000_004)
      "0"
  """
  @spec digito_verificador(pos_integer()) :: String.t()
  # Módulo 11 tal como lo publica el Registro Civil: los dígitos de derecha a
  # izquierda, multiplicados por la serie 2..7 que vuelve a empezar, y
  # 11 - (suma rem 11), donde 11 es "0" y 10 es "K". Con 12345678:
  # 8*2 + 7*3 + 6*4 + 5*5 + 4*6 + 3*7 + 2*2 + 1*3 = 138, 138 rem 11 = 6, DV 5.
  def digito_verificador(cuerpo) when is_integer(cuerpo) and cuerpo > 0 do
    suma =
      cuerpo
      |> Integer.digits()
      |> Enum.reverse()
      |> Enum.zip_reduce(Stream.cycle(2..7), 0, fn digito, factor, acumulado ->
        acumulado + digito * factor
      end)

    case 11 - rem(suma, 11) do
      11 -> "0"
      10 -> "K"
      resto -> Integer.to_string(resto)
    end
  end

  defp limpiar(texto), do: texto |> String.trim() |> String.replace(".", "")

  # El guion es opcional porque la mitad de los formatos no lo trae. Los
  # puntos ya se quitaron. La `k` minúscula se acepta porque aparece en
  # archivos reales y no hay ambigüedad posible.
  defp separar(limpio) do
    case Regex.run(~r/\A(\d+)-?([0-9kK])\z/, limpio) do
      [_todo, digitos, dv] -> {:ok, digitos, String.upcase(dv)}
      nil -> {:error, {:formato, descripcion_formato()}}
    end
  end

  defp cuerpo(digitos) do
    case Integer.parse(digitos) do
      {0, ""} -> {:error, {:formato, "el cuerpo del RUT es cero"}}
      {cuerpo, ""} when cuerpo > 0 -> {:ok, cuerpo}
      _otra_cosa -> {:error, {:formato, descripcion_formato()}}
    end
  end

  defp verificar(_cuerpo, _dv, :no_validar), do: :ok

  defp verificar(cuerpo, dv, :validar) do
    case digito_verificador(cuerpo) do
      ^dv -> :ok
      esperado -> {:error, {:dv, esperado, dv}}
    end
  end

  defp descripcion_formato do
    "se esperaban dígitos, opcionalmente con puntos y guion, y un DV del 0 al 9 o K"
  end
end
