defmodule AnchoFijo.Error do
  @moduledoc """
  La excepción de la librería: uno o más `AnchoFijo.Diagnostico` adentro.

  La levantan solo las funciones con `!` —`AnchoFijo.parsear!/3`,
  `AnchoFijo.detectar!/2`, `AnchoFijo.Layout.nuevo!/1`, `AnchoFijo.Campo.nuevo!/1`—
  y `AnchoFijo.stream/3` cuando el layout es inválido. El mensaje es
  `AnchoFijo.Diagnostico.reporte/1` sobre los diagnósticos: la excepción no
  redacta nada nuevo, y lo que se lee en la consola es lo mismo que habría
  llegado en la tupla.

      iex> try do
      ...>   AnchoFijo.parsear!([campos: [[nombre: :codigo, largo: 3, tipo: :entero]]], "001\\nAB2\\n")
      ...> rescue
      ...>   e in AnchoFijo.Error -> {length(e.diagnosticos), Exception.message(e)}
      ...> end
      {1, "línea 2, campo :codigo (posiciones 1-3): se esperaban 3 posiciones con un número entero, llegaron \\"AB2\\"; hay caracteres no numéricos o el campo está corrido"}

  ## Las dos formas de fallar

  La librería tiene dos y solo dos maneras de decir que algo salió mal:

    * **Un problema con los datos** —el archivo, el layout, la línea— es un
      `AnchoFijo.Diagnostico`. Llega como valor en `{:error, diagnosticos}`, o
      envuelto en esta excepción si se usó la variante con `!`.
    * **Un problema con la llamada** —una opción que no existe, un valor de
      otro tipo— es un `ArgumentError`, como en la stdlib. No es un
      diagnóstico porque no hay nada que mandarle al banco: el bug es del
      programa.

  Nada más debería escapar de una función pública. Si escapa un
  `FunctionClauseError` o un `MatchError`, es un bug de la librería.
  """

  defexception [:diagnosticos]

  @type t :: %__MODULE__{diagnosticos: [AnchoFijo.Diagnostico.t()]}

  @impl true
  def exception(diagnosticos) when is_list(diagnosticos) do
    %__MODULE__{diagnosticos: diagnosticos}
  end

  @impl true
  def exception(diagnostico), do: %__MODULE__{diagnosticos: [diagnostico]}

  @impl true
  def message(%__MODULE__{diagnosticos: diagnosticos}) do
    AnchoFijo.Diagnostico.reporte(diagnosticos)
  end
end
