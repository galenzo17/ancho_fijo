defmodule AnchoFijo.Tipo.Decimal do
  @moduledoc """
  El tipo `:decimal`: un monto como `{unidades_minimas, precision}`, nunca un
  float. `:precision` es obligatoria; `:separador` dice si los decimales son
  implícitos (`0000125000` para 1.250,00) o vienen con punto o coma.
  """

  @behaviour AnchoFijo.Tipo

  alias AnchoFijo.Campo
  alias AnchoFijo.Tipo
  alias AnchoFijo.Tipo.Signo

  @separadores [:implicito, :punto, :coma]

  @impl true
  def opciones, do: [:precision, :separador, :signo]

  @impl true
  def validar(campo) do
    validar_precision(campo) ++ validar_separador(campo) ++ Signo.validar(campo)
  end

  defp validar_precision(%Campo{precision: precision})
       when is_integer(precision) and precision >= 0,
       do: []

  defp validar_precision(%Campo{precision: precision} = campo) do
    [
      Tipo.falla(
        campo,
        ":precision declarada para un campo :decimal",
        precision,
        "sin precisión no se sabe si 1234 son 12,34 o 1234,00"
      )
    ]
  end

  defp validar_separador(%Campo{separador: separador}) when separador in @separadores, do: []

  defp validar_separador(%Campo{separador: separador} = campo) do
    [Tipo.falla(campo, ":separador en #{inspect(@separadores)}", separador, nil)]
  end

  @impl true
  def leer("", campo, contexto), do: {:error, Tipo.vacio(campo, contexto)}

  def leer(texto, campo, contexto) do
    with {:ok, signo, digitos} <- Signo.separar(texto, campo),
         {:ok, unidades} <- unidades(digitos, campo) do
      {:ok, {signo * unidades, campo.precision}}
    else
      {:error, {:exceso, fraccion}} -> {:error, exceso_de_decimales(campo, fraccion, contexto)}
      {:error, :formato} -> {:error, error_decimal(campo, texto, contexto)}
      {:error, causa} -> {:error, Signo.error(campo, texto, causa, contexto)}
    end
  end

  # Con separador implícito el campo entero ya viene en unidades mínimas: el
  # anexo dice "10 posiciones, 2 decimales" y el archivo trae 0000125000 para
  # 1.250,00. Escalarlo otra vez multiplicaría los montos por cien, que es la
  # clase de error que nadie nota hasta el cierre de mes.
  defp unidades(digitos, %Campo{separador: :implicito}) do
    if Tipo.solo_digitos?(digitos), do: {:ok, String.to_integer(digitos)}, else: {:error, :formato}
  end

  defp unidades(digitos, %Campo{separador: separador, precision: precision}) do
    case String.split(digitos, caracter(separador)) do
      [entera] -> escalar(entera, "", precision)
      [entera, fraccion] -> escalar(entera, fraccion, precision)
      _varios -> {:error, :formato}
    end
  end

  defp caracter(:punto), do: "."
  defp caracter(:coma), do: ","

  defp escalar(entera, fraccion, precision) do
    entera = if entera == "", do: "0", else: entera

    cond do
      not Tipo.solo_digitos?(entera) -> {:error, :formato}
      fraccion != "" and not Tipo.solo_digitos?(fraccion) -> {:error, :formato}
      String.length(fraccion) > precision -> {:error, {:exceso, fraccion}}
      true -> {:ok, String.to_integer(entera <> String.pad_trailing(fraccion, precision, "0"))}
    end
  end

  defp exceso_de_decimales(%Campo{precision: precision} = campo, fraccion, contexto) do
    Tipo.diagnostico(campo, contexto,
      esperado: "a lo más #{precision} decimales",
      recibido: "#{String.length(fraccion)} (#{inspect(fraccion)})",
      causa_probable: "la precisión declarada en el layout es menor que la del archivo"
    )
  end

  defp error_decimal(%Campo{} = campo, texto, contexto) do
    Tipo.diagnostico(campo, contexto,
      esperado: descripcion(campo),
      recibido: inspect(texto),
      causa_probable: causa(campo.separador)
    )
  end

  defp descripcion(%Campo{separador: :implicito, largo: largo, precision: precision}) do
    "#{largo} dígitos con #{precision} decimales implícitos"
  end

  defp descripcion(%Campo{separador: separador, precision: precision}) do
    "un número con #{separador} decimal y a lo más #{precision} decimales"
  end

  defp causa(:implicito) do
    "el monto trae un separador decimal explícito o un carácter no numérico; " <>
      "si el archivo usa punto o coma, declare separador: :punto o :coma"
  end

  defp causa(_separador), do: "hay caracteres no numéricos o más de un separador"
end
