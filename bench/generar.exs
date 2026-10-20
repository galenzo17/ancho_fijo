# Genera un archivo de nómina grande para los benchmarks.
#
#     mix run bench/generar.exs            # 100 MB en bench/datos/nomina_100mb.txt
#     mix run bench/generar.exs 1000       # 1 GB en bench/datos/nomina_1000mb.txt
#
# Las líneas tienen el layout de los fixtures de test (48 posiciones más el
# salto): rut, beneficiario, monto con dos decimales implícitos y fecha. Una
# de cada mil líneas trae un monto con letras, para que el modo tolerante
# tenga algo que reportar y el estricto corte en la primera. Los archivos van
# a bench/datos/, que está en .gitignore.

megabytes =
  case System.argv() do
    [mb] -> String.to_integer(mb)
    _ -> 100
  end

destino = Path.join([__DIR__, "datos", "nomina_#{megabytes}mb.txt"])
File.mkdir_p!(Path.dirname(destino))

largo_linea = 49
lineas = div(megabytes * 1_000_000, largo_linea)

fila = fn n ->
  cuerpo = 10_000_000 + rem(n * 7919, 80_000_000)
  dv = AnchoFijo.Rut.digito_verificador(cuerpo)
  rut = "#{cuerpo}-#{dv}"
  nombre = String.pad_trailing("BENEFICIARIO #{rem(n, 100_000)}", 20)
  monto = if rem(n, 1000) == 999, do: "0000ABC000", else: String.pad_leading("#{rem(n * 137, 99_999_999)}", 10, "0")
  fecha = "2024" <> String.pad_leading("#{rem(n, 12) + 1}", 2, "0") <> String.pad_leading("#{rem(n, 28) + 1}", 2, "0")
  rut <> nombre <> monto <> fecha <> "\n"
end

{tiempo, _} =
  :timer.tc(fn ->
    File.open!(destino, [:write, :binary, :delayed_write], fn archivo ->
      1..lineas
      |> Stream.map(fila)
      |> Stream.chunk_every(10_000)
      |> Enum.each(fn trozo -> IO.binwrite(archivo, trozo) end)
    end)
  end)

IO.puts("#{destino}: #{lineas} líneas, #{File.stat!(destino).size} bytes, en #{div(tiempo, 1000)} ms")
