defmodule AnchoFijo.IdentidadTest do
  use ExUnit.Case, async: true

  import AnchoFijo.Fixtures, only: [ruta: 1, leer: 1, layout_nomina: 0, layout_nomina: 1]

  alias AnchoFijo.Diagnostico
  alias AnchoFijo.Identidad
  alias AnchoFijo.Layout

  @layout Layout.nuevo!(
            identidad: [campos: [:lote, :fecha]],
            campos: [
              [nombre: :lote, largo: 4, tipo: :entero],
              [nombre: :fecha, largo: 8, tipo: :fecha, formato: :aaaammdd],
              [nombre: :monto, largo: 6, tipo: :entero]
            ]
          )

  @archivo "000120240115001000\n000120240115002500\n"

  describe "identidad/3" do
    test "trae lo declarado por el primer registro, la huella y el nombre" do
      ruta = Path.join(System.tmp_dir!(), "nomina_lote_#{System.unique_integer([:positive])}.txt")
      File.write!(ruta, @archivo)
      on_exit(fn -> File.rm(ruta) end)

      assert {:ok, identidad} = AnchoFijo.identidad(@layout, ruta)
      assert identidad.declarada == %{lote: 1, fecha: ~D[2024-01-15]}
      assert identidad.huella =~ ~r/^sha256:[0-9a-f]{64}$/
      assert identidad.nombre == Path.basename(ruta)

      assert {:ok, por_contenido} = AnchoFijo.identidad(@layout, @archivo)
      assert por_contenido.nombre == nil
      assert por_contenido.huella == identidad.huella
    end

    test "sin :identidad en el layout, la identidad es la huella" do
      assert {:ok, identidad} = AnchoFijo.identidad(layout_nomina(), ruta("nomina_correcta.txt"))
      assert identidad.declarada == nil
      assert {:ok, ^identidad} = AnchoFijo.identidad(layout_nomina(), ruta("nomina_correcta.txt"))
    end

    test "la huella no cambia con el terminador; lo declarado tampoco" do
      {:ok, a} = AnchoFijo.identidad(@layout, @archivo)
      {:ok, b} = AnchoFijo.identidad(@layout, String.replace(@archivo, "\n", "\r\n"))
      assert a == b
    end

    test "un primer registro ilegible es el diagnóstico de la línea" do
      assert {:error, [%Diagnostico{linea: 1, campo: :lote}]} =
               AnchoFijo.identidad(@layout, "XXXX20240115001000\n")
    end

    test "un archivo vacío no tiene lote que identificar" do
      assert {:error, [%Diagnostico{tipo: :identidad} = d]} = AnchoFijo.identidad(@layout, "")
      assert d.causa_probable =~ "está vacío"
    end

    test ":saltar también aplica al primer registro" do
      assert {:ok, identidad} =
               AnchoFijo.identidad(@layout, "CABECERA LIBRE\n" <> @archivo, saltar: 1)

      assert identidad.declarada.lote == 1
    end

    test "el layout valida que los campos de identidad existan" do
      assert {:error, [d]} =
               Layout.nuevo(identidad: [campos: [:lote, :zzz]], campos: [[nombre: :lote, largo: 4]])

      assert d.recibido == "[:zzz]"

      assert {:error, [d]} =
               Layout.nuevo(identidad: [campos: []], campos: [[nombre: :lote, largo: 4]])

      assert d.esperado =~ "al menos un campo"

      assert {:error, [_]} = Layout.nuevo(identidad: :lote, campos: [[nombre: :lote, largo: 4]])
    end
  end

  describe "identidad/3 con un Multiregistro" do
    test "la identidad declarada sale del header NACHA" do
      assert {:ok, identidad} =
               AnchoFijo.identidad(AnchoFijo.Formatos.nacha(), ruta("nacha_ppd.txt"))

      assert identidad.declarada == %{
               immediate_origin: "991000012",
               file_creation_date: "240115",
               file_creation_time: "0930",
               file_id_modifier: "A"
             }

      assert identidad.nombre == "nacha_ppd.txt"
      assert {:ok, por_huella} = AnchoFijo.huella(ruta("nacha_ppd.txt"))
      assert identidad.huella == por_huella
    end

    test "un archivo que no empieza por el tipo que declara la identidad es un diagnóstico" do
      sin_header = leer("nacha_ppd.txt") |> String.split("\n") |> Enum.drop(1) |> Enum.join("\n")

      assert {:error, [%Diagnostico{tipo: :identidad, linea: 1} = d]} =
               AnchoFijo.identidad(AnchoFijo.Formatos.nacha(), sin_header)

      assert d.esperado =~ "un primer registro :encabezado_de_archivo"
      assert d.recibido == ":encabezado_de_lote"
    end

    test "un primer registro de un tipo desconocido es el diagnóstico de estructura" do
      assert {:error, [%Diagnostico{tipo: :estructura, linea: 1}]} =
               AnchoFijo.identidad(AnchoFijo.Formatos.nacha(), "XX\n")
    end

    test "un multiregistro sin identidad declarada en ningún tipo es solo la huella" do
      multi =
        AnchoFijo.Multiregistro.nuevo!(
          discriminador: [largo: 1],
          registros: [d: [valor: "D", layout: [campos: [[nombre: :t, largo: 1]]]]]
        )

      assert {:ok, %Identidad{declarada: nil}} = AnchoFijo.identidad(multi, "D\nD\n")
    end

    test "el tipo que declara la identidad no tiene que ser el primero de :registros" do
      multi =
        AnchoFijo.Multiregistro.nuevo!(
          discriminador: [largo: 1],
          registros: [
            x: [valor: "X", cantidad: :opcional, layout: [campos: [[nombre: :t, largo: 1]]]],
            h: [
              valor: "H",
              cantidad: :uno,
              layout: [
                identidad: [campos: [:lote]],
                campos: [[nombre: :t, largo: 1], [nombre: :lote, largo: 3, tipo: :entero]]
              ]
            ]
          ]
        )

      assert {:ok, %Identidad{declarada: %{lote: 7}}} = AnchoFijo.identidad(multi, "H007\n")

      assert {:error, [%Diagnostico{tipo: :identidad, recibido: ":x"}]} =
               AnchoFijo.identidad(multi, "X\nH007\n")
    end
  end

  describe "cotejar/2 y duplicada?/2" do
    test "el mismo archivo dos veces es duplicado, por huella, aunque cambie el nombre" do
      {:ok, primera} = AnchoFijo.identidad(@layout, @archivo)
      {:ok, segunda} = AnchoFijo.identidad(@layout, @archivo)

      assert {:duplicada, ^primera} = Identidad.cotejar(segunda, [primera])
      assert Identidad.duplicada?(segunda, [primera])
      assert Identidad.duplicada?(%{segunda | nombre: "otro_nombre.txt"}, [primera])
    end

    test "el mismo contenido sin identidad declarada también es duplicado" do
      {:ok, a} = AnchoFijo.identidad(layout_nomina(), leer("nomina_correcta.txt"))
      {:ok, b} = AnchoFijo.identidad(layout_nomina(), leer("nomina_correcta.txt"))
      assert Identidad.duplicada?(b, [a])
    end

    test "mismo lote y fecha con otro contenido es un conflicto con su propio diagnóstico" do
      {:ok, original} = AnchoFijo.identidad(@layout, @archivo)
      {:ok, editado} = AnchoFijo.identidad(@layout, "000120240115001000\n000120240115009999\n")

      assert {:conflicto, diagnostico, ^original} = Identidad.cotejar(editado, [original])
      assert %Diagnostico{tipo: :identidad} = diagnostico
      assert diagnostico.recibido =~ "lote: 1"
      assert diagnostico.causa_probable =~ "reutilizó el número de lote o alguien editó el archivo"
      refute Identidad.duplicada?(editado, [original])
    end

    test "otro lote es nueva, y una lista vacía también" do
      {:ok, original} = AnchoFijo.identidad(@layout, @archivo)
      {:ok, otro} = AnchoFijo.identidad(@layout, "000220240116001000\n")

      assert Identidad.cotejar(otro, [original]) == :nueva
      assert Identidad.cotejar(original, []) == :nueva
    end

    test "la huella manda sobre lo declarado" do
      {:ok, a} = AnchoFijo.identidad(@layout, @archivo)
      distinto_lote_mismo_contenido = %{a | declarada: %{lote: 99, fecha: ~D[2024-01-15]}}

      assert {:duplicada, ^a} = Identidad.cotejar(distinto_lote_mismo_contenido, [a])
    end

    test "una identidad sin declarada no entra en conflicto con nadie" do
      {:ok, a} = AnchoFijo.identidad(layout_nomina(), leer("nomina_correcta.txt"))
      {:ok, b} = AnchoFijo.identidad(layout_nomina(encoding: :latin1), leer("nomina_latin1.txt"))
      assert Identidad.cotejar(b, [a]) == :nueva
    end
  end
end
