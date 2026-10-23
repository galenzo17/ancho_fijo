defmodule AnchoFijo.Tipo.Texto do
  @moduledoc """
  El tipo `:texto`: el valor es el texto del campo, ya transcodificado a UTF-8
  y recortado según `:trim` y `:relleno`.

  Es el único tipo para el que un campo en blanco sin `:opcional` es un valor
  (`""`) y no un diagnóstico: una glosa vacía es una glosa.

  ## Doble codificación

  Un texto como `operaciÃ³n` es UTF-8 que alguien decodificó como latin-1 y
  volvió a codificar. `AnchoFijo.Campo` lo detecta (ver
  `AnchoFijo.Transcodificacion.doble_codificacion/1`) y deja una
  advertencia `:doble_codificacion` con el texto reparado; con
  `reparar_doble_codificacion: true` en el campo, el valor sale reparado y
  la advertencia lo anota. Si el campo trae UTF-8 en un layout latin-1, la
  solución de fondo es `encoding: :utf8` en ese campo.
  """

  @behaviour AnchoFijo.Tipo

  @impl true
  def opciones, do: [:reparar_doble_codificacion]

  @impl true
  def validar(_campo), do: []

  @impl true
  def leer(texto, _campo, _contexto), do: {:ok, texto}
end
