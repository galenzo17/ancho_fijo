# Regenera los fixtures: mix run test/fixtures/generar.exs
#
# Existe porque dos de estos archivos no se pueden editar a mano de forma
# confiable: el de latin-1 se corrompe al abrirlo en un editor UTF-8, y el que
# no tiene terminador final lo recupera cualquier editor que "arregle" el
# archivo al guardar.

destino = Path.expand(__DIR__)

# Layout que todos los fixtures de nómina describen, 48 posiciones:
#   rut          1-10   texto
#   beneficiario 11-30  texto
#   monto        31-40  decimal con 2 decimales implícitos
#   fecha        41-48  fecha AAAAMMDD
fila = fn rut, nombre, monto, fecha ->
  String.pad_trailing(rut, 10) <>
    String.pad_trailing(nombre, 20) <>
    String.pad_leading(monto, 10, "0") <>
    fecha
end

lineas = fn filas -> Enum.map_join(filas, "", &(&1 <> "\n")) end

escribir = fn nombre, contenido ->
  ruta = Path.join(destino, nombre)
  File.write!(ruta, contenido)
  IO.puts("#{nombre}: #{byte_size(contenido)} bytes")
end

escribir.(
  "nomina_correcta.txt",
  lineas.([
    fila.("12345678-9", "JUAN PEREZ SOTO", "125000", "20240115"),
    fila.("98765432-1", "ANA MARIA ROJAS", "9990050", "20240115"),
    fila.("11111111-1", "PEDRO GONZALEZ", "45", "20240116")
  ])
)

# Los acentos y la ñ como un solo byte, que es lo que manda un mainframe.
escribir.(
  "nomina_latin1.txt",
  lineas.([
    fila.("12345678-9", "JOSÉ MUÑOZ PEÑA", "125000", "20240115"),
    fila.("98765432-1", "MARÍA ROJAS ÑAÑEZ", "9990050", "20240115")
  ])
  |> then(&:unicode.characters_to_binary(&1, :utf8, :latin1))
)

# A la segunda fila le faltan 2 posiciones de la fecha: el emisor no rellenó un
# campo que venía vacío.
escribir.(
  "nomina_fila_corta.txt",
  lineas.([
    fila.("12345678-9", "JUAN PEREZ SOTO", "125000", "20240115"),
    String.slice(fila.("98765432-1", "ANA MARIA ROJAS", "9990050", "20240115"), 0..45),
    fila.("11111111-1", "PEDRO GONZALEZ", "45", "20240116")
  ])
)

# Layout con la glosa al final, 60 posiciones:
#   rut    1-10   texto
#   fecha  11-18  fecha AAAAMMDD
#   monto  19-30  decimal con 2 decimales implícitos
#   glosa  31-60  texto
#
# El emisor recorta los espacios finales de cada línea, así que las dos
# primeras llegan cortas. La tercera llena la glosa completa y llega entera.
fila_glosa = fn rut, fecha, monto, glosa ->
  String.pad_trailing(rut, 10) <>
    fecha <>
    String.pad_leading(monto, 12, "0") <>
    String.pad_trailing(glosa, 30)
end

escribir.(
  "nomina_glosa_recortada.txt",
  lineas.([
    String.trim_trailing(fila_glosa.("12345678-9", "20240115", "125000", "PAGO NOMINA ENERO")),
    String.trim_trailing(fila_glosa.("98765432-1", "20240115", "9990050", "ANTICIPO")),
    fila_glosa.("11111111-1", "20240116", "45", "REEMBOLSO GASTOS MENORES OK   ")
  ])
)

# El que "es de ancho fijo" y salió de un Excel.
escribir.("nomina_en_realidad_csv.csv", """
rut;beneficiario;monto;fecha
12345678-9;JUAN PEREZ SOTO;1250,00;15-01-2024
98765432-1;ANA MARIA ROJAS;99900,50;15-01-2024
11111111-1;PEDRO GONZALEZ;0,45;16-01-2024
""")

