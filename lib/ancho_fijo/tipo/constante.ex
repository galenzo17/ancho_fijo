defmodule AnchoFijo.Tipo.Constante do
  @moduledoc """
  El tipo `:constante`: un literal fijo del formato, que no viene del dato.

  Todo layout bancario tiene posiciones cuyo valor lo pone el formato y no
  el registro: el código de tipo de registro (`"01"`, `"H"`), un literal
  como `"HEADER H2H"`, un separador. Declararlos como `:texto` los deja sin
  validar al leer y obliga a repetirlos en cada mapa al escribir.

      [nombre: :tipo_registro, largo: 2, tipo: :constante, valor: "01"]

    * Al leer, el texto del campo tiene que ser el literal; si no, es un
      diagnóstico `:campo_invalido` con `esperado` y `recibido`, como
      cualquier otro campo. El valor del registro es el literal declarado.
    * Al escribir, se emite el literal sin que esté en el mapa. Si el mapa
      lo trae con el mismo valor, también; con otro valor, es un diagnóstico:
      un literal distinto no es un dato, es otro formato.
    * Un literal más corto que el campo se completa a la derecha con
      `:relleno` (espacio por default), y al leer el relleno final no cuenta:
      `"HEADER"` en un campo de 10 calza con `"HEADER    "`.

  `:trim` no aplica: el literal se compara entero.
  """

  @behaviour AnchoFijo.Tipo

  alias AnchoFijo.Campo
  alias AnchoFijo.Tipo

  @impl true
  def opciones, do: [:valor]

  @impl true
  def validar(%Campo{valor: valor} = campo) do
    cond do
      not is_binary(valor) or valor == "" ->
        [
          Tipo.falla(
            campo,
            "un :valor binario no vacío para un campo :constante",
            valor,
            "el literal es parte del formato y se declara en el layout"
          )
        ]

      String.length(valor) > campo.largo ->
        [
          Tipo.falla(
            campo,
            "un :valor de hasta #{campo.largo} caracteres",
            valor,
            "el literal no cabe en el campo"
          )
        ]

      true ->
        []
    end
  end

  @impl true
  def leer(texto, %Campo{valor: valor, relleno: relleno} = campo, contexto) do
    if coincide?(texto, valor, relleno) do
      {:ok, valor}
    else
      {:error,
       Tipo.diagnostico(campo, contexto,
         esperado: "el literal #{inspect(valor)}",
         recibido: inspect(texto),
         causa_probable:
           "la línea no es del formato declarado, o el emisor cambió el literal; " <>
             "si es un código de tipo de registro, puede ser un archivo multiregistro"
       )}
    end
  end

  @doc """
  Si el texto es el literal, sin contar el relleno final de ninguno de los dos.

      iex> AnchoFijo.Tipo.Constante.coincide?("HEADER    ", "HEADER", " ")
      true
      iex> AnchoFijo.Tipo.Constante.coincide?("HEADER  X ", "HEADER", " ")
      false
  """
  @spec coincide?(String.t(), String.t(), String.t()) :: boolean()
  def coincide?(texto, valor, relleno) do
    String.trim_trailing(texto, relleno) == String.trim_trailing(valor, relleno)
  end

  @doc """
  El literal completo al ancho del campo, tal como va en la línea.

      iex> campo = AnchoFijo.Campo.nuevo!(nombre: :t, largo: 4, tipo: :constante, valor: "H")
      iex> AnchoFijo.Tipo.Constante.esperado(campo)
      "H   "
  """
  @spec esperado(Campo.t()) :: String.t()
  def esperado(%Campo{valor: valor, largo: largo, relleno: relleno}) do
    valor <> String.duplicate(relleno, max(largo - String.length(valor), 0))
  end
end
