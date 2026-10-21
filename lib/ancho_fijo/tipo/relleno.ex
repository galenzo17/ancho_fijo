defmodule AnchoFijo.Tipo.Relleno do
  @moduledoc """
  El tipo `:relleno`: posiciones reservadas que nadie lee, los *fillers* de
  los formatos.

      [nombre: :filler, largo: 946, tipo: :relleno]           # espacios
      [nombre: :ceros, largo: 15, tipo: :relleno, relleno: "0"]

    * Al leer, el campo no aparece en el registro, y lo que haya en esas
      posiciones no se valida: un filler es por definición lo que el emisor
      no se compromete a llenar con nada en particular.
    * Al escribir, se emite el carácter de `:relleno` repetido, sin que el
      campo esté en el mapa. Si el mapa lo trae con un valor que no es
      `nil`, es un diagnóstico: el relleno no se escribe desde el registro.
    * Con `relleno_final: :tolerar` en el layout, un filler al final de la
      línea es relleno reponible, como un `:texto`: es exactamente lo que
      los emisores recortan.

  Existe para que el layout diga lo que el formato dice. Un `:texto` llamado
  `:filler` con `opcional: true` lee lo mismo, pero mete una clave de basura
  en cada registro y hay que acordarse de omitirla al escribir.
  """

  @behaviour AnchoFijo.Tipo

  @impl true
  def opciones, do: []

  @impl true
  def validar(_campo), do: []

  @impl true
  def leer(_texto, _campo, _contexto), do: {:ok, nil}
end
