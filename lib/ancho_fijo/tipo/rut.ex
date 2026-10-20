defmodule AnchoFijo.Tipo.Rut do
  @moduledoc """
  El tipo `:rut`: normaliza las presentaciones que llegan en archivos reales
  a `"12345678-5"` y valida el dígito verificador con `AnchoFijo.Rut`.
  `:dv` es `:validar` (default), `:no_validar` o `:ausente`.
  """

  @behaviour AnchoFijo.Tipo

  alias AnchoFijo.Campo
  alias AnchoFijo.Rut
  alias AnchoFijo.Tipo

  @impl true
  def opciones, do: [:dv]

  @impl true
  def validar(%Campo{dv: dv} = campo) do
    if dv in Rut.modos(),
      do: [],
      else: [Tipo.falla(campo, ":dv en #{inspect(Rut.modos())}", dv, nil)]
  end

  @impl true
  def leer("", campo, contexto), do: {:error, Tipo.vacio(campo, contexto)}

  def leer(texto, campo, contexto) do
    case Rut.normalizar(texto, campo.dv) do
      {:ok, rut} ->
        {:ok, rut}

      {:error, {:dv, esperado, _recibido}} ->
        {:error,
         Tipo.diagnostico(campo, contexto,
           esperado:
             "un RUT cuyo dígito verificador cuadre; para ese cuerpo corresponde #{esperado}",
           recibido: inspect(texto),
           causa_probable:
             "el dígito verificador no cuadra: posible error de digitación o campo corrido"
         )}

      {:error, {:formato, detalle}} ->
        {:error,
         Tipo.diagnostico(campo, contexto,
           esperado: descripcion(campo.dv),
           recibido: inspect(texto),
           causa_probable: detalle
         )}
    end
  end

  defp descripcion(:ausente), do: "el cuerpo de un RUT, sin dígito verificador"
  defp descripcion(_con_dv), do: "un RUT con dígito verificador"
end
