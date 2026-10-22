defmodule AnchoFijo.Reglas do
  @moduledoc false
  # Las reglas declarativas de un campo: las del valor (`en:`, `rango:`,
  # `patron:`) se verifican al leer y al escribir, sobre el valor ya
  # convertido; las cruzadas (`requerido_si:`, `prohibido_si:`) se
  # verifican sobre el registro entero, cuando ya están todos los campos.
  # Cada falla es un diagnóstico de tipo :regla, con la línea, el campo y
  # las posiciones de siempre, y sensible si el campo lo es.

  alias AnchoFijo.Campo
  alias AnchoFijo.Diagnostico
  alias AnchoFijo.Monto

  @compile {:no_warn_undefined, Decimal}

  # Las reglas viven juntas en `campo.reglas` y no sueltas en el struct del
  # campo: cinco campos más lo pasaban de 32 claves, el tamaño desde el que
  # la VM deja de representar un mapa como flatmap. Este módulo no nombra el
  # struct `Campo` en patrones para que `Campo` pueda tener `%Reglas{}` de
  # default sin un ciclo de compilación.
  defstruct en: nil, rango: nil, patron: nil, requerido_si: nil, prohibido_si: nil

  @type t :: %__MODULE__{
          en: [term()] | (term() -> boolean()) | nil,
          rango: {term(), term()} | nil,
          patron: Regex.t() | nil,
          requerido_si: keyword() | map() | nil,
          prohibido_si: keyword() | map() | nil
        }

  @claves [:en, :rango, :patron, :requerido_si, :prohibido_si]

  @doc false
  # Las opciones de `Campo.nuevo/1` que son reglas.
  @spec claves() :: [atom()]
  def claves, do: @claves

  @doc false
  # El struct de reglas a partir de los atributos de un campo.
  @spec desde_atributos(map()) :: t()
  def desde_atributos(atributos), do: struct(%__MODULE__{}, Map.take(atributos, @claves))

  @con_rango [:entero, :decimal, :fecha, :hora, :fecha_hora]

  # ------------------------------------------------------------ definición

  @doc false
  # Los diagnósticos de layout de las reglas de un campo.
  @spec validar(Campo.t()) :: [Diagnostico.t()]
  def validar(%{} = campo) do
    Enum.concat([
      validar_en(campo),
      validar_rango(campo),
      validar_patron(campo),
      validar_condicion(campo, :requerido_si),
      validar_condicion(campo, :prohibido_si)
    ])
  end

  defp validar_en(%{reglas: %{en: nil}}), do: []
  defp validar_en(%{reglas: %{en: lista}}) when is_list(lista) and lista != [], do: []
  defp validar_en(%{reglas: %{en: fun}}) when is_function(fun, 1), do: []

  defp validar_en(%{} = campo),
    do: [
      falla(
        campo,
        "en: una lista de valores admitidos, no vacía, o una función de un argumento",
        campo.reglas.en
      )
    ]

  defp validar_rango(%{reglas: %{rango: nil}}), do: []

  defp validar_rango(%{reglas: %{rango: {min, max}}, tipo: tipo} = campo) when tipo in @con_rango do
    cond do
      is_nil(min) and is_nil(max) ->
        [falla(campo, "un :rango con al menos un extremo", campo.reglas.rango)]

      not is_nil(min) and not is_nil(max) and comparar(min, max) == :gt ->
        [falla(campo, "un :rango con el mínimo antes que el máximo", campo.reglas.rango)]

      true ->
        []
    end
  end

  defp validar_rango(%{tipo: tipo} = campo) when tipo in @con_rango,
    do: [
      falla(
        campo,
        "un :rango como {minimo, maximo}, con nil en el extremo abierto",
        campo.reglas.rango
      )
    ]

  defp validar_rango(%{} = campo),
    do: [
      falla(
        campo,
        ":rango solo en campos #{inspect(@con_rango)}",
        "un campo #{inspect(campo.tipo)}"
      )
    ]

  defp validar_patron(%{reglas: %{patron: nil}}), do: []
  defp validar_patron(%{reglas: %{patron: %Regex{}}, tipo: :texto}), do: []

  defp validar_patron(%{reglas: %{patron: %Regex{}}} = campo),
    do: [falla(campo, ":patron solo en campos :texto", "un campo #{inspect(campo.tipo)}")]

  defp validar_patron(%{} = campo),
    do: [falla(campo, "un :patron que sea una expresión regular (~r/.../)", campo.reglas.patron)]

  defp validar_condicion(%{} = campo, opcion) do
    case Map.fetch!(campo.reglas, opcion) do
      nil ->
        []

      condicion ->
        otro = condicion_campo(condicion)
        valores = condicion_valores(condicion)

        if is_atom(otro) and not is_nil(otro) and
             (is_nil(valores) or (is_list(valores) and valores != [])),
           do: [],
           else: [
             falla(
               campo,
               "#{inspect(opcion)} como [campo: nombre] o [campo: nombre, en: [valores]]",
               condicion
             )
           ]
    end
  end

  @doc false
  # El campo del que depende una condición, para que el layout verifique
  # que existe. Devuelve lo que el layout haya puesto: validarlo es tarea
  # de `validar_condicion/2`.
  @spec condicion_campo(term()) :: term()
  def condicion_campo(condicion) when is_list(condicion), do: Keyword.get(condicion, :campo)
  def condicion_campo(%{campo: campo}), do: campo
  def condicion_campo(_otro), do: nil

  defp condicion_valores(condicion) when is_list(condicion), do: Keyword.get(condicion, :en)
  defp condicion_valores(%{} = condicion), do: Map.get(condicion, :en)
  defp condicion_valores(_otro), do: nil

  # --------------------------------------------------------- sobre el valor

  @doc false
  # Las reglas del valor de un campo. `nil` (un opcional en blanco) no se
  # valida: las reglas hablan de un valor, y la obligatoriedad es de
  # `requerido_si:`.
  @spec del_valor(Campo.t(), term(), Campo.contexto()) :: [Diagnostico.t()]
  def del_valor(_campo, nil, _contexto), do: []

  def del_valor(%{} = campo, valor, contexto) do
    Enum.concat([
      en(campo, valor, contexto),
      rango(campo, valor, contexto),
      patron(campo, valor, contexto)
    ])
  end

  defp en(%{reglas: %{en: nil}}, _valor, _contexto), do: []

  defp en(%{reglas: %{en: lista}} = campo, valor, contexto) when is_list(lista) do
    if valor in lista,
      do: [],
      else: [
        regla(
          campo,
          contexto,
          "un valor en #{Enum.map_join(lista, ", ", &inspect/1)}",
          valor,
          "el valor no está en el catálogo que el layout declara"
        )
      ]
  end

  defp en(%{reglas: %{en: fun}} = campo, valor, contexto) when is_function(fun, 1) do
    if fun.(valor),
      do: [],
      else: [
        regla(
          campo,
          contexto,
          "un valor que la función de :en acepte",
          valor,
          "el valor no está en el catálogo que el layout declara"
        )
      ]
  end

  defp rango(%{reglas: %{rango: nil}}, _valor, _contexto), do: []

  defp rango(%{reglas: %{rango: {min, max}}} = campo, valor, contexto) do
    bajo? = not is_nil(min) and comparar(valor, min) == :lt
    alto? = not is_nil(max) and comparar(valor, max) == :gt

    if bajo? or alto?,
      do: [
        regla(
          campo,
          contexto,
          describir_rango(min, max),
          valor,
          "el valor está fuera del rango que el layout declara"
        )
      ],
      else: []
  end

  defp describir_rango(min, nil), do: "un valor de #{inspect(min)} en adelante"
  defp describir_rango(nil, max), do: "un valor hasta #{inspect(max)}"
  defp describir_rango(min, max), do: "un valor entre #{inspect(min)} y #{inspect(max)}"

  defp patron(%{reglas: %{patron: nil}}, _valor, _contexto), do: []

  defp patron(%{reglas: %{patron: %Regex{} = patron}} = campo, valor, contexto)
       when is_binary(valor) do
    if Regex.match?(patron, valor),
      do: [],
      else: [
        regla(
          campo,
          contexto,
          "un texto que cumpla #{inspect(patron)}",
          valor,
          "el valor no tiene la forma que el layout declara"
        )
      ]
  end

  defp patron(_campo, _valor, _contexto), do: []

  # Compara enteros, tuplas {unidades, precision}, Monto, Decimal, fechas,
  # horas y fechas con hora. Lo incomparable se considera igual: la regla
  # no sabe qué decir y no inventa un diagnóstico.
  @doc false
  @spec comparar(term(), term()) :: :lt | :eq | :gt
  def comparar(a, b) when is_integer(a) and is_integer(b), do: orden(a, b)

  def comparar({ua, pa}, {ub, pb}) when is_integer(ua) and is_integer(ub) do
    p = max(pa, pb)
    orden(ua * Integer.pow(10, p - pa), ub * Integer.pow(10, p - pb))
  end

  def comparar({u, p}, b) when is_integer(u) and is_integer(b), do: comparar({u, p}, {b, 0})
  def comparar(a, {u, p}) when is_integer(a) and is_integer(u), do: comparar({a, 0}, {u, p})

  def comparar(%Monto{} = a, %Monto{} = b),
    do: comparar({a.unidades, a.precision}, {b.unidades, b.precision})

  def comparar(%Monto{} = a, b), do: comparar({a.unidades, a.precision}, b)
  def comparar(a, %Monto{} = b), do: comparar(a, {b.unidades, b.precision})
  def comparar(%Date{} = a, %Date{} = b), do: Date.compare(a, b)
  def comparar(%Time{} = a, %Time{} = b), do: Time.compare(a, b)
  def comparar(%NaiveDateTime{} = a, %NaiveDateTime{} = b), do: NaiveDateTime.compare(a, b)

  def comparar(%{__struct__: Decimal} = a, b), do: Decimal.compare(a, a_decimal(b))
  def comparar(a, %{__struct__: Decimal} = b), do: Decimal.compare(a_decimal(a), b)
  def comparar(_a, _b), do: :eq

  defp a_decimal(%{__struct__: Decimal} = d), do: d
  defp a_decimal(n) when is_integer(n), do: Decimal.new(n)
  defp a_decimal({u, p}), do: Decimal.new(if(u < 0, do: -1, else: 1), abs(u), -p)
  defp a_decimal(%Monto{} = m), do: a_decimal({m.unidades, m.precision})
  defp a_decimal(otro), do: Decimal.new(to_string(otro))

  defp orden(a, b) when a < b, do: :lt
  defp orden(a, b) when a > b, do: :gt
  defp orden(_a, _b), do: :eq

  # ------------------------------------------------------- sobre el registro

  @doc false
  # Las reglas cruzadas de todos los campos del layout sobre el registro
  # leído o por escribir. Un campo es requerido cuando la condición se
  # cumple y su valor es nil; prohibido cuando se cumple y no es nil.
  @spec cruzadas([Campo.t()], map(), Campo.contexto()) :: [Diagnostico.t()]
  def cruzadas(campos, registro, contexto) do
    Enum.flat_map(campos, fn campo ->
      requerido(campo, registro, contexto) ++ prohibido(campo, registro, contexto)
    end)
  end

  defp requerido(%{reglas: %{requerido_si: nil}}, _registro, _contexto), do: []

  defp requerido(%{reglas: %{requerido_si: condicion}} = campo, registro, contexto) do
    if se_cumple?(condicion, registro) and is_nil(Map.get(registro, campo.nombre)),
      do: [
        regla(
          campo,
          contexto,
          "un valor, porque #{describir_condicion(condicion, registro)}",
          nil,
          "el campo es obligatorio cuando se cumple la condición que el layout declara"
        )
      ],
      else: []
  end

  defp prohibido(%{reglas: %{prohibido_si: nil}}, _registro, _contexto), do: []

  defp prohibido(%{reglas: %{prohibido_si: condicion}} = campo, registro, contexto) do
    valor = Map.get(registro, campo.nombre)

    if se_cumple?(condicion, registro) and not is_nil(valor),
      do: [
        regla(
          campo,
          contexto,
          "ningún valor, porque #{describir_condicion(condicion, registro)}",
          valor,
          "el campo tiene que venir en blanco cuando se cumple la condición que el layout declara"
        )
      ],
      else: []
  end

  defp se_cumple?(condicion, registro) do
    otro = Map.get(registro, condicion_campo(condicion))

    case condicion_valores(condicion) do
      nil -> not is_nil(otro)
      valores -> otro in valores
    end
  end

  defp describir_condicion(condicion, registro) do
    otro = condicion_campo(condicion)

    case condicion_valores(condicion) do
      nil -> "#{inspect(otro)} tiene valor (#{inspect(Map.get(registro, otro))})"
      _valores -> "#{inspect(otro)} es #{inspect(Map.get(registro, otro))}"
    end
  end

  # ----------------------------------------------------------- diagnósticos

  @doc false
  # Las reglas de un campo en prosa, para la documentación.
  @spec describir(Campo.t(), :es | :en) :: [String.t()]
  def describir(%{} = campo, idioma) do
    [
      campo.reglas.en &&
        if(is_list(campo.reglas.en),
          do: t(:en, idioma) <> " " <> Enum.map_join(campo.reglas.en, ", ", &inspect/1),
          else: t(:en_funcion, idioma)
        ),
      campo.reglas.rango && t(:rango, idioma) <> " " <> rango_texto(campo.reglas.rango),
      campo.reglas.patron && t(:patron, idioma) <> " " <> inspect(campo.reglas.patron),
      campo.reglas.requerido_si &&
        t(:requerido_si, idioma) <> " " <> condicion_texto(campo.reglas.requerido_si),
      campo.reglas.prohibido_si &&
        t(:prohibido_si, idioma) <> " " <> condicion_texto(campo.reglas.prohibido_si)
    ]
    |> Enum.filter(&is_binary/1)
  end

  defp rango_texto({min, nil}), do: "≥ #{inspect(min)}"
  defp rango_texto({nil, max}), do: "≤ #{inspect(max)}"
  defp rango_texto({min, max}), do: "#{inspect(min)}..#{inspect(max)}"

  defp condicion_texto(condicion) do
    case condicion_valores(condicion) do
      nil -> "`#{condicion_campo(condicion)}`"
      valores -> "`#{condicion_campo(condicion)}` ∈ #{Enum.map_join(valores, ", ", &inspect/1)}"
    end
  end

  @textos %{
    en: {"uno de", "one of"},
    en_funcion: {"según función", "by function"},
    rango: {"rango", "range"},
    patron: {"patrón", "pattern"},
    requerido_si: {"requerido si", "required if"},
    prohibido_si: {"prohibido si", "forbidden if"}
  }

  defp t(clave, idioma) do
    {es, en} = Map.fetch!(@textos, clave)
    if idioma == :en, do: en, else: es
  end

  defp regla(%{} = campo, contexto, esperado, valor, causa) do
    diagnostico =
      Diagnostico.nuevo(
        tipo: :regla,
        linea: Map.get(contexto, :linea),
        campo: campo.nombre,
        posicion: Campo.rango(campo),
        esperado: esperado,
        recibido: inspect(valor),
        causa_probable: causa
      )

    if campo.sensible,
      do: Diagnostico.marcar_sensible(diagnostico, texto_de(valor)),
      else: diagnostico
  end

  defp texto_de(nil), do: nil
  defp texto_de(valor) when is_binary(valor), do: valor
  defp texto_de(valor), do: to_string(valor)

  defp falla(%{nombre: nombre}, esperado, recibido) do
    Diagnostico.nuevo(
      tipo: :layout,
      campo: nombre,
      esperado: esperado,
      recibido: inspect(recibido),
      causa_probable: nil
    )
  end
end
