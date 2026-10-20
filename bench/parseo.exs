# Benchmark de parsear/3 contra stream/3 sobre un archivo grande.
#
#     mix run bench/generar.exs
#     mix run bench/parseo.exs                 # bench/datos/nomina_100mb.txt
#     mix run bench/parseo.exs ruta/otro.txt
#
# Dos mediciones, porque miden cosas distintas:
#
# 1. Benchee: tiempo y throughput de cada camino, en modo estricto y
#    tolerante. La memoria que reporta Benchee es la *asignada* por el
#    proceso durante la corrida, no la retenida: para un stream de dos
#    millones de líneas es un número grande aunque nunca haya más de una
#    línea viva, así que no se usa para la pregunta de memoria constante.
#
# 2. Pico de memoria: la tarea corre en un proceso aparte y otro proceso
#    muestrea su heap cada 10 ms. El máximo es lo que de verdad ocupa cada
#    camino. Es la cifra que responde "¿cabe un archivo de 2 GB?".

ruta =
  case System.argv() do
    [ruta] -> ruta
    _ -> Path.join([__DIR__, "datos", "nomina_100mb.txt"])
  end

unless File.regular?(ruta) do
  IO.puts("no existe #{ruta}; genere el archivo con: mix run bench/generar.exs")
  System.halt(1)
end

layout =
  AnchoFijo.Layout.nuevo!(
    nombre: "nómina de benchmark",
    campos: [
      [nombre: :rut, largo: 10],
      [nombre: :beneficiario, largo: 20],
      [nombre: :monto, largo: 10, tipo: :decimal, precision: 2],
      [nombre: :fecha, largo: 8, tipo: :fecha, formato: :aaaammdd]
    ]
  )

bytes = File.stat!(ruta).size
mb = Float.round(bytes / 1_000_000, 1)
IO.puts("archivo: #{ruta} (#{mb} MB)\n")

# Lo que cada camino devuelve se reduce a cuentas para que el resultado no
# quede retenido por el benchmark mismo.
contar_stream = fn stream ->
  Enum.reduce(stream, {0, 0}, fn
    {:ok, _registro, _advertencias}, {ok, err} -> {ok + 1, err}
    {:error, _diagnosticos}, {ok, err} -> {ok, err + 1}
  end)
end

escenarios = %{
  "parsear/3 estricto (corta en la primera fila mala)" => fn ->
    {:error, diagnosticos} = AnchoFijo.parsear(layout, ruta)
    length(diagnosticos)
  end,
  "parsear/3 tolerante (todo el archivo en memoria)" => fn ->
    {:ok, registros, diagnosticos} = AnchoFijo.parsear(layout, ruta, modo: :tolerante)
    {length(registros), length(diagnosticos)}
  end,
  "stream/3 sobre File.stream!/1" => fn ->
    ruta |> File.stream!() |> then(&AnchoFijo.stream(layout, &1)) |> contar_stream.()
  end,
  "stream/3 sobre la ruta" => fn ->
    layout |> AnchoFijo.stream(ruta) |> contar_stream.()
  end
}

IO.puts("== Benchee: tiempo ==\n")

Benchee.run(escenarios,
  warmup: 1,
  time: 5,
  memory_time: 0,
  print: [configuration: false],
  formatters: [{Benchee.Formatters.Console, comparison: true, extended_statistics: false}]
)

IO.puts("\n== Pico de memoria del proceso (heap muestreado cada 10 ms) ==\n")

pico = fn fun ->
  padre = self()

  pid =
    spawn(fn ->
      receive do
        :ya -> send(padre, {:listo, fun.()})
      end
    end)

  muestreador =
    spawn(fn ->
      medir = fn medir, maximo ->
        receive do
          :parar -> send(padre, {:pico, maximo})
        after
          10 ->
            actual =
              case Process.info(pid, :total_heap_size) do
                {:total_heap_size, palabras} -> palabras * :erlang.system_info(:wordsize)
                nil -> 0
              end

            medir.(medir, max(maximo, actual))
        end
      end

      medir.(medir, 0)
    end)

  send(pid, :ya)

  receive do
    {:listo, _resultado} -> :ok
  end

  send(muestreador, :parar)

  receive do
    {:pico, maximo} -> maximo
  end
end

for {nombre, fun} <- Enum.sort(escenarios) do
  :erlang.garbage_collect()
  maximo = pico.(fun)
  legible = if maximo < 1_000_000, do: "#{div(maximo, 1000)} KB", else: "#{Float.round(maximo / 1_000_000, 1)} MB"
  IO.puts(String.pad_trailing(nombre, 52) <> String.pad_leading(legible, 12))
end

IO.puts("\n(archivo de #{mb} MB; un camino de memoria constante no debería depender de ese número)")
