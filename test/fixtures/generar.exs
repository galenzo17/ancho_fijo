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
