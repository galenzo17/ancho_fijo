defmodule AnchoFijo.Formatos.Cuaderno43Test do
  use ExUnit.Case, async: true

  import AnchoFijo.Fixtures, only: [ruta: 1, leer: 1]

  alias AnchoFijo.Diagnostico
  alias AnchoFijo.Formatos
  alias AnchoFijo.Formatos.Cuaderno43

  describe "el fixture, de punta a punta" do
    test "se lee con el multiregistro, cuadra y se agrupa en cuentas" do
      assert {:ok, registros, []} = AnchoFijo.parsear(Formatos.cuaderno43(), ruta("cuaderno43.txt"))

      tipos = Enum.map(registros, &elem(&1, 0))
      assert Enum.count(tipos, &(&1 == :cabecera_de_cuenta)) == 2
      assert Enum.count(tipos, &(&1 == :movimiento)) == 4
      assert Enum.count(tipos, &(&1 == :concepto_complementario)) == 2
      assert Enum.count(tipos, &(&1 == :equivalencia_de_importe)) == 1
      assert Enum.count(tipos, &(&1 == :final_de_cuenta)) == 2
      assert List.last(tipos) == :fin_de_fichero
      assert length(registros) == 12

      assert Cuaderno43.validar(registros) == []

      [primera, segunda] = Cuaderno43.cuentas(registros)
      assert primera.cabecera.numero_de_cuenta == "0200051332"
      assert primera.cabecera.fecha_inicial == ~D[2024-01-01]
      assert primera.cabecera.importe_saldo_inicial == {150_000, 2}
      assert [luz, transferencia, comision] = primera.movimientos
      assert luz.movimiento.importe == {25_050, 2}
      assert luz.movimiento.clave_debe_haber == "1"

      assert [%{codigo_de_dato: "01", concepto_1: "RECIBO LUZ ENERO 2024"}, %{codigo_de_dato: "02"}] =
               luz.conceptos

      assert [%{clave_divisa_origen: "840", importe: {348_000, 2}}] = transferencia.equivalencias
      assert comision.conceptos == [] and comision.equivalencias == []
      assert primera.final.importe_saldo_final == {443_750, 2}

      assert segunda.cabecera.clave_debe_haber == "1"

      assert Cuaderno43.saldo(segunda.final.codigo_saldo_final, segunda.final.importe_saldo_final) ==
               40_000
    end

    test "en el stream también, y la identidad es la cuenta con sus fechas" do
      resultados =
        Formatos.cuaderno43() |> AnchoFijo.stream(ruta("cuaderno43.txt")) |> Enum.to_list()

      assert Enum.all?(resultados, &match?({:ok, _, _}, &1))

      assert {:ok, identidad} = AnchoFijo.identidad(Formatos.cuaderno43(), ruta("cuaderno43.txt"))
      assert identidad.declarada.clave_entidad == "2100"
      assert identidad.declarada.numero_de_cuenta == "0200051332"
      assert identidad.declarada.fecha_final == ~D[2024-01-31]
    end

    test "cada registro mide 80 y el archivo hace el viaje de ida y vuelta" do
      contenido = leer("cuaderno43.txt")
      for linea <- String.split(contenido, "\n", trim: true), do: assert(byte_size(linea) == 80)

      {:ok, registros, []} = AnchoFijo.parsear(Formatos.cuaderno43(), contenido)
      assert {:ok, ^contenido, []} = AnchoFijo.escribir(Formatos.cuaderno43(), registros)
    end
  end

  describe "validar/1 sobre un extracto alterado" do
    defp alterado(fun) do
      {:ok, registros, []} = AnchoFijo.parsear(Formatos.cuaderno43(), ruta("cuaderno43.txt"))
      registros |> fun.() |> Cuaderno43.validar()
    end

    defp cambiar(registros, tipo, campo, fun, cual \\ 0) do
      {registros, _} =
        Enum.map_reduce(registros, 0, fn
          {^tipo, r}, ^cual -> {{tipo, Map.update!(r, campo, fun)}, cual + 1}
          {^tipo, r}, n -> {{tipo, r}, n + 1}
          otro, n -> {otro, n}
        end)

      registros
    end

    test "un saldo final alterado se detecta, con la línea del final de cuenta" do
      assert [%Diagnostico{tipo: :control, campo: :importe_saldo_final, linea: 8} = d] =
               alterado(
                 &cambiar(&1, :final_de_cuenta, :importe_saldo_final, fn {c, 2} -> {c + 1, 2} end)
               )

      assert d.esperado =~ "443750, que es el saldo inicial más el haber menos el debe"
      assert d.recibido == "443751"
    end

    test "un importe alterado desbalancea el total y el saldo" do
      diagnosticos = alterado(&cambiar(&1, :movimiento, :importe, fn {c, 2} -> {c + 100, 2} end))
      assert Enum.map(diagnosticos, & &1.campo) == [:total_importes_debe, :importe_saldo_final]
    end

    test "la cuenta del final tiene que ser la de la cabecera, y el 88 contar los registros" do
      assert [%Diagnostico{campo: :numero_de_cuenta, linea: 11}] =
               alterado(
                 &cambiar(&1, :final_de_cuenta, :numero_de_cuenta, fn _ -> "0000000000" end, 1)
               )

      assert [%Diagnostico{campo: :numero_de_registros, linea: 12} = d] =
               alterado(&cambiar(&1, :fin_de_fichero, :numero_de_registros, fn _ -> 10 end))

      assert d.esperado == "11, que es los registros anteriores al 88"
    end

    test "la estructura: un movimiento sin cuenta, un concepto sin movimiento, una cuenta sin cerrar" do
      # Sin la primera cabecera: el movimiento, sus complementarios y el final quedan sueltos, y el 88 no cuadra.
      assert [%Diagnostico{tipo: :estructura, linea: 1} = d | resto] = alterado(&tl/1)
      assert d.recibido == "un movimiento fuera de una cuenta"
      assert Enum.any?(resto, &(&1.recibido == "un final de cuenta sin cabecera"))
      assert Enum.any?(resto, &(&1.campo == :numero_de_registros))

      sin_movimiento = fn registros ->
        Enum.reject(registros, &match?({:movimiento, %{numero_de_documento: "0000000001"}}, &1))
      end

      diagnosticos = alterado(sin_movimiento)

      assert Enum.any?(
               diagnosticos,
               &(&1.tipo == :estructura and &1.recibido =~ "concepto complementario sin movimiento")
             )

      sin_final = fn registros ->
        Enum.reject(registros, &match?({:final_de_cuenta, %{numero_de_cuenta: "0123456789"}}, &1))
      end

      assert Enum.any?(alterado(sin_final), &(&1.recibido =~ "cuenta sin cerrar"))
    end
  end

  describe "catálogo" do
    test "la vigencia 2012 está, con su fuente" do
      assert Formatos.catalogo().cuaderno43.vigencias == ["2012"]
      assert Formatos.catalogo().cuaderno43.fuente =~ "Cuaderno 43"
      assert_raise ArgumentError, fn -> Formatos.cuaderno43(vigencia: "1999") end
    end
  end
end
