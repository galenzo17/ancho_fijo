defmodule AnchoFijo.Tipo.Decimal do
  @moduledoc """
  El tipo `:decimal`: un monto como `{unidades_minimas, precision}`, nunca un
  float. `:precision` es obligatoria; `:separador` dice si los decimales son
  implícitos (`0000125000` para 1.250,00) o vienen con punto o coma. Con
  `:moneda`, el valor es un `AnchoFijo.Monto` y la precisión es la escala
  ISO 4217 de la moneda.

  ## Si ya usa `Decimal`

  Con `como: :decimal` en el campo (o `decimales_como: :decimal` en el
  layout, para todos), el valor leído es un `%Decimal{}` con la escala del
  campo, y hace falta tener `{:decimal, "~> 2.0 or ~> 3.0"}` en el proyecto:
  sin la librería, el layout es inválido y el diagnóstico lo dice. Al
  escribir, un campo `:decimal` acepta siempre un `%Decimal{}`, un entero
  (en unidades enteras: `1250` es 1.250,00) o un string numérico
  (`"1250.50"`, que necesita `Decimal` para leerse), además de la tupla y
  del `Monto`. Un valor con más decimales que `:precision` es un
  diagnóstico, nunca un redondeo.
  """

  @behaviour AnchoFijo.Tipo
  @compile {:no_warn_undefined, Decimal}

  alias AnchoFijo.Campo
  alias AnchoFijo.Monto
  alias AnchoFijo.Tipo
  alias AnchoFijo.Tipo.Signo

  @separadores [:implicito, :punto, :coma]

  @impl true
  def opciones, do: [:precision, :separador, :moneda, :signo, :como]

  # Con moneda, la precisión la valida `validar_moneda/1`: reclamarla dos
  # veces no ayuda a nadie.
  @impl true
  def validar(%Campo{moneda: nil} = campo) do
    validar_precision(campo) ++
      validar_separador(campo) ++
      Signo.validar(campo) ++
      validar_como(campo)
  end

  def validar(campo) do
    validar_moneda(campo) ++
      validar_separador(campo) ++
      Signo.validar(campo) ++
      validar_como(campo)
  end

  defp validar_como(%Campo{como: nil}), do: []

  defp validar_como(%Campo{como: :decimal} = campo) do
    if decimal_disponible?() do
      []
    else
      [
        Tipo.falla(
          campo,
          "la librería Decimal disponible, porque el campo declara como: :decimal",
          "un proyecto sin Decimal",
          "agregue {:decimal, \"~> 2.0 or ~> 3.0\"} a las dependencias, o quite como: :decimal " <>
            "para leer {unidades, precision}"
        )
      ]
    end
  end

  defp validar_como(%Campo{como: otro} = campo) do
    [Tipo.falla(campo, "como: :decimal, o ninguno para leer {unidades, precision}", otro, nil)]
  end

  @doc "Si la librería `Decimal` está cargada en este proyecto."
  @spec decimal_disponible?() :: boolean()
  def decimal_disponible?, do: Code.ensure_loaded?(Decimal)

  # La escala no es una preferencia del layout: es una propiedad de la
  # moneda. Un `moneda: :clp` con `precision: 2` lee pesos chilenos divididos
  # por cien, y nadie se entera hasta la conciliación.
  defp validar_moneda(%Campo{moneda: moneda, precision: precision} = campo) do
    case Monto.escala(moneda) do
      {:ok, ^precision} ->
        []

      {:ok, escala} ->
        [
          Tipo.falla(
            campo,
            "precision: #{escala} para #{Monto.codigo(moneda)}, que es su escala ISO 4217",
            precision,
            causa_de_escala(moneda, escala)
          )
        ]

      :error when is_integer(precision) ->
        # Se valida la precisión como siempre; la moneda queda sin verificar y
        # el layout lo avisa. Un layout con advertencias se construye igual.
        []

      :error ->
        [
          Tipo.falla(
            campo,
            "una :moneda de la tabla ISO 4217 de AnchoFijo.Monto, o :precision explícita",
            moneda,
            "la moneda no está en la tabla y sin :precision no se sabe la escala"
          )
        ]
    end
  end

  defp causa_de_escala(moneda, 0) do
    "#{Monto.codigo(moneda)} no tiene decimales: leer el campo con decimales implícitos " <>
      "dividiría los montos; si el archivo trae decimales de verdad, no es #{Monto.codigo(moneda)}"
  end

  defp causa_de_escala(moneda, escala) do
    "#{Monto.codigo(moneda)} tiene #{escala} decimales; con otra precisión los montos " <>
      "quedan escalados mal"
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
      {:ok, valor(signo * unidades, campo)}
    else
      {:error, {:exceso, fraccion}} -> {:error, exceso_de_decimales(campo, fraccion, contexto)}
      {:error, :formato} -> {:error, error_decimal(campo, texto, contexto)}
      {:error, causa} -> {:error, Signo.error(campo, texto, causa, contexto)}
    end
  end

  # El valor del campo a partir de las unidades mínimas: la tupla, el
  # `%Decimal{}` con `como: :decimal` o el `Monto` con moneda. Es lo que
  # `leer/3` devuelve y lo que `Campo.canonico/2` lleva a las reglas al
  # escribir.
  @doc false
  @spec valor(integer(), Campo.t()) :: Campo.valor()
  def valor(unidades, %Campo{como: :decimal, precision: precision}),
    do: Decimal.new(if(unidades < 0, do: -1, else: 1), abs(unidades), -precision)

  def valor(unidades, %Campo{moneda: nil, precision: precision}), do: {unidades, precision}

  def valor(unidades, %Campo{moneda: moneda, precision: precision}),
    do: Monto.nuevo(unidades, precision, moneda)

  @doc """
  Convierte lo que se puede escribir en un campo `:decimal` a unidades
  mínimas: un `%Decimal{}`, un entero (unidades enteras) o un string
  numérico. `{:error, causa}` si tiene más decimales que la precisión del
  campo, no es un número, o hace falta `Decimal` y no está.

      iex> campo = AnchoFijo.Campo.nuevo!(nombre: :m, largo: 8, tipo: :decimal, precision: 2)
      iex> AnchoFijo.Tipo.Decimal.a_unidades(Decimal.new("1250.5"), campo)
      {:ok, 125_050}
      iex> AnchoFijo.Tipo.Decimal.a_unidades(1250, campo)
      {:ok, 125_000}
      iex> AnchoFijo.Tipo.Decimal.a_unidades("-12.345", campo)
      {:error, "el valor tiene más decimales que la precisión del campo (2); escalar o redondear acá es donde se pierde el peso, convierta antes"}
  """
  @spec a_unidades(term(), Campo.t()) :: {:ok, integer()} | {:error, String.t()}
  def a_unidades(valor, %Campo{precision: precision}) when is_integer(valor),
    do: {:ok, valor * Integer.pow(10, precision)}

  def a_unidades(valor, %Campo{} = campo) when is_binary(valor) do
    if decimal_disponible?() do
      case Decimal.parse(valor) do
        {decimal, ""} -> a_unidades(decimal, campo)
        _otro -> {:error, "el string no es un número decimal"}
      end
    else
      {:error,
       "un string numérico se lee con la librería Decimal, que no está disponible; " <>
         "pase {unidades, precision} o un entero"}
    end
  end

  def a_unidades(%{__struct__: Decimal} = decimal, %Campo{precision: precision}) do
    if Decimal.nan?(decimal) or Decimal.inf?(decimal) do
      {:error, "NaN o infinito no son un monto"}
    else
      escalado = Decimal.mult(decimal, Decimal.new(Integer.pow(10, precision)))

      if Decimal.integer?(escalado),
        do: {:ok, Decimal.to_integer(escalado)},
        else:
          {:error,
           "el valor tiene más decimales que la precisión del campo (#{precision}); " <>
             "escalar o redondear acá es donde se pierde el peso, convierta antes"}
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
