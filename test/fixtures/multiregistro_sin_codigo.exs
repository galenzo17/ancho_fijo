# Header, detalle y trailer sin código de tipo: se distinguen por el largo de
# la línea. Describe test/fixtures/nomina_sin_codigo.txt, y lo usa el test de
# `mix ancho_fijo.detectar --layout`.
AnchoFijo.Multiregistro.nuevo!(
  nombre: "nómina sin código de tipo",
  discriminador: [por: :largo],
  registros: [
    header: [
      cantidad: :uno,
      layout: [
        campos: [
          [nombre: :empresa, largo: 10, tipo: :rut],
          [nombre: :fecha, largo: 8, tipo: :fecha, formato: :aaaammdd],
          [nombre: :glosa, largo: 14]
        ]
      ]
    ],
    detalle: [
      cantidad: :al_menos_uno,
      layout: [
        campos: [
          [nombre: :rut, largo: 10, tipo: :rut],
          [nombre: :nombre, largo: 16],
          [nombre: :monto, largo: 10, tipo: :decimal, precision: 2],
          [nombre: :cuenta, largo: 4, tipo: :entero]
        ]
      ]
    ],
    trailer: [
      cantidad: :uno,
      layout: [
        campos: [
          [nombre: :cantidad, largo: 6, tipo: :entero],
          [nombre: :total, largo: 14, tipo: :decimal, precision: 2]
        ]
      ]
    ]
  ],
  controles: [
    [en: :trailer, campo: :cantidad, cuenta: :detalle],
    [en: :trailer, campo: :total, suma: {:detalle, :monto}]
  ]
)
