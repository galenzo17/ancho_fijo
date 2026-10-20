defmodule AnchoFijo.TrazaTest do
  use ExUnit.Case, async: true

  import AnchoFijo.Fixtures, only: [ruta: 1, leer: 1, layout_nomina: 0]

  alias AnchoFijo.Layout
  alias AnchoFijo.Traza

  @layout Layout.nuevo!(campos: [[nombre: :codigo, largo: 3, tipo: :entero]])

  # Con cada terminador, la traza de cada registro reconstruye su línea con
  # :binary.part/3 sobre el contenido original.
  defp verificar_reconstruccion(contenido, opts \\ []) do
    {:ok, registros, _} = AnchoFijo.parsear(@layout, contenido, [traza: true] ++ opts)
    assert registros != []

    for registro <- registros do
      traza = registro.__traza__
      assert %Traza{} = traza

      assert Traza.linea_original(traza, contenido) ==
               String.pad_leading("#{registro.codigo}", 3, "0")

      assert :binary.part(contenido, traza.offset, traza.largo) ==
               Traza.linea_original(traza, contenido)
    end

    registros
  end

  describe "parsear/3 con traza: true" do
    test "LF" do
      [r1, r2, r3] = verificar_reconstruccion("001\n002\n003\n")

      assert Enum.map([r1, r2, r3], & &1.__traza__) == [
               Traza.nueva(1, 0, 3),
               Traza.nueva(2, 4, 3),
               Traza.nueva(3, 8, 3)
             ]
    end

    test "CRLF" do
      [_, r2, _] = verificar_reconstruccion("001\r\n002\r\n003\r\n")
      assert r2.__traza__ == Traza.nueva(2, 5, 3)
    end

    test "CR solo" do
      [_, _, r3] = verificar_reconstruccion("001\r002\r003\r")
      assert r3.__traza__ == Traza.nueva(3, 8, 3)
    end

    test "sin terminador final" do
      [_, _, r3] = verificar_reconstruccion("001\n002\n003")
      assert r3.__traza__ == Traza.nueva(3, 8, 3)
    end

    test "terminadores mezclados" do
      [_, r2, r3] = verificar_reconstruccion("001\r\n002\n003\r")
      assert {r2.__traza__.offset, r3.__traza__.offset} == {5, 9}
    end

    test ":saltar y :omitir_vacias no corren la numeración ni los offsets" do
      contenido = "cabecera\n001\n\n002\n"
      [r1, r2] = verificar_reconstruccion(contenido, saltar: 1)

      assert r1.__traza__ == Traza.nueva(2, 9, 3)
      assert r2.__traza__ == Traza.nueva(4, 14, 3)
    end

    test "el registro sigue siendo el mapa de siempre más la clave reservada" do
      {:ok, [registro], []} = AnchoFijo.parsear(@layout, "001\n", traza: true)

      assert registro.codigo == 1
      assert Enum.sort(Map.keys(registro)) == [:__traza__, :codigo]
      assert Map.delete(registro, :__traza__) == %{codigo: 1}
    end

    test "sobre un fixture real, con un layout de verdad" do
      contenido = leer("nomina_correcta.txt")

      {:ok, registros, []} =
        AnchoFijo.parsear(layout_nomina(), ruta("nomina_correcta.txt"), traza: true)

      assert length(registros) == 3

      for registro <- registros do
        linea = Traza.linea_original(registro.__traza__, contenido)
        assert byte_size(linea) == 48

        assert {:ok, ^registro, []} =
                 AnchoFijo.parsear(layout_nomina(), linea, traza: true)
                 |> poner_traza(registro.__traza__)
      end
    end

    # La línea suelta parsea igual; solo cambia la traza, que es relativa al
    # contenido que se parseó. Se repone la original para comparar.
    defp poner_traza({:ok, [registro], []}, traza),
      do: {:ok, Map.put(registro, :__traza__, traza), []}
  end

  describe "sin traza" do
    test "la forma de retorno no cambia y no hay clave reservada" do
      {:ok, [registro], []} = AnchoFijo.parsear(@layout, "001\n")
      assert registro == %{codigo: 1}

      [{:ok, registro, []}] = AnchoFijo.stream(@layout, "001\n") |> Enum.to_list()
      assert registro == %{codigo: 1}
    end

    test "un campo no se puede llamar :__traza__" do
      assert {:error, [diagnostico]} = Layout.nuevo(campos: [[nombre: :__traza__, largo: 3]])
      assert diagnostico.causa_probable =~ "clave reservada para la traza"
    end
  end

  describe "stream/3 con traza: true" do
    test "sobre un binario, los offsets son los mismos que en parsear/3" do
      contenido = "001\r\n002\r\n003"
      {:ok, esperados, []} = AnchoFijo.parsear(@layout, contenido, traza: true)

      obtenidos =
        AnchoFijo.stream(@layout, contenido, traza: true)
        |> Enum.map(fn {:ok, registro, []} -> registro end)

      assert obtenidos == esperados
    end

    test "sobre una ruta con LF, CRLF y CR: los bloques se parten byte a byte" do
      for terminador <- ["\n", "\r\n", "\r"] do
        ruta = Path.join(System.tmp_dir!(), "traza_#{System.unique_integer([:positive])}.txt")
        contenido = Enum.map_join(1..50, "", &(String.pad_leading("#{&1}", 3, "0") <> terminador))
        File.write!(ruta, contenido)
        on_exit(fn -> File.rm(ruta) end)

        registros =
          AnchoFijo.stream(@layout, ruta, traza: true)
          |> Enum.map(fn {:ok, registro, []} -> registro end)

        assert length(registros) == 50

        for registro <- registros do
          assert Traza.linea_original(registro.__traza__, contenido) ==
                   String.pad_leading("#{registro.codigo}", 3, "0")
        end

        assert List.last(registros).__traza__.linea == 50
      end
    end

    test "un CRLF partido entre dos bloques no corre los offsets" do
      # Bloques de 64 KB: una línea de 3 bytes más CRLF cae partida muchas veces.
      ruta = Path.join(System.tmp_dir!(), "traza_grande_#{System.unique_integer([:positive])}.txt")

      contenido =
        Enum.map_join(1..30_000, "", &(String.pad_leading("#{rem(&1, 1000)}", 3, "0") <> "\r\n"))

      File.write!(ruta, contenido)
      on_exit(fn -> File.rm(ruta) end)

      ultimo =
        AnchoFijo.stream(@layout, ruta, traza: true)
        |> Enum.reduce(nil, fn {:ok, registro, []}, _ -> registro end)

      assert ultimo.__traza__ == Traza.nueva(30_000, 29_999 * 5, 3)
      assert Traza.linea_original(ultimo.__traza__, contenido) == "000"
    end

    test "con un File.Stream ajeno sobre LF los offsets cuadran" do
      ruta = Path.join(System.tmp_dir!(), "traza_lf_#{System.unique_integer([:positive])}.txt")
      contenido = "001\n002\n003\n"
      File.write!(ruta, contenido)
      on_exit(fn -> File.rm(ruta) end)

      [_, r2, _] =
        ruta
        |> File.stream!()
        |> then(&AnchoFijo.stream(@layout, &1, traza: true))
        |> Enum.map(fn {:ok, registro, []} -> registro end)

      assert r2.__traza__ == Traza.nueva(2, 4, 3)
    end

    test "sobre una ruta, con :saltar" do
      registros =
        AnchoFijo.stream(@layout, ruta("nomina_correcta.txt") |> tap(&File.regular?/1), traza: true)
        |> Enum.map(fn
          {:ok, _, _} = ok -> ok
          {:error, _} = e -> e
        end)

      # El layout de 3 posiciones no calza con el fixture: todas son errores,
      # pero los números de línea en los diagnósticos siguen bien.
      assert Enum.map(registros, fn {:error, [d]} -> d.linea end) == [1, 2, 3]
    end
  end

  describe "huella/2" do
    test "es estable entre corridas y entre binario y ruta" do
      {:ok, a} = AnchoFijo.huella(leer("nomina_correcta.txt"))
      {:ok, b} = AnchoFijo.huella(leer("nomina_correcta.txt"))
      {:ok, c} = AnchoFijo.huella(ruta("nomina_correcta.txt"))

      assert a == b and b == c
      assert a =~ ~r/^sha256:[0-9a-f]{64}$/
    end

    test "cambia con cualquier byte de datos" do
      {:ok, a} = AnchoFijo.huella("001\n002\n")
      {:ok, b} = AnchoFijo.huella("001\n003\n")
      {:ok, c} = AnchoFijo.huella("001\n002 \n")
      assert length(Enum.uniq([a, b, c])) == 3
    end

    test "no cambia con el estilo de terminador ni con el terminador final" do
      {:ok, referencia} = AnchoFijo.huella("001\n002\n")

      for variante <- ["001\r\n002\r\n", "001\r002\r", "001\n002", "001\r\n002", "001\r002"] do
        assert {:ok, ^referencia} = AnchoFijo.huella(variante), inspect(variante)
      end
    end

    test "un CRLF partido entre dos bloques se normaliza igual" do
      {:ok, referencia} = AnchoFijo.huella("001\n002\n")

      assert {:ok, ^referencia} = AnchoFijo.huella(["001\r", "\n002\r\n"])
      assert {:ok, ^referencia} = AnchoFijo.huella(["001", "\r\n", "002", "\r"])
      assert {:ok, ^referencia} = AnchoFijo.huella(["0", "01\n0", "02"])
    end

    test "el vacío tiene huella y es distinta de un salto de línea solo" do
      {:ok, vacio} = AnchoFijo.huella("")
      {:ok, salto} = AnchoFijo.huella("\n")
      assert vacio != salto
      assert vacio == "sha256:" <> Base.encode16(:crypto.hash(:sha256, ""), case: :lower)
    end

    test "normalizar: false es el hash de los bytes exactos" do
      contenido = leer("nomina_latin1.txt")
      {:ok, "sha256:" <> hex} = AnchoFijo.huella(contenido, normalizar: false)
      assert hex == Base.encode16(:crypto.hash(:sha256, contenido), case: :lower)

      {:ok, a} = AnchoFijo.huella("001\n", normalizar: false)
      {:ok, b} = AnchoFijo.huella("001\r\n", normalizar: false)
      assert a != b
    end

    test "una ruta ilegible es un diagnóstico" do
      assert {:error, [%AnchoFijo.Diagnostico{tipo: :entrada}]} =
               AnchoFijo.huella("/no/existe.txt", desde: :archivo)
    end
  end
end
