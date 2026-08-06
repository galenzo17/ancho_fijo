defmodule AnchoFijo.PropiedadesTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  import AnchoFijo.Generadores

  alias AnchoFijo.Campo

  describe "round-trip" do
    property "un registro válido serializado y vuelto a parsear es el mismo registro" do
      check all(%{layout: layout, linea: linea, registro: registro} <- layout_con_registro()) do
        assert AnchoFijo.parsear(layout, linea) == {:ok, [registro]}
      end
    end

    property "el largo del layout coincide con el de la línea que describe" do
      check all(%{layout: layout, linea: linea} <- layout_con_registro()) do
        assert AnchoFijo.Layout.largo(layout) == byte_size(linea)
      end
    end

    property "varias copias de la misma línea dan varios registros idénticos" do
      check all(
              %{layout: layout, linea: linea, registro: registro} <- layout_con_registro(),
              repeticiones <- integer(1..8)
            ) do
        contenido = String.duplicate(linea <> "\n", repeticiones)

        assert {:ok, registros} = AnchoFijo.parsear(layout, contenido)
        assert registros == List.duplicate(registro, repeticiones)
      end
    end

    property "el modo tolerante sobre un archivo sano no acumula diagnósticos" do
      check all(%{layout: layout, linea: linea, registro: registro} <- layout_con_registro()) do
        assert {:ok, [^registro], []} = AnchoFijo.parsear(layout, linea, modo: :tolerante)
      end
    end

    property "el stream entrega lo mismo que parsear/3" do
      check all(%{layout: layout, linea: linea, registro: registro} <- layout_con_registro()) do
        resultados = layout |> AnchoFijo.stream(linea <> "\n") |> Enum.to_list()

        assert resultados == [{:ok, registro}]
      end
    end
  end

  describe "mutaciones detectadas" do
    property "acortar una línea válida siempre produce un diagnóstico de largo" do
      check all(
              %{layout: layout, linea: linea} <- layout_con_registro(),
              recorte <- integer(1..max(1, byte_size(linea) - 1))
            ) do
        mutada = :binary.part(linea, 0, byte_size(linea) - recorte)

        assert {:error, [diagnostico]} = AnchoFijo.parsear(layout, mutada, omitir_vacias: false)
        assert diagnostico.tipo == :largo_de_linea
        assert diagnostico.linea == 1
        assert diagnostico.recibido == Integer.to_string(byte_size(mutada))
        assert diagnostico.causa_probable =~ "campo faltante"
      end
    end

    property "alargar una línea válida siempre produce un diagnóstico de largo" do
      check all(
              %{layout: layout, linea: linea} <- layout_con_registro(),
              sobra <- integer(1..5)
            ) do
        mutada = linea <> String.duplicate("X", sobra)

        assert {:error, [diagnostico]} = AnchoFijo.parsear(layout, mutada)
        assert diagnostico.tipo == :largo_de_linea
        assert diagnostico.esperado == "#{AnchoFijo.Layout.largo(layout)} bytes"
      end
    end

    # Es la mutación que importa: el archivo mide lo que debe, pasa cualquier
    # chequeo de largo, y trae un byte latin-1 donde el layout declaró UTF-8.
    property "cambiar un byte por uno latin-1 produce un diagnóstico de encoding" do
      check all(
              %{layout: layout, linea: linea} <- layout_con_registro(),
              posicion <- integer(0..(byte_size(linea) - 1)),
              byte <- integer(0xC0..0xFF)
            ) do
        mutada = reemplazar_byte(linea, posicion, byte)

        assert {:ok, [], diagnosticos} = AnchoFijo.parsear(layout, mutada, modo: :tolerante)
        assert Enum.any?(diagnosticos, &(&1.tipo == :encoding))

        diagnostico = Enum.find(diagnosticos, &(&1.tipo == :encoding))
        assert diagnostico.campo == campo_en(layout, posicion + 1)
        assert diagnostico.linea == 1
      end
    end

    property "el mismo byte declarado como latin-1 no produce diagnóstico de encoding" do
      check all(
              %{layout: layout, linea: linea} <- layout_con_registro(),
              posicion <- integer(0..(byte_size(linea) - 1)),
              byte <- integer(0xC0..0xFF)
            ) do
        latin1 = AnchoFijo.Layout.nuevo!(campos: campos_de(layout), encoding: :latin1)
        mutada = reemplazar_byte(linea, posicion, byte)

        {:ok, _registros, diagnosticos} = AnchoFijo.parsear(latin1, mutada, modo: :tolerante)

        refute Enum.any?(diagnosticos, &(&1.tipo == :encoding))
      end
    end

    property "meter una letra en un campo numérico se diagnostica en ese campo" do
      check all(
              %{layout: layout, linea: linea, campos: campos} <- layout_con_registro(),
              Enum.any?(campos, &(&1.tipo in [:entero, :decimal])),
              nombre <- member_of(nombres_numericos(campos))
            ) do
        campo = AnchoFijo.Layout.campo(layout, nombre)
        {desde, _hasta} = Campo.rango(campo)
        mutada = reemplazar_byte(linea, desde - 1, ?X)

        assert {:ok, [], diagnosticos} = AnchoFijo.parsear(layout, mutada, modo: :tolerante)

        diagnostico = Enum.find(diagnosticos, &(&1.campo == nombre))
        assert diagnostico.tipo == :campo_invalido
        assert diagnostico.recibido =~ "X"
      end
    end

    property "una línea mutada nunca produce un registro silenciosamente distinto" do
      check all(
              %{layout: layout, linea: linea, registro: registro} <- layout_con_registro(),
              posicion <- integer(0..(byte_size(linea) - 1)),
              byte <- integer(0xC0..0xFF)
            ) do
        mutada = reemplazar_byte(linea, posicion, byte)

        case AnchoFijo.parsear(layout, mutada) do
          {:error, diagnosticos} -> assert diagnosticos != []
          {:ok, [otro]} -> assert otro == registro
        end
      end
    end
  end

  describe "el detector sobre datos generados" do
    property "reconoce como ancho fijo un archivo generado a partir de un layout" do
      check all(
              %{linea: linea} <- layout_con_registro(),
              repeticiones <- integer(2..10)
            ) do
        contenido = String.duplicate(linea <> "\n", repeticiones)

        {:ok, reporte} = AnchoFijo.detectar(contenido, desde: :contenido)

        assert reporte.largo_consistente?
        assert reporte.largo_predominante == byte_size(linea)
        assert reporte.lineas_analizadas == repeticiones
        assert reporte.terminador == :lf
      end
    end

    property "el contraste con su propio layout no encuentra desacuerdos" do
      check all(%{layout: layout, linea: linea} <- layout_con_registro()) do
        {:ok, reporte} = AnchoFijo.detectar(linea <> "\n", desde: :contenido)

        assert AnchoFijo.Detector.contrastar(reporte, layout) == []
      end
    end

    property "acortar todas las líneas se detecta como largo inconsistente con el layout" do
      check all(
              %{layout: layout, linea: linea} <- layout_con_registro(),
              byte_size(linea) > 1,
              recorte <- integer(1..(byte_size(linea) - 1))
            ) do
        mutada = :binary.part(linea, 0, byte_size(linea) - recorte)
        {:ok, reporte} = AnchoFijo.detectar(mutada <> "\n", desde: :contenido)

        assert [diagnostico] = AnchoFijo.Detector.contrastar(reporte, layout)
        assert diagnostico.causa_probable =~ "#{recorte} bytes menos por línea"
      end
    end
  end

  defp reemplazar_byte(binario, posicion, byte) do
    :binary.part(binario, 0, posicion) <>
      <<byte>> <>
      :binary.part(binario, posicion + 1, byte_size(binario) - posicion - 1)
  end

  defp campo_en(layout, posicion) do
    layout.campos
    |> Enum.find(fn campo ->
      {desde, hasta} = Campo.rango(campo)
      posicion >= desde and posicion <= hasta
    end)
    |> then(& &1.nombre)
  end

  defp campos_de(layout) do
    Enum.map(layout.campos, &Map.from_struct/1)
  end

  defp nombres_numericos(campos) do
    campos
    |> Enum.filter(&(&1.tipo in [:entero, :decimal]))
    |> Enum.map(& &1.definicion[:nombre])
  end
end
