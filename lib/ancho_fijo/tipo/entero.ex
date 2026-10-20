defmodule AnchoFijo.Tipo.Entero do
  @moduledoc """
  El tipo `:entero`: dígitos con signo opcional, al principio (`-1250`) o,
  con `signo: :final`, al final (`1250-`) como en los formatos heredados de
  mainframe.
  """

  @behaviour AnchoFijo.Tipo

  alias AnchoFijo.Tipo
  alias AnchoFijo.Tipo.Signo

  @impl true
  def opciones, do: [:signo]

  @impl true
  def validar(campo), do: Signo.validar(campo)

  @impl true
  def leer("", campo, contexto), do: {:error, Tipo.vacio(campo, contexto)}

  def leer(texto, campo, contexto) do
    with {:ok, signo, digitos} <- Signo.separar(texto, campo),
         true <- Tipo.solo_digitos?(digitos) do
      {:ok, signo * String.to_integer(digitos)}
    else
      {:error, causa} ->
        {:error, Signo.error(campo, texto, causa, contexto)}

      false ->
        {:error,
         Tipo.diagnostico(campo, contexto,
           esperado: "#{campo.largo} posiciones con un número entero",
           recibido: inspect(texto),
           causa_probable: "hay caracteres no numéricos o el campo está corrido"
         )}
    end
  end
end
