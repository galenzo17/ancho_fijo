defmodule AnchoFijo.Formatos.NachaTest do
  use ExUnit.Case, async: true

  import AnchoFijo.Fixtures, only: [ruta: 1, leer: 1]

  alias AnchoFijo.Diagnostico
  alias AnchoFijo.Formatos
  alias AnchoFijo.Formatos.Nacha

  describe "el fixture, de punta a punta" do
    test "se lee con el multiregistro, cuadra y se agrupa en lotes" do
      assert {:ok, registros, []} = AnchoFijo.parsear(Formatos.nacha(), ruta("nacha_ppd.txt"))

      tipos = Enum.map(registros, &elem(&1, 0))
      assert hd(tipos) == :encabezado_de_archivo
      assert Enum.count(tipos, &(&1 == :encabezado_de_lote)) == 2
      assert Enum.count(tipos, &(&1 == :entrada)) == 5
      assert Enum.count(tipos, &(&1 == :addenda)) == 1
      assert Enum.count(tipos, &(&1 == :control_de_lote)) == 2
      assert Enum.count(tipos, &(&1 == :control_de_archivo)) == 1
      assert Enum.any?(tipos, &(&1 == :relleno))
      assert length(registros) == 20

      assert Nacha.validar(registros) == []

      [creditos, debitos] = Nacha.lotes(registros)
      assert creditos.encabezado.service_class_code == 220
      assert creditos.encabezado.standard_entry_class_code == "PPD"
      assert length(creditos.entradas) == 3
      assert [%{addendas: [addenda]}] = Enum.filter(creditos.entradas, &(&1.addendas != []))
      assert addenda.payment_related_information =~ "PAGO"

      assert creditos.control.total_credit_entry_dollar_amount ==
               {Enum.sum(Enum.map(creditos.entradas, fn e -> elem(e.entrada.amount, 0) end)), 2}

      assert debitos.encabezado.service_class_code == 225
      assert length(debitos.entradas) == 2

      assert debitos.control.total_debit_entry_dollar_amount ==
               {Enum.sum(Enum.map(debitos.entradas, fn e -> elem(e.entrada.amount, 0) end)), 2}
    end

    test "en el stream también, con los controles de estructura al final" do
      resultados = Formatos.nacha() |> AnchoFijo.stream(ruta("nacha_ppd.txt")) |> Enum.to_list()
      assert Enum.all?(resultados, &match?({:ok, _, _}, &1))
    end

    test "cada registro mide 94" do
      for linea <- String.split(leer("nacha_ppd.txt"), "\n", trim: true),
          do: assert(byte_size(linea) == 94)
    end
  end

  describe "validar/1 sobre un archivo alterado" do
    defp alterado(fun) do
      {:ok, registros, []} = AnchoFijo.parsear(Formatos.nacha(), ruta("nacha_ppd.txt"))
      registros |> fun.() |> Nacha.validar()
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

    test "un monto alterado desbalancea el total del lote y el del archivo" do
      diagnosticos = alterado(&cambiar(&1, :entrada, :amount, fn {c, 2} -> {c + 1, 2} end))

      assert [lote, archivo] = diagnosticos
      assert %Diagnostico{tipo: :control, campo: :total_credit_entry_dollar_amount} = lote
      assert lote.esperado =~ "la suma de los montos con código de transacción de crédito"
      assert %Diagnostico{tipo: :control, campo: :total_credit_entry_dollar_amount} = archivo
      assert archivo.esperado =~ "de todos los lotes"
    end

    test "un routing number alterado rompe el entry hash del lote y del archivo" do
      diagnosticos =
        alterado(&cambiar(&1, :entrada, :receiving_dfi_identification, fn n -> n + 10 end))

      assert Enum.map(diagnosticos, & &1.campo) == [:entry_hash, :entry_hash]
    end

    test "una addenda de más desbalancea las cuentas" do
      diagnosticos =
        alterado(fn registros ->
          {indice, {:addenda, addenda}} =
            registros
            |> Enum.with_index()
            |> Enum.find(fn {{t, _}, _} -> t == :addenda end)
            |> then(fn {r, i} -> {i, r} end)

          List.insert_at(registros, indice, {:addenda, addenda})
        end)

      assert Enum.map(diagnosticos, & &1.campo) == [:entry_addenda_count, :entry_addenda_count]
    end

    test "un service class code que no coincide entre encabezado y control" do
      diagnosticos = alterado(&cambiar(&1, :control_de_lote, :service_class_code, fn _ -> 200 end))
      assert [%Diagnostico{campo: :service_class_code, linea: linea}] = diagnosticos
      assert is_integer(linea)
    end

    test "un control de archivo con la cuenta de lotes mal" do
      diagnosticos = alterado(&cambiar(&1, :control_de_archivo, :batch_count, fn _ -> 9 end))

      assert [
               %Diagnostico{
                 campo: :batch_count,
                 recibido: "9",
                 esperado: "2 en :batch_count, la cantidad de lotes cerrados"
               }
             ] = diagnosticos
    end

    test "la estructura de los lotes: entrada fuera de lote y lote sin cerrar" do
      {:ok, registros, []} = AnchoFijo.parsear(Formatos.nacha(), ruta("nacha_ppd.txt"))
      [archivo, lote1 | resto] = registros
      {:entrada, entrada} = Enum.find(registros, &match?({:entrada, _}, &1))

      fuera = Nacha.validar([archivo, {:entrada, entrada}, lote1 | resto])

      assert [
               %Diagnostico{tipo: :estructura, linea: 2, recibido: "una entrada fuera de un lote"}
               | _
             ] = fuera

      sin_cerrar = Nacha.validar(Enum.reject(registros, &match?({:control_de_lote, _}, &1)))
      assert Enum.any?(sin_cerrar, &(&1.tipo == :estructura and &1.recibido =~ "sin cerrar"))
    end

    test "sin relleno el bloque cuenta igual, y el relleno no cuenta" do
      {:ok, registros, []} = AnchoFijo.parsear(Formatos.nacha(), ruta("nacha_ppd.txt"))
      assert Nacha.validar(Enum.reject(registros, &match?({:relleno, _}, &1))) == []
    end
  end

  describe "el catálogo" do
    test "lista la vigencia, la fuente y la fecha de consulta" do
      assert %{nacha: %{vigencias: ["2021"], fuente: fuente, consultado: %Date{}}} =
               Formatos.catalogo()

      assert fuente =~ "Appendix Three"
      assert fuente =~ "achdevguide.nacha.org"
    end

    test "una vigencia que no existe es ArgumentError" do
      assert_raise ArgumentError, ~r/no está en el catálogo/, fn ->
        Formatos.nacha(vigencia: "1999")
      end
    end

    test "el encabezado de archivo declara la identidad del archivo" do
      assert Nacha.encabezado_de_archivo().identidad == %{
               campos: [
                 :immediate_origin,
                 :file_creation_date,
                 :file_creation_time,
                 :file_id_modifier
               ]
             }
    end

    test "los nombres de los campos son los de la especificación" do
      assert Enum.map(Nacha.entrada().campos, & &1.nombre) == [
               :record_type_code,
               :transaction_code,
               :receiving_dfi_identification,
               :check_digit,
               :dfi_account_number,
               :amount,
               :individual_identification_number,
               :individual_name,
               :discretionary_data,
               :addenda_record_indicator,
               :trace_number
             ]

      assert AnchoFijo.Layout.campo(Nacha.entrada(), :amount) |> AnchoFijo.Campo.rango() == {30, 39}

      assert AnchoFijo.Layout.campo(Nacha.control_de_archivo(), :entry_hash)
             |> AnchoFijo.Campo.rango() == {22, 31}
    end
  end
end
