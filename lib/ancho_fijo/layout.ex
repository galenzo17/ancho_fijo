defmodule AnchoFijo.Layout do
  @moduledoc """
  La definición del formato, como data.

  Un layout es una lista de campos más tres decisiones globales: en qué encoding
  viene el archivo, si las posiciones se cuentan en bytes o en caracteres, y qué
  largo total se espera por línea. Cambiar de formato es cambiar este mapa, no
  escribir código.

      iex> alias AnchoFijo.Layout
      iex> {:ok, layout} = Layout.nuevo(
      ...>   nombre: "nómina banco X",
      ...>   encoding: :latin1,
      ...>   campos: [
      ...>     [nombre: :rut, largo: 10],
      ...>     [nombre: :beneficiario, largo: 30],
      ...>     [nombre: :monto, largo: 12, tipo: :decimal, precision: 2]
      ...>   ]
      ...> )
      iex> Layout.largo(layout)
      52

  Las posiciones son 1-based porque así vienen en todas las especificaciones
  bancarias del mundo: cuando el anexo dice "posiciones 21 a 32", el layout dice
  lo mismo. Si se omiten, cada campo se encadena al anterior.

  ## Validación de la definición misma

  `nuevo/1` revisa el layout antes de ver un archivo. Distingue dos gravedades,
  y la distinción es de dominio: un solapamiento es siempre un error de
  transcripción del anexo, mientras que un hueco suele ser una zona reservada
  legítima del formato. Los huecos quedan en `:advertencias` y no impiden
  parsear.

      iex> alias AnchoFijo.Layout
      iex> {:error, [diagnostico]} = Layout.nuevo(campos: [
      ...>   [nombre: :rut, posicion: 1, largo: 10],
      ...>   [nombre: :nombre, posicion: 8, largo: 20]
      ...> ])
      iex> AnchoFijo.Diagnostico.mensaje(diagnostico)
      "layout, campo :nombre (posiciones 8-27): se esperaba que empezara en la posición 11 o después, llegó 8; se solapa con el campo :rut (posiciones 1-10)"

      iex> alias AnchoFijo.Layout
      iex> {:ok, layout} = Layout.nuevo(campos: [
      ...>   [nombre: :rut, posicion: 1, largo: 10],
      ...>   [nombre: :nombre, posicion: 14, largo: 20]
      ...> ])
      iex> AnchoFijo.Diagnostico.mensaje(hd(layout.advertencias))
      "layout, campo :nombre (posiciones 14-33): se esperaba que empezara en la posición 11, llegó 14; quedan 3 posiciones sin declarar entre :rut y :nombre; si el formato tiene relleno ahí, ignore esta advertencia"

  ## Opciones

    * `:campos` — obligatorio. Lista de definiciones de `AnchoFijo.Campo`
      (keyword lists, mapas o structs ya construidos).
    * `:encoding` — `:utf8` (default) o `:latin1`.
    * `:unidad` — `:bytes` (default) o `:caracteres`. Ver más abajo.
    * `:largo` — largo total esperado por línea. Si se omite, se infiere del
      último campo.
    * `:nombre` — etiqueta libre para identificar el layout en logs.

  ## Bytes o caracteres

  El default es `:bytes` porque un formato de ancho fijo se define sobre el
  archivo físico: cuando el banco dice "120 posiciones", cuenta bytes. Con
  latin-1 da lo mismo, un byte es un carácter. Con UTF-8 no: si el archivo trae
  acentos y el emisor contó caracteres, hay que declarar `unidad: :caracteres` o
  cada línea con una "ñ" se corre un byte.
  """

  alias AnchoFijo.Campo
  alias AnchoFijo.Diagnostico

  @encodings [:utf8, :latin1]
  @unidades [:bytes, :caracteres]

  @type t :: %__MODULE__{
          nombre: String.t() | nil,
          campos: [Campo.t()],
          largo: pos_integer(),
          encoding: :utf8 | :latin1,
          unidad: :bytes | :caracteres,
          advertencias: [Diagnostico.t()]
        }

  defstruct nombre: nil,
            campos: [],
            largo: nil,
            encoding: :utf8,
            unidad: :bytes,
            advertencias: []

  @doc """
  Valida y construye un layout.

  Devuelve `{:ok, layout}` —posiblemente con `:advertencias`— o
  `{:error, diagnosticos}` con todos los problemas encontrados, no solo el
  primero: corregir una definición de 40 campos de a un error por compilación es
  una forma lenta de perder el día.

      iex> {:ok, layout} = AnchoFijo.Layout.nuevo(campos: [[nombre: :codigo, largo: 4, tipo: :entero]])
      iex> layout.largo
      4

      iex> {:error, [diagnostico]} = AnchoFijo.Layout.nuevo(campos: [])
      iex> AnchoFijo.Diagnostico.mensaje(diagnostico)
      "layout: se esperaba al menos un campo en :campos, llegó una lista vacía; un layout sin campos no puede leer nada"
  """
  @spec nuevo(Enumerable.t()) :: {:ok, t()} | {:error, [Diagnostico.t()]}
  def nuevo(atributos) do
    atributos = Map.new(atributos)

    with {:ok, globales} <- validar_globales(atributos),
         {:ok, campos} <- construir_campos(Map.get(atributos, :campos, [])),
         campos = posicionar(campos),
         :ok <- validar_disposicion(campos),
         {:ok, largo, advertencias} <- resolver_largo(campos, globales, atributos) do
      {:ok,
       struct(
         %__MODULE__{},
         Map.merge(globales, %{campos: campos, largo: largo, advertencias: advertencias})
       )}
    end
  end

  @doc """
  Igual que `nuevo/1` pero levanta `AnchoFijo.Error` con el reporte completo.

      iex> AnchoFijo.Layout.nuevo!(campos: [[nombre: :a, largo: 2]]).unidad
      :bytes

      iex> AnchoFijo.Layout.nuevo!(campos: [[nombre: :a, largo: 0]])
      ** (AnchoFijo.Error) layout, campo :a: se esperaba un :largo entero mayor que cero, llegó 0; revise la especificación del formato
  """
  @spec nuevo!(Enumerable.t()) :: t()
  def nuevo!(atributos) do
    case nuevo(atributos) do
      {:ok, layout} -> layout
      {:error, diagnosticos} -> raise AnchoFijo.Error, diagnosticos
    end
  end

  @doc """
  Acepta un layout ya construido o una definición y devuelve siempre `{:ok, layout}`.

  Es lo que usan `AnchoFijo.parsear/3` y `AnchoFijo.stream/3` para que el
  llamador pueda pasar la definición en línea sin ceremonia.

      iex> {:ok, layout} = AnchoFijo.Layout.coercer(campos: [[nombre: :a, largo: 2]])
      iex> AnchoFijo.Layout.coercer(layout)
      {:ok, layout}
  """
  @spec coercer(t() | Enumerable.t()) :: {:ok, t()} | {:error, [Diagnostico.t()]}
  def coercer(%__MODULE__{} = layout), do: {:ok, layout}
  def coercer(atributos), do: nuevo(atributos)

  @doc """
  Largo total de línea que el layout espera.

      iex> AnchoFijo.Layout.largo(AnchoFijo.Layout.nuevo!(campos: [[nombre: :a, largo: 7]]))
      7
  """
  @spec largo(t()) :: pos_integer()
  def largo(%__MODULE__{largo: largo}), do: largo

  @doc """
  Busca un campo por nombre.

      iex> layout = AnchoFijo.Layout.nuevo!(campos: [[nombre: :a, largo: 2], [nombre: :b, largo: 3]])
      iex> AnchoFijo.Layout.campo(layout, :b) |> AnchoFijo.Campo.rango()
      {3, 5}
      iex> AnchoFijo.Layout.campo(layout, :inexistente)
      nil
  """
  @spec campo(t(), atom()) :: Campo.t() | nil
  def campo(%__MODULE__{campos: campos}, nombre) do
    Enum.find(campos, &(&1.nombre == nombre))
  end

  @doc """
  Nombres de los campos, en orden de posición.

      iex> AnchoFijo.Layout.nuevo!(campos: [[nombre: :a, largo: 2], [nombre: :b, largo: 3]])
      ...> |> AnchoFijo.Layout.nombres()
      [:a, :b]
  """
  @spec nombres(t()) :: [atom()]
  def nombres(%__MODULE__{campos: campos}), do: Enum.map(campos, & &1.nombre)

  @doc """
  Contexto de lectura que el layout entrega a cada campo.

      iex> AnchoFijo.Layout.nuevo!(campos: [[nombre: :a, largo: 2]], encoding: :latin1)
      ...> |> AnchoFijo.Layout.contexto(9)
      %{encoding: :latin1, unidad: :bytes, linea: 9}
  """
  @spec contexto(t(), pos_integer() | nil) :: Campo.contexto()
  def contexto(%__MODULE__{} = layout, linea) do
    %{encoding: layout.encoding, unidad: layout.unidad, linea: linea}
  end

  defp validar_globales(atributos) do
    encoding = Map.get(atributos, :encoding, :utf8)
    unidad = Map.get(atributos, :unidad, :bytes)

    diagnosticos =
      Enum.concat([
        validar_en(encoding, @encodings, :encoding),
        validar_en(unidad, @unidades, :unidad)
      ])

    case diagnosticos do
      [] -> {:ok, %{encoding: encoding, unidad: unidad, nombre: Map.get(atributos, :nombre)}}
      diagnosticos -> {:error, diagnosticos}
    end
  end

  defp validar_en(valor, permitidos, opcion) do
    if valor in permitidos do
      []
    else
      [
        falla(
          "#{inspect(opcion)} en #{inspect(permitidos)}",
          valor,
          nil
        )
      ]
    end
  end

  defp construir_campos([]) do
    {:error,
     [
       falla(
         "al menos un campo en :campos",
         "una lista vacía",
         "un layout sin campos no puede leer nada"
       )
     ]}
  end

  defp construir_campos(definiciones) when is_list(definiciones) do
    {campos, diagnosticos} =
      Enum.reduce(definiciones, {[], []}, fn definicion, {campos, diagnosticos} ->
        case construir_campo(definicion) do
          {:ok, campo} -> {[campo | campos], diagnosticos}
          {:error, nuevos} -> {campos, diagnosticos ++ nuevos}
        end
      end)

    case diagnosticos do
      [] -> validar_nombres_unicos(Enum.reverse(campos))
      diagnosticos -> {:error, diagnosticos}
    end
  end

  defp construir_campos(otro) do
    {:error, [falla("una lista de campos en :campos", otro, nil)]}
  end

  defp construir_campo(%Campo{} = campo), do: {:ok, campo}
  defp construir_campo(definicion), do: Campo.nuevo(definicion)

  defp validar_nombres_unicos(campos) do
    duplicados =
      campos
      |> Enum.frequencies_by(& &1.nombre)
      |> Enum.filter(fn {_nombre, veces} -> veces > 1 end)
      |> Enum.map(fn {nombre, veces} ->
        falla(
          "nombres de campo únicos",
          "#{inspect(nombre)} #{veces} veces",
          "el registro es un mapa: el segundo campo con ese nombre sobrescribiría al primero"
        )
      end)

    case duplicados do
      [] -> {:ok, campos}
      duplicados -> {:error, duplicados}
    end
  end

  # Las posiciones explícitas y las encadenadas se pueden mezclar: quien
  # transcribe un anexo de 60 campos suele copiar las posiciones de los primeros
  # y dejar que el resto se acomode. Cualquier inconsistencia que eso produzca
  # aparece igual en la validación de solapamientos.
  defp posicionar(campos) do
    campos
    |> Enum.map_reduce(1, fn %Campo{} = campo, siguiente ->
      campo = %Campo{campo | posicion: campo.posicion || siguiente}
      {campo, Campo.fin(campo) + 1}
    end)
    |> elem(0)
    |> Enum.sort_by(& &1.posicion)
  end

  defp validar_disposicion(campos) do
    diagnosticos =
      campos
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.flat_map(fn [anterior, actual] -> validar_par(anterior, actual) end)

    case diagnosticos do
      [] -> :ok
      diagnosticos -> {:error, diagnosticos}
    end
  end

  defp validar_par(anterior, actual) do
    fin_anterior = Campo.fin(anterior)

    if actual.posicion <= fin_anterior do
      [solapamiento(anterior, actual, fin_anterior)]
    else
      []
    end
  end

  defp solapamiento(anterior, actual, fin_anterior) do
    Diagnostico.nuevo(
      tipo: :layout,
      campo: actual.nombre,
      posicion: Campo.rango(actual),
      esperado: "que empezara en la posición #{fin_anterior + 1} o después",
      recibido: actual.posicion,
      causa_probable: "se solapa con el campo #{inspect(anterior.nombre)} #{rango_texto(anterior)}"
    )
  end

  defp resolver_largo(campos, globales, atributos) do
    ocupado = campos |> Enum.map(&Campo.fin/1) |> Enum.max()
    declarado = Map.get(atributos, :largo)
    unidad = Campo.nombre_unidad(globales.unidad)

    case declarado do
      nil ->
        {:ok, ocupado, huecos(campos, ocupado, ocupado, unidad)}

      largo when is_integer(largo) and largo >= ocupado ->
        {:ok, largo, huecos(campos, ocupado, largo, unidad)}

      largo ->
        {:error, [largo_insuficiente(largo, ocupado, unidad)]}
    end
  end

  defp largo_insuficiente(declarado, ocupado, unidad) do
    Diagnostico.nuevo(
      tipo: :layout,
      esperado: "un :largo de al menos #{ocupado} #{unidad}, que es lo que ocupan los campos",
      recibido: declarado,
      causa_probable:
        "el :largo declarado no alcanza para los campos definidos; sobra un campo o falta largo"
    )
  end

  defp huecos(campos, ocupado, largo, unidad) do
    intermedios =
      campos
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.flat_map(fn [anterior, actual] -> hueco_entre(anterior, actual) end)

    intermedios ++ hueco_inicial(campos) ++ hueco_final(ocupado, largo, unidad)
  end

  defp hueco_entre(anterior, actual) do
    esperada = Campo.fin(anterior) + 1

    if actual.posicion > esperada do
      [
        Diagnostico.nuevo(
          tipo: :layout,
          campo: actual.nombre,
          posicion: Campo.rango(actual),
          esperado: "que empezara en la posición #{esperada}",
          recibido: actual.posicion,
          causa_probable:
            "quedan #{actual.posicion - esperada} posiciones sin declarar entre " <>
              "#{inspect(anterior.nombre)} y #{inspect(actual.nombre)}; " <>
              "si el formato tiene relleno ahí, ignore esta advertencia"
        )
      ]
    else
      []
    end
  end

  defp hueco_inicial([%Campo{} = primero | _resto]) do
    if primero.posicion > 1 do
      [
        Diagnostico.nuevo(
          tipo: :layout,
          campo: primero.nombre,
          posicion: Campo.rango(primero),
          esperado: "que el primer campo empezara en la posición 1",
          recibido: primero.posicion,
          causa_probable: "las primeras #{primero.posicion - 1} posiciones de cada línea se ignoran"
        )
      ]
    else
      []
    end
  end

  defp hueco_final(ocupado, largo, unidad) when largo > ocupado do
    [
      Diagnostico.nuevo(
        tipo: :layout,
        esperado: "que los campos cubrieran los #{largo} #{unidad} declarados",
        recibido: ocupado,
        causa_probable:
          "las últimas #{largo - ocupado} posiciones de cada línea se ignoran; " <>
            "es normal si el formato reserva relleno al final"
      )
    ]
  end

  defp hueco_final(_ocupado, _largo, _unidad), do: []

  defp rango_texto(campo) do
    {desde, hasta} = Campo.rango(campo)
    "(posiciones #{desde}-#{hasta})"
  end

  defp falla(esperado, recibido, causa) do
    Diagnostico.nuevo(tipo: :layout, esperado: esperado, recibido: recibido, causa_probable: causa)
  end
end