# Sin terminador final y con CRLF, como sale de un servidor Windows.
escribir.(
  "nomina_sin_terminador_final.txt",
  Enum.join(
    [
      fila.("12345678-9", "JUAN PEREZ SOTO", "125000", "20240115"),
      fila.("98765432-1", "ANA MARIA ROJAS", "9990050", "20240115")
    ],
    "\r\n"
  )
)

# Nómina multiregistro estilo banco chileno: header (01), detalles (02) y
# trailer (09) con cantidad y suma de montos. El header mide 40, el detalle
# 50 y el trailer 24: cada tipo tiene su propio largo.
header = fn empresa, fecha, glosa ->
  "01" <> String.pad_trailing(empresa, 10) <> fecha <> String.pad_trailing(glosa, 20)
end

detalle = fn rut, nombre, monto, cuenta ->
  "02" <>
    String.pad_trailing(rut, 10) <>
    String.pad_trailing(nombre, 20) <>
    String.pad_leading(monto, 10, "0") <> String.pad_leading(cuenta, 8, "0")
end

trailer = fn cantidad, total ->
  "09" <> String.pad_leading(cantidad, 6, "0") <> String.pad_leading(total, 16, "0")
end

# Los RUT llevan el dígito verificador correcto: en el multiregistro los
# campos son :rut y se validan al leer.
rut = fn cuerpo -> "#{cuerpo}-#{AnchoFijo.Rut.digito_verificador(cuerpo)}" end

detalles = [
  detalle.(rut.(12_345_678), "JUAN PEREZ SOTO", "125000", "11223344"),
  detalle.(rut.(98_765_432), "ANA MARIA ROJAS", "9990050", "55667788"),
  detalle.(rut.(11_111_111), "PEDRO GONZALEZ", "45", "99001122")
]

escribir.(
  "nomina_multiregistro.txt",
  lineas.(
    [header.(rut.(76_543_210), "20240115", "SUELDOS ENERO") | detalles] ++
      [trailer.("3", "10115095")]
  )
)

# Un archivo NACHA (ACH) de dos lotes PPD, uno de créditos y uno de débitos,
# con una addenda, los totales y el entry hash calculados como manda el
# Apéndice Tres, y el relleno de nueves hasta completar bloques de diez.
# Datos inventados: routing numbers con dígito verificador válido pero que no
# son de ningún banco, cuentas y nombres ficticios.
aba = fn ocho ->
  d = ocho |> String.graphemes() |> Enum.map(&String.to_integer/1)

  suma =
    3 * (Enum.at(d, 0) + Enum.at(d, 3) + Enum.at(d, 6)) +
      7 * (Enum.at(d, 1) + Enum.at(d, 4) + Enum.at(d, 7)) + (Enum.at(d, 2) + Enum.at(d, 5))

  ocho <> Integer.to_string(rem(10 - rem(suma, 10), 10))
end

izq = fn texto, largo -> String.pad_trailing(texto, largo) end
num = fn valor, largo -> String.pad_leading(Integer.to_string(valor), largo, "0") end

origen = "99100001"
destino = "99200002"

cabecera_archivo =
  "1" <>
    "01" <>
    " " <>
    aba.(destino) <>
    " " <>
    aba.(origen) <>
    "240115" <>
    "0930" <>
    "A" <>
    "094" <>
    "10" <>
    "1" <>
    izq.("BANCO DESTINO FICTICIO", 23) <> izq.("EMPRESA ORIGEN FICTICIA", 23) <> izq.("", 8)

cabecera_lote = fn numero, clase ->
  "5" <>
    num.(clase, 3) <>
    izq.("EMPRESA FICTICIA", 16) <>
    izq.("", 20) <>
    "1234567890" <>
    "PPD" <>
    izq.("SUELDOS", 10) <>
    "240115" <> "240116" <> "   " <> "1" <> origen <> num.(numero, 7)
