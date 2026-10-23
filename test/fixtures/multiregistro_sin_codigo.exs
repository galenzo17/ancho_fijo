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
          [
            nombre: :empresa,
            largo: 10,
            tipo: :rut,
            descripcion: "RUT de la empresa pagadora",
            ejemplo: "76543210-3"
          ],
          [
            nombre: :fecha,
            largo: 8,
            tipo: :fecha,
            formato: :aaaammdd,
            descripcion: "Fecha de pago"
          ],
          [nombre: :glosa, largo: 14, descripcion: "Glosa libre del lote"]
        ]
      ]
    ],
    detalle: [
      cantidad: :al_menos_uno,
      layout: [
        campos: [
          [nombre: :rut, largo: 10, tipo: :rut, descripcion: "RUT del beneficiario"],
          [nombre: :nombre, largo: 16, descripcion: "Nombre del beneficiario"],
          [
            nombre: :monto,
            largo: 10,
            tipo: :decimal,
            precision: 2,
            descripcion: "Monto a pagar",
            ejemplo: "0000125000"
          ],
          [nombre: :cuenta, largo: 4, tipo: :entero, descripcion: "Cuenta de destino"]
        ]
      ]
    ],
    trailer: [
      cantidad: :uno,
      layout: [
        campos: [
          [nombre: :cantidad, largo: 6, tipo: :entero, descripcion: "Cantidad de detalles"],
          [
            nombre: :total,
            largo: 14,
            tipo: :decimal,
            precision: 2,
            descripcion: "Suma de los montos"
          ]
        ]
      ]
    ]
  ],
  controles: [
    [en: :trailer, campo: :cantidad, cuenta: :detalle],
    [en: :trailer, campo: :total, suma: {:detalle, :monto}]
  ]
)
