defmodule AnchoFijo.CampoTest do
  use ExUnit.Case, async: true

  alias AnchoFijo.Campo

  defp extraer(atributos, linea, contexto \\ []) do
    atributos
    |> Keyword.put_new(:posicion, 1)
    |> Campo.nuevo!()
    |> Campo.extraer(linea, contexto)
  end

  describe ":texto" do
    test "recorta el relleno por ambos lados" do
      assert extraer([nombre: :a, largo: 8], "  JUAN  ") == {:ok, "JUAN"}
    end

    test "respeta trim: :izquierda y :derecha" do
      assert extraer([nombre: :a, largo: 8, trim: :izquierda], "  JUAN  ") == {:ok, "JUAN  "}
      assert extraer([nombre: :a, largo: 8, trim: :derecha], "  JUAN  ") == {:ok, "  JUAN"}
    end

    test "trim: false deja el campo tal cual" do
      assert extraer([nombre: :a, largo: 8, trim: false], "  JUAN  ") == {:ok, "  JUAN  "}
    end

    test "un relleno de ceros se recorta como relleno" do
      assert extraer([nombre: :a, largo: 6, relleno: "0"], "000ABC") == {:ok, "ABC"}
    end

    test "un texto en blanco es cadena vacía y no un error" do
      assert extraer([nombre: :a, largo: 4], "    ") == {:ok, ""}
    end

    test "con opcional: true un texto en blanco es nil" do
      assert extraer([nombre: :a, largo: 4, opcional: true], "    ") == {:ok, nil}
    end
  end

  describe ":entero" do
    test "ignora los ceros de relleno" do
      assert extraer([nombre: :a, largo: 6, tipo: :entero], "000042") == {:ok, 42}
    end

    test "acepta signo y espacios" do
      assert extraer([nombre: :a, largo: 6, tipo: :entero], "  -123") == {:ok, -123}
      assert extraer([nombre: :a, largo: 6, tipo: :entero], "+00123") == {:ok, 123}
    end

    test "un campo en ceros es cero" do
      assert extraer([nombre: :a, largo: 4, tipo: :entero], "0000") == {:ok, 0}
    end

    test "un campo en blanco sin opcional diagnostica y sugiere la opción" do
      {:error, diagnostico} = extraer([nombre: :a, largo: 4, tipo: :entero], "    ")

      assert diagnostico.recibido == "un campo en blanco"
      assert diagnostico.causa_probable =~ "declare opcional: true"
    end

    test "un campo con letras diagnostica el contenido" do
      {:error, diagnostico} = extraer([nombre: :a, largo: 4, tipo: :entero], "12A4")

      assert diagnostico.esperado == "4 posiciones con un número entero"
      assert diagnostico.recibido == ~s("12A4")
      assert diagnostico.causa_probable =~ "el campo está corrido"
    end

    test "rechaza un decimal disfrazado de entero" do
      assert {:error, _diagnostico} = extraer([nombre: :a, largo: 6, tipo: :entero], "12.345")
    end
  end

  describe ":decimal" do
    test "con separador implícito el campo ya viene en unidades mínimas" do
      assert extraer([nombre: :a, largo: 10, tipo: :decimal, precision: 2], "0000125000") ==
               {:ok, {125_000, 2}}
    end

    test "precision 0 devuelve el entero con escala cero" do
      assert extraer([nombre: :a, largo: 4, tipo: :decimal, precision: 0], "1234") ==
               {:ok, {1234, 0}}
    end

    test "acepta signo negativo" do
      assert extraer([nombre: :a, largo: 8, tipo: :decimal, precision: 2], "-0012345") ==
               {:ok, {-12_345, 2}}
    end

    test "con separador explícito escala la fracción a la precisión declarada" do
      assert extraer(
               [nombre: :a, largo: 10, tipo: :decimal, precision: 2, separador: :coma],
               "    1234,5"
             ) == {:ok, {123_450, 2}}
    end

    test "con separador explícito y sin parte fraccionaria rellena con ceros" do
      assert extraer(
               [nombre: :a, largo: 8, tipo: :decimal, precision: 2, separador: :punto],
               "    1234"
             ) == {:ok, {123_400, 2}}
    end

    test "más decimales que la precisión declarada es un error explicado" do
      {:error, diagnostico} =
        extraer(
          [nombre: :a, largo: 10, tipo: :decimal, precision: 2, separador: :punto],
          "   12.3456"
        )

      assert diagnostico.esperado == "a lo más 2 decimales"
      assert diagnostico.causa_probable =~ "es menor que la del archivo"
    end

    # El error más común del mundo real: el ERP exporta con punto y el layout
    # declara decimales implícitos. Multiplicar por cien silenciosamente sería
    # peor que fallar.
    test "un separador inesperado sugiere la opción correcta" do
      {:error, diagnostico} =
        extraer([nombre: :a, largo: 8, tipo: :decimal, precision: 2], " 1234.56")

      assert diagnostico.causa_probable =~ "declare separador: :punto o :coma"
    end

    test "los montos nunca pasan por float" do
      {:ok, {unidades, precision}} =
        extraer([nombre: :a, largo: 12, tipo: :decimal, precision: 2], "000000010010")

      assert is_integer(unidades)
      assert unidades == 10_010
      assert precision == 2
    end
  end

  describe ":fecha" do
    test "lee AAAAMMDD" do
      assert extraer([nombre: :a, largo: 8, tipo: :fecha, formato: :aaaammdd], "20240229") ==
               {:ok, ~D[2024-02-29]}
    end

    test "lee DDMMAAAA" do
      assert extraer([nombre: :a, largo: 8, tipo: :fecha, formato: :ddmmaaaa], "29022024") ==
               {:ok, ~D[2024-02-29]}
    end

    test "un día inexistente diagnostica el día" do
      {:error, diagnostico} =
        extraer([nombre: :a, largo: 8, tipo: :fecha, formato: :aaaammdd], "20230229")

      assert diagnostico.causa_probable == "el día no existe en ese mes"
    end

    test "un mes imposible sugiere que el formato está invertido" do
      {:error, diagnostico} =
        extraer([nombre: :a, largo: 8, tipo: :fecha, formato: :aaaammdd], "15012024")

      assert diagnostico.causa_probable =~ "puede que el formato sea el inverso"
    end

    test "una fecha en ceros sin opcional explica la convención del emisor" do
      {:error, diagnostico} =
        extraer([nombre: :a, largo: 8, tipo: :fecha, formato: :aaaammdd], "00000000")

      assert diagnostico.causa_probable =~ "blancos o ceros para 'sin fecha'"
    end

    test "una fecha en ceros con opcional es nil" do
      assert extraer(
               [nombre: :a, largo: 8, tipo: :fecha, formato: :aaaammdd, opcional: true],
               "00000000"
             ) == {:ok, nil}
    end

    test "una fecha con separadores diagnostica el largo" do
      {:error, diagnostico} =
        extraer([nombre: :a, largo: 10, tipo: :fecha, formato: :ddmmaaaa], "15-01-2024")

      assert diagnostico.causa_probable =~ "se esperaban 8 dígitos"
    end
  end

  describe "encoding" do
    test "transcodifica latin-1 a UTF-8" do
      assert extraer([nombre: :a, largo: 6], <<74, 79, 83, 201, 32, 32>>, encoding: :latin1) ==
               {:ok, "JOSÉ"}
    end

    test "un byte latin-1 leído como UTF-8 diagnostica y sugiere el encoding" do
      {:error, diagnostico} = extraer([nombre: :a, largo: 5], <<74, 79, 83, 201, 32>>, linea: 12)

      assert diagnostico.tipo == :encoding
      assert diagnostico.linea == 12
      assert diagnostico.recibido == "el byte 0xC9 en la posición 4"
      assert diagnostico.causa_probable =~ "declare encoding: :latin1"
    end

    test "un byte del rango cp1252 delata Windows-1252" do
      {:error, diagnostico} =
        extraer([nombre: :a, largo: 4], <<65, 66, 0x93, 67>>, encoding: :latin1)

      assert diagnostico.causa_probable =~ "probablemente es cp1252"
    end

    test "un byte nulo no revienta el parseo" do
      {:error, diagnostico} = extraer([nombre: :a, largo: 4], <<65, 66, 0, 67>>, encoding: :latin1)

      assert diagnostico.tipo == :encoding
      assert diagnostico.causa_probable =~ "carácter de control"
    end
  end

  describe "unidad :caracteres" do
    test "corta por caracteres sobre una línea ya transcodificada" do
      assert extraer([nombre: :a, largo: 4], "JOSÉ MUÑOZ", unidad: :caracteres) == {:ok, "JOSÉ"}
    end

    test "el mismo campo en bytes parte el carácter multibyte y lo diagnostica" do
      assert {:error, diagnostico} = extraer([nombre: :a, largo: 4], "JOSÉ MUÑOZ")
      assert diagnostico.causa_probable =~ "unidad: :caracteres"
    end
  end

  describe "rango" do
    test "una línea que termina antes del campo se diagnostica como largo" do
      {:error, diagnostico} = extraer([nombre: :a, posicion: 10, largo: 5], "corta")

      assert diagnostico.tipo == :largo_de_linea
      assert diagnostico.esperado == "al menos 14 bytes"
      assert diagnostico.causa_probable == "la línea termina antes de este campo"
    end
  end

  describe "definición" do
    test "un campo :fecha sin formato es un layout inválido" do
      {:error, [diagnostico]} = Campo.nuevo(nombre: :f, largo: 8, tipo: :fecha)

      assert diagnostico.causa_probable =~ "el orden de una fecha no se adivina"
    end

    test "un campo :fecha necesita al menos 8 posiciones" do
      {:error, [diagnostico]} =
        Campo.nuevo(nombre: :f, largo: 6, tipo: :fecha, formato: :aaaammdd)

      assert diagnostico.esperado =~ "al menos 8"
    end

    test "trim: true es sinónimo de :ambos" do
      assert Campo.nuevo!(nombre: :a, largo: 2, trim: true).trim == :ambos
    end

    test "rechaza un relleno de más de un carácter" do
      assert {:error, [_diagnostico]} = Campo.nuevo(nombre: :a, largo: 2, relleno: "00")
    end

    test "rango/1 y fin/1 son 1-based e inclusivos" do
      campo = Campo.nuevo!(nombre: :a, posicion: 21, largo: 12)

      assert Campo.rango(campo) == {21, 32}
      assert Campo.fin(campo) == 32
    end
  end
end
