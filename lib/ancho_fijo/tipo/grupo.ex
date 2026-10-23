defmodule AnchoFijo.Tipo.Grupo do
  @moduledoc """
  El tipo `:grupo`: un bloque de campos que se repite N veces dentro del
  registro, el `OCCURS` de los formatos heredados de mainframe. Tres
  totales por moneda, doce montos mensuales.

      [nombre: :totales, tipo: :grupo, repetir: 3, campos: [
        [nombre: :moneda, largo: 3],
        [nombre: :importe, largo: 15, tipo: :decimal, precision: 2]
      ]]

  El valor es una lista de `repetir` mapas, uno por repetición, en el orden
  del archivo. Las posiciones de los campos internos son relativas al
  grupo y se encadenan como en un layout; el `:largo` del grupo se calcula
  (`repetir` × el largo de una repetición) y, si se declara, tiene que
  coincidir. Un diagnóstico de un campo interno lleva la ruta:
  `totales[2].importe`.

  Al escribir, el registro trae la lista completa: menos o más mapas que
  `repetir` es un diagnóstico, porque el ancho del grupo es parte del
  formato.
  """

  @behaviour AnchoFijo.Tipo

  alias AnchoFijo.Campo
  alias AnchoFijo.Tipo

  @impl true
  def opciones, do: [:campos, :repetir]

  @impl true
  def validar(%Campo{} = campo) do
    repetir = campo.repetir || 1

    cond do
      not (is_integer(repetir) and repetir > 0) ->
        [Tipo.falla(campo, "un :repetir entero mayor que cero", campo.repetir, nil)]

      not is_list(campo.campos) or campo.campos == [] ->
        [Tipo.falla(campo, "al menos un campo en :campos del grupo", campo.campos, nil)]

      true ->
        []
    end
  end

  # Un grupo no se lee como un valor plano: lo arma `AnchoFijo.Anidados`
  # campo por campo. Si algo llega acá, el campo se construyó mal.
  @impl true
  def leer(_texto, campo, contexto) do
    {:error,
     Tipo.diagnostico(campo, contexto,
       esperado: "un grupo leído campo por campo",
       recibido: "una lectura plana",
       causa_probable: "los grupos se leen con AnchoFijo.Anidados, no con Campo.extraer/3"
     )}
  end
end
