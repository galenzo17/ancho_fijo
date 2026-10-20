# Layout de los fixtures de nómina, para `mix ancho_fijo.detectar --layout`.
# El archivo se evalúa y tiene que devolver la definición.
[
  nombre: "nómina de fixtures",
  campos: [
    [nombre: :rut, largo: 10],
    [nombre: :beneficiario, largo: 20],
    [nombre: :monto, largo: 10, tipo: :decimal, precision: 2],
    [nombre: :fecha, largo: 8, tipo: :fecha, formato: :aaaammdd]
  ]
]
