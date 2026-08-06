defmodule AnchoFijo.Fixtures do
  @moduledoc false

  @directorio Path.expand("../fixtures", __DIR__)

  def ruta(nombre), do: Path.join(@directorio, nombre)

  def leer(nombre), do: File.read!(ruta(nombre))

  @doc false
  # Layout que describen todos los fixtures de nómina: 48 posiciones.
  def layout_nomina(opts \\ []) do
    AnchoFijo.Layout.nuevo!(
      Keyword.merge(
        [
          nombre: "nómina de fixtures",
          campos: [
            [nombre: :rut, largo: 10],
            [nombre: :beneficiario, largo: 20],
            [nombre: :monto, largo: 10, tipo: :decimal, precision: 2],
            [nombre: :fecha, largo: 8, tipo: :fecha, formato: :aaaammdd]
          ]
        ],
        opts
      )
    )
  end
end
