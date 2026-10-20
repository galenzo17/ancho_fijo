defmodule AnchoFijo.Tipo.Texto do
  @moduledoc """
  El tipo `:texto`: el valor es el texto del campo, ya transcodificado a UTF-8
  y recortado según `:trim` y `:relleno`.

  Es el único tipo para el que un campo en blanco sin `:opcional` es un valor
  (`""`) y no un diagnóstico: una glosa vacía es una glosa.
  """

  @behaviour AnchoFijo.Tipo

  @impl true
  def opciones, do: []

  @impl true
  def validar(_campo), do: []

  @impl true
  def leer(texto, _campo, _contexto), do: {:ok, texto}
end
