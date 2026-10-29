defmodule AnchoFijo.Formatos do
  @moduledoc """
  Formatos reales, listos para usar, con su fuente citada.

  La librería sabe leer cualquier formato de ancho fijo, pero cada usuario
  tiene que transcribir el anexo desde cero. Los formatos de verdad son
  públicos y estables, y traerlos incluidos convierte al paquete de "un
  parser genérico" en "sabe leer lo que necesito":

      {:ok, registros, []} = AnchoFijo.parsear(AnchoFijo.Formatos.nacha(), "ach.txt")
      [] = AnchoFijo.Formatos.Nacha.validar(registros)
      lotes = AnchoFijo.Formatos.Nacha.lotes(registros)

  ## Cómo se versionan

  Los formatos cambian por resolución del regulador, y un layout
  desactualizado en silencio es peor que no tenerlo. Por eso cada formato se
  pide con su **vigencia**, que es la versión de la norma que transcribe:

      AnchoFijo.Formatos.nacha()                  # la vigencia más nueva del catálogo
      AnchoFijo.Formatos.nacha(vigencia: "2021")  # una vigencia explícita, que no cambia

  Pedir la más nueva es cómodo para empezar; fijar la vigencia es lo que
  corresponde en producción, porque así una actualización del catálogo no
  cambia qué se lee sin que nadie lo decida. Una vigencia que no está en el
  catálogo es `ArgumentError`. `catalogo/0` lista las vigencias de cada
  formato con su fuente y la fecha en que se consultó.

  ## Qué formatos hay

    * `nacha/1` — NACHA/ACH, Estados Unidos. Ver `AnchoFijo.Formatos.Nacha`.
    * `cuaderno43/1` — Cuaderno 43 de la AEB, el extracto bancario de
      España. Ver `AnchoFijo.Formatos.Cuaderno43`.

  Se agregan de a uno y completos, no dos a medias, con el mismo criterio:
  público, estable, con fuente citable, y que ejercite partes de la
  librería que los anteriores no ejercitan. Previred (Chile) no entra: su
  archivo vigente de 105 campos es delimitado por punto y coma, no de ancho
  fijo.
  """

  alias AnchoFijo.Formatos.Cuaderno43
  alias AnchoFijo.Formatos.Nacha
  alias AnchoFijo.Multiregistro

  @catalogo %{
    nacha: %{
      vigencias: ["2021"],
      fuente: Nacha.fuente(),
      consultado: ~D[2026-10-16]
    },
    cuaderno43: %{
      vigencias: ["2012"],
      fuente: Cuaderno43.fuente(),
      consultado: ~D[2026-10-29]
    }
  }

  @doc """
  Las vigencias disponibles de cada formato, su fuente y cuándo se consultó.

      iex> AnchoFijo.Formatos.catalogo().nacha.vigencias
      ["2021"]
  """
  @spec catalogo() :: %{
          atom() => %{vigencias: [String.t()], fuente: String.t(), consultado: Date.t()}
        }
  def catalogo, do: @catalogo

  @doc """
  El multiregistro del formato NACHA/ACH. Ver `AnchoFijo.Formatos.Nacha`.

      iex> AnchoFijo.Formatos.nacha().discriminador
      %{posicion: 1, largo: 2}
      iex> AnchoFijo.Formatos.nacha(vigencia: "2021") == AnchoFijo.Formatos.nacha()
      true
  """
  @spec nacha(keyword()) :: Multiregistro.t()
  def nacha(opts \\ []) do
    case vigencia(:nacha, Keyword.get(opts, :vigencia)) do
      "2021" -> Nacha.multiregistro()
    end
  end

  @doc """
  El multiregistro del Cuaderno 43 de la AEB. Ver `AnchoFijo.Formatos.Cuaderno43`.

      iex> AnchoFijo.Formatos.cuaderno43().discriminador
      %{posicion: 1, largo: 2}
      iex> AnchoFijo.Formatos.cuaderno43(vigencia: "2012") == AnchoFijo.Formatos.cuaderno43()
      true
  """
  @spec cuaderno43(keyword()) :: Multiregistro.t()
  def cuaderno43(opts \\ []) do
    case vigencia(:cuaderno43, Keyword.get(opts, :vigencia)) do
      "2012" -> Cuaderno43.multiregistro()
    end
  end

  defp vigencia(formato, nil),
    do: @catalogo |> Map.fetch!(formato) |> Map.fetch!(:vigencias) |> List.last()

  defp vigencia(formato, pedida) do
    disponibles = @catalogo |> Map.fetch!(formato) |> Map.fetch!(:vigencias)

    if pedida in disponibles do
      pedida
    else
      raise ArgumentError,
            "la vigencia #{inspect(pedida)} de #{inspect(formato)} no está en el catálogo; " <>
              "las disponibles son #{inspect(disponibles)}"
    end
  end
end
