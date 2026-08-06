defmodule AnchoFijo.DetectorTest do
  use ExUnit.Case, async: true

  import AnchoFijo.Fixtures

  alias AnchoFijo.Detector

  describe "largos de línea" do
    test "reconoce un archivo consistente" do
      {:ok, reporte} = Detector.detectar(leer("nomina_correcta.txt"))

      assert reporte.lineas_analizadas == 3
      assert reporte.largos == %{48 => 3}
      assert reporte.largo_consistente?
      assert reporte.largo_predominante == 48
      assert reporte.probablemente_ancho_fijo?
    end

    test "aísla la fila corta y la nombra sospechosa" do
      {:ok, reporte} = Detector.detectar(leer("nomina_fila_corta.txt"))

      refute reporte.largo_consistente?
      assert reporte.largos == %{48 => 2, 46 => 1}
      assert reporte.largo_predominante == 48
      refute reporte.probablemente_ancho_fijo?

      assert Enum.any?(reporte.observaciones, &String.contains?(&1, "2 largos de línea distintos"))
      assert Enum.any?(reporte.observaciones, &String.contains?(&1, "filas sospechosas"))
    end

    test "un archivo vacío no revienta y lo dice" do
      {:ok, reporte} = Detector.detectar("", desde: :contenido)

      assert reporte.lineas_analizadas == 0
      assert reporte.largo_predominante == nil
      refute reporte.probablemente_ancho_fijo?
      assert hd(reporte.observaciones) =~ "no tiene ninguna línea con contenido"
    end
  end

  describe "encoding" do
    test "delata un archivo latin-1 con el byte y la línea" do
      {:ok, reporte} = Detector.detectar(leer("nomina_latin1.txt"))

      assert reporte.encoding_probable == :latin1
      assert [%{linea: 1, posicion: posicion, byte: byte} | _resto] = reporte.bytes_no_utf8
      assert posicion == 14
      assert byte == 0xC9

      assert Enum.any?(reporte.observaciones, &String.contains?(&1, "declare encoding: :latin1"))
    end

    test "un archivo ASCII declara que la pregunta no importa" do
      {:ok, reporte} = Detector.detectar(leer("nomina_correcta.txt"))

      assert reporte.encoding_probable == :ascii
      assert reporte.bytes_no_utf8 == []
      assert Enum.any?(reporte.observaciones, &String.contains?(&1, "dan el mismo resultado"))
    end

    test "distingue UTF-8 legítimo de latin-1" do
      {:ok, reporte} = Detector.detectar("JOSÉ MUÑOZ\nMARÍA ROJAS\n")

      assert reporte.encoding_probable == :utf8
      assert reporte.bytes_no_utf8 == []
    end

    test "reporta el desajuste entre largos en bytes y en caracteres" do
      {:ok, reporte} = Detector.detectar("JOSÉ\nJUAN\n")

      assert reporte.largos == %{5 => 1, 4 => 1}
      assert reporte.largos_en_caracteres == %{4 => 2}
      assert Enum.any?(reporte.observaciones, &String.contains?(&1, "unidad: :caracteres"))
    end
  end

  describe "terminadores" do
    test "identifica LF" do
      {:ok, reporte} = Detector.detectar(leer("nomina_correcta.txt"))

      assert reporte.terminador == :lf
      assert reporte.termina_con_terminador?
    end

    test "identifica CRLF y la falta de terminador final" do
      {:ok, reporte} = Detector.detectar(leer("nomina_sin_terminador_final.txt"))

      assert reporte.terminador == :crlf
      refute reporte.termina_con_terminador?
      assert Enum.any?(reporte.observaciones, &String.contains?(&1, "no trae terminador"))
    end

    test "detecta terminadores mezclados" do
      {:ok, reporte} = Detector.detectar("AAAA\r\nBBBB\nCCCC\r\n")

      assert reporte.terminador == :mixto
      assert Enum.any?(reporte.observaciones, &String.contains?(&1, "mezclados"))
    end

    test "un archivo de una sola línea sin salto no tiene terminador" do
      {:ok, reporte} = Detector.detectar("AAAABBBB", desde: :contenido)

      assert reporte.terminador == :ninguno
      assert reporte.lineas_analizadas == 1
    end
  end

  describe "delimitadores" do
    test "descubre que el archivo es en realidad un CSV" do
      {:ok, reporte} = Detector.detectar(leer("nomina_en_realidad_csv.csv"))

      refute reporte.probablemente_ancho_fijo?
      assert reporte.delimitador_sugerido == ";"

      assert Enum.any?(
               reporte.observaciones,
               &String.contains?(&1, "parece un archivo delimitado, no de ancho fijo")
             )
    end

    # La diferencia entre un delimitador y un separador decorativo es la única
    # forma de no dar falsos positivos en formatos de ancho fijo que usan pipes.
    test "un separador en posiciones fijas no es un delimitador" do
      {:ok, reporte} = Detector.detectar("AAA|BBB|CCC\nDDD|EEE|FFF\n")

      assert reporte.probablemente_ancho_fijo?
      assert reporte.delimitador_sugerido == nil
      assert reporte.delimitadores["|"].posiciones_fijas?
      assert Enum.any?(reporte.observaciones, &String.contains?(&1, "separador decorativo"))
    end

    test "una coma dentro de un campo de texto no delata un CSV" do
      {:ok, reporte} = Detector.detectar("PEREZ, JUAN  100\nSOTO ANA     200\n")

      assert reporte.probablemente_ancho_fijo?
      assert reporte.delimitador_sugerido == nil
    end

    test "solo reporta delimitadores presentes" do
      {:ok, reporte} = Detector.detectar("AAAA\nBBBB\n")

      assert reporte.delimitadores == %{}
    end
  end

  describe "lectura de la entrada" do
    test "acepta una ruta de archivo" do
      {:ok, reporte} = Detector.detectar(ruta("nomina_correcta.txt"))

      assert reporte.lineas_analizadas == 3
      assert reporte.largo_predominante == 48
    end

    test "un archivo inexistente devuelve diagnóstico, no excepción" do
      {:error, [diagnostico]} = Detector.detectar("/no/existe/archivo.txt", desde: :archivo)

      assert diagnostico.tipo == :entrada
      assert AnchoFijo.Diagnostico.mensaje(diagnostico) =~ "la ruta no existe"
    end

    test "desde: :contenido evita confundir contenido con ruta" do
      {:ok, reporte} = Detector.detectar(ruta("nomina_correcta.txt"), desde: :contenido)

      assert reporte.lineas_analizadas == 1
    end

    test "limita la muestra por líneas" do
      contenido = String.duplicate("ABCDE\n", 500)
      {:ok, reporte} = Detector.detectar(contenido, lineas: 10)

      assert reporte.lineas_analizadas == 10
    end

    test "marca la muestra truncada y no adivina el terminador final" do
      contenido = String.duplicate("ABCDE\n", 500)
      {:ok, reporte} = Detector.detectar(contenido, bytes: 100)

      assert reporte.muestra_truncada?
      assert reporte.termina_con_terminador? == nil
      assert Enum.any?(reporte.observaciones, &String.contains?(&1, "muestra parcial"))
    end

    test "un argumento que no es entrada da un diagnóstico" do
      {:error, [diagnostico]} = Detector.detectar(:no_soy_un_archivo)

      assert diagnostico.tipo == :entrada
      assert diagnostico.recibido == ":no_soy_un_archivo"
    end
  end

  describe "contrastar/2" do
    test "detecta que el layout declara un largo distinto al del archivo" do
      {:ok, reporte} = Detector.detectar(leer("nomina_correcta.txt"))
      layout = layout_nomina(campos: [[nombre: :todo, largo: 50]])

      assert [diagnostico] = Detector.contrastar(reporte, layout)
      assert diagnostico.esperado == "un largo de línea de 50 bytes según el layout"
      assert diagnostico.recibido == "48"
      assert diagnostico.causa_probable =~ "2 bytes menos por línea"
    end

    test "detecta que el layout declara UTF-8 y el archivo es latin-1" do
      {:ok, reporte} = Detector.detectar(leer("nomina_latin1.txt"))

      diagnosticos = Detector.contrastar(reporte, layout_nomina(encoding: :utf8))

      assert Enum.any?(diagnosticos, &(&1.causa_probable =~ "declare encoding: :latin1"))
    end

    test "no dice nada cuando el archivo calza con el layout" do
      {:ok, reporte} = Detector.detectar(leer("nomina_latin1.txt"))

      assert Detector.contrastar(reporte, layout_nomina(encoding: :latin1)) == []
    end

    test "la opción :layout agrega el contraste a las observaciones" do
      {:ok, reporte} =
        Detector.detectar(leer("nomina_correcta.txt"), layout: layout_nomina(largo: 60))

      assert Enum.any?(reporte.observaciones, &String.contains?(&1, "según el layout"))
    end

    test "un layout inválido devuelve sus propios diagnósticos" do
      {:ok, reporte} = Detector.detectar(leer("nomina_correcta.txt"))

      assert [diagnostico] = Detector.contrastar(reporte, campos: [])
      assert diagnostico.tipo == :layout
    end
  end
end
