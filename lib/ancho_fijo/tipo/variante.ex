defmodule AnchoFijo.Tipo.Variante do
  @moduledoc """
  El tipo `:variante`: a partir de cierta posición el registro cambia de
  forma según el valor de un campo anterior, el `REDEFINES` de los formatos
  heredados. El tipo de cuenta decide si lo que sigue es una cuenta
  bancaria, una CLABE o un número de tarjeta.

      [nombre: :destino, tipo: :variante, segun: :tipo_cuenta, variantes: %{
        "01" => [[nombre: :banco, largo: 3], [nombre: :cuenta, largo: 17]],
        "02" => [[nombre: :clabe, largo: 18], [nombre: :filler, largo: 2, tipo: :relleno]]
      }]

  El valor es el mapa de la variante elegida. `:segun` tiene que ser un
  campo del mismo layout que venga antes, y la clave de `:variantes` es el
  valor que ese campo lee (un string para `:texto` o `:constante`, un
  entero para `:entero`). Un valor sin variante declarada es un
  diagnóstico que lista las que hay. Todas las variantes miden lo mismo, o
  el campo declara un `:largo` y las más cortas se completan con blanco al
  escribir (y lo que sobra no se lee). Los diagnósticos de los campos
  internos llevan la ruta: `destino.cuenta`.
  """

  @behaviour AnchoFijo.Tipo

  alias AnchoFijo.Campo
  alias AnchoFijo.Tipo

  @impl true
  def opciones, do: [:segun, :variantes]

  @impl true
  def validar(%Campo{} = campo) do
    cond do
      not (is_atom(campo.segun) and not is_nil(campo.segun)) ->
        [
          Tipo.falla(
            campo,
            "un :segun con el nombre del campo que elige la variante",
            campo.segun,
            nil
          )
        ]

      not (is_map(campo.variantes) and map_size(campo.variantes) > 0) ->
        [
          Tipo.falla(
            campo,
            "un mapa :variantes de valor a lista de campos, no vacío",
            campo.variantes,
            nil
          )
        ]

      Enum.any?(campo.variantes, fn {_valor, campos} -> not is_list(campos) or campos == [] end) ->
        [
          Tipo.falla(
            campo,
            "una lista de campos, no vacía, por cada valor de :variantes",
            campo.variantes,
            nil
          )
        ]

      true ->
        []
    end
  end

  @impl true
  def leer(_texto, campo, contexto) do
    {:error,
     Tipo.diagnostico(campo, contexto,
       esperado: "una variante leída campo por campo",
       recibido: "una lectura plana",
       causa_probable: "las variantes se leen con AnchoFijo.Anidados, no con Campo.extraer/3"
     )}
  end
end