end

entrada = fn codigo, routing, cuenta, centavos, nombre, addenda?, secuencia ->
  "6" <>
    num.(codigo, 2) <>
    aba.(routing) <>
    izq.(cuenta, 17) <>
    num.(centavos, 10) <>
    izq.("ID" <> num.(secuencia, 6), 15) <>
    izq.(nombre, 22) <> "  " <> if(addenda?, do: "1", else: "0") <> origen <> num.(secuencia, 7)
end

addenda = fn texto, secuencia ->
  "7" <> "05" <> izq.(texto, 80) <> "0001" <> num.(secuencia, 7)
end

control_lote = fn numero, clase, entradas, addendas, debito, credito ->
  hash =
    entradas
    |> Enum.map(fn {_c, routing, _cta, _ctv, _n, _a} -> String.to_integer(routing) end)
    |> Enum.sum()
    |> rem(10_000_000_000)

  "8" <>
    num.(clase, 3) <>
    num.(length(entradas) + addendas, 6) <>
    num.(hash, 10) <>
    num.(debito, 12) <>
    num.(credito, 12) <>
    "1234567890" <> izq.("", 19) <> izq.("", 6) <> origen <> num.(numero, 7)
end

lote1 = [
  {22, "99300003", "000123456789", 125_000, "JUAN PEREZ FICTICIO", true},
  {32, "99400004", "987654321", 9_990_050, "ANA ROJAS FICTICIA", false},
  {22, "99500005", "5550001", 45, "PEDRO GONZALEZ FICT", false}
]

lote2 = [
  {27, "99300003", "000123456789", 50_000, "JUAN PEREZ FICTICIO", false},
  {37, "99600006", "11112222", 7_500, "MARIA SOTO FICTICIA", false}
]

lineas_lote1 =
  [cabecera_lote.(1, 220)] ++
    Enum.flat_map(Enum.with_index(lote1, 1), fn {{c, r, cta, ctv, n, a?}, i} ->
      [entrada.(c, r, cta, ctv, n, a?, i)] ++
        if(a?, do: [addenda.("PAGO DE SUELDO ENERO 2024", i)], else: [])
    end) ++
    [control_lote.(1, 220, lote1, 1, 0, Enum.sum(Enum.map(lote1, &elem(&1, 3))))]

lineas_lote2 =
  [cabecera_lote.(2, 225)] ++
    Enum.map(Enum.with_index(lote2, 4), fn {{c, r, cta, ctv, n, a?}, i} ->
      entrada.(c, r, cta, ctv, n, a?, i)
    end) ++
    [control_lote.(2, 225, lote2, 0, Enum.sum(Enum.map(lote2, &elem(&1, 3))), 0)]

hash_archivo =
  [lote1, lote2]
  |> Enum.map(fn l ->
    l
    |> Enum.map(fn {_c, r, _, _, _, _} -> String.to_integer(r) end)
    |> Enum.sum()
    |> rem(10_000_000_000)
  end)
  |> Enum.sum()
  |> rem(10_000_000_000)

cuerpo = [cabecera_archivo] ++ lineas_lote1 ++ lineas_lote2
sin_relleno = length(cuerpo) + 1
bloques = div(sin_relleno + 9, 10)

control_archivo =
  "9" <>
    num.(2, 6) <>
    num.(bloques, 6) <>
    num.(length(lote1) + 1 + length(lote2), 8) <>
    num.(hash_archivo, 10) <>
    num.(Enum.sum(Enum.map(lote2, &elem(&1, 3))), 12) <>
    num.(Enum.sum(Enum.map(lote1, &elem(&1, 3))), 12) <> izq.("", 39)

relleno = List.duplicate(String.duplicate("9", 94), bloques * 10 - sin_relleno)

escribir.("nacha_ppd.txt", lineas.(cuerpo ++ [control_archivo] ++ relleno))
