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

  @doc false
  # La respuesta mixta: offsets en bytes, latin-1 en el nombre, UTF-8 en el
  # mensaje. 56 posiciones.
  def layout_respuesta_mixta(opts \\ []) do
    AnchoFijo.Layout.nuevo!(
      Keyword.merge(
        [
          nombre: "respuesta del banco",
          encoding: :latin1,
          campos: [
            [nombre: :rut, largo: 10, tipo: :rut],
            [nombre: :nombre, largo: 14],
            [nombre: :mensaje, largo: 24, encoding: :utf8],
            [nombre: :fecha, largo: 8, tipo: :fecha, formato: :aaaammdd]
          ]
        ],
        opts
      )
    )
  end

  @doc false
  # La nómina con un grupo repetido (tres totales por moneda) y una variante
  # (el destino según el tipo de cuenta): 69 posiciones.
  def layout_anidado do
    AnchoFijo.Layout.nuevo!(
      nombre: "nómina anidada",
      campos: [
        [nombre: :tipo_cuenta, largo: 2],
        [nombre: :rut, largo: 10, tipo: :rut],
        [
          nombre: :totales,
          tipo: :grupo,
          repetir: 3,
          campos: [
            [nombre: :moneda, largo: 3],
            [nombre: :importe, largo: 10, tipo: :decimal, precision: 2]
          ]
        ],
        [
          nombre: :destino,
          tipo: :variante,
          segun: :tipo_cuenta,
          variantes: %{
            "01" => [[nombre: :banco, largo: 3], [nombre: :cuenta, largo: 15, tipo: :entero]],
            "02" => [[nombre: :clabe, largo: 18]]
          }
        ]
      ]
    )
  end

  @doc false
  # Layout con la glosa al final, que es donde los formatos reales ponen el
  # campo de ancho variable: 60 posiciones, las últimas 30 rellenas de espacios.
  def layout_glosa(opts \\ []) do
    AnchoFijo.Layout.nuevo!(
      Keyword.merge(
        [
          nombre: "nómina con glosa final",
          campos: [
            [nombre: :rut, largo: 10],
            [nombre: :fecha, largo: 8, tipo: :fecha, formato: :aaaammdd],
            [nombre: :monto, largo: 12, tipo: :decimal, precision: 2],
            [nombre: :glosa, largo: 30]
          ]
        ],
        opts
      )
    )
  end
end
