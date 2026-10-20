defmodule AnchoFijo.Opciones do
  @moduledoc false
  # Valida las opciones y las definiciones que reciben las funciones públicas.
  #
  # Una opción mal escrita o con un valor de otro tipo es un error del
  # programador, no del archivo. La respuesta correcta es la de la stdlib:
  # `ArgumentError`, con el nombre de la función y de la opción. Las otras dos
  # respuestas posibles son peores: un diagnóstico confunde un bug del llamador
  # con un dato sucio, y dejar que explote más adentro da un
  # `FunctionClauseError` en `Enum.drop/2` que no dice qué opción fue.

  @typedoc "Nombre de la opción, predicado sobre su valor y descripción de lo que espera."
  @type esquema :: [{atom(), (term() -> boolean()), String.t()}]

  @doc """
  Devuelve `opts` si es una keyword list cuyas claves y valores respetan el
  esquema; levanta `ArgumentError` en cualquier otro caso.
  """
  @spec validar!(term(), esquema(), String.t()) :: keyword()
  def validar!(opts, esquema, funcion) do
    unless Keyword.keyword?(opts) do
      raise ArgumentError,
            "#{funcion} espera las opciones como keyword list, llegó: #{inspect(opts)}"
    end

    Enum.each(opts, fn {clave, valor} -> validar_opcion!(clave, valor, esquema, funcion) end)
    opts
  end

  @doc """
  Convierte una definición (keyword list, mapa o struct) a mapa, o devuelve
  `:error` si no es ninguna de las tres cosas.

  `Map.new/1` a secas acepta cualquier enumerable y revienta con una lista que
  no sea de pares; esto lo decide antes.
  """
  @spec a_mapa(term()) :: {:ok, map()} | :error
  def a_mapa(definicion) when is_map(definicion), do: {:ok, definicion}

  def a_mapa(definicion) when is_list(definicion) do
    if Keyword.keyword?(definicion), do: {:ok, Map.new(definicion)}, else: :error
  end

  def a_mapa(_definicion), do: :error

  @doc """
  Claves de la definición que no están entre las conocidas, en el orden en que
  aparecen. `:__struct__` no cuenta: quien pasa un struct o un
  `Map.from_struct/1` no está declarando una opción.
  """
  @spec claves_desconocidas(map(), [atom()]) :: [term()]
  def claves_desconocidas(definicion, conocidas) do
    definicion
    |> Map.keys()
    |> Enum.reject(&(&1 == :__struct__ or &1 in conocidas))
  end

  defp validar_opcion!(clave, valor, esquema, funcion) do
    case List.keyfind(esquema, clave, 0) do
      nil ->
        validas = Enum.map_join(esquema, ", ", fn {nombre, _, _} -> inspect(nombre) end)

        raise ArgumentError,
              "#{funcion} no reconoce la opción #{inspect(clave)}; " <>
                "las opciones válidas son #{validas}"

      {_clave, valido?, descripcion} ->
        unless valido?.(valor) do
          raise ArgumentError,
                "#{funcion}: la opción #{inspect(clave)} espera #{descripcion}, " <>
                  "llegó #{inspect(valor)}"
        end
    end
  end
end
