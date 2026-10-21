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

  describe "signo al final" do
    test "un decimal con signo al final se lee negativo, sin float en el camino" do
      assert extraer(
               [nombre: :a, largo: 8, tipo: :decimal, precision: 2, signo: :final],
               "0125000-"
             ) == {:ok, {-125_000, 2}}
    end

    test "un entero con signo al final se lee negativo" do
      assert extraer([nombre: :a, largo: 7, tipo: :entero, signo: :final], "000123-") ==
               {:ok, -123}
    end

    test "sin signo es positivo: el espacio del positivo implícito ya se recortó" do
      assert extraer([nombre: :a, largo: 7, tipo: :entero, signo: :final], "000123 ") ==
               {:ok, 123}
    end

    test "un campo en blanco con :opcional sigue siendo nil" do
      assert extraer(
               [nombre: :a, largo: 7, tipo: :entero, signo: :final, opcional: true],
               "       "
             ) ==
               {:ok, nil}
    end

    test "signo duplicado es diagnóstico con causa probable, no valor basura" do
      {:error, diagnostico} =
        extraer([nombre: :a, largo: 8, tipo: :entero, signo: :final], "-001250-")

      assert diagnostico.tipo == :campo_invalido
      assert diagnostico.esperado == "el signo después de los dígitos, como 1250-"
      assert diagnostico.recibido == ~s("-001250-")
      assert is_binary(diagnostico.causa_probable) and diagnostico.causa_probable != ""
    end

    test "el + explícito al final se acepta" do
      assert extraer([nombre: :a, largo: 7, tipo: :entero, signo: :final], "000123+") ==
               {:ok, 123}
    end

    test "con :final, el signo adelante sugiere declarar signo: :inicial" do
      {:error, diagnostico} =
        extraer([nombre: :a, largo: 8, tipo: :decimal, precision: 2, signo: :final], "-0125000")

      assert diagnostico.esperado == "el signo después de los dígitos, como 1250-"
      assert diagnostico.causa_probable =~ "declare signo: :inicial"
    end

    test "dos signos al final también es diagnóstico" do
      {:error, diagnostico} =
        extraer([nombre: :a, largo: 6, tipo: :entero, signo: :final], "1250--")

      assert diagnostico.causa_probable =~ "duplicado"
    end

    test "un signo sin dígitos es diagnóstico con causa, no un cero" do
      {:error, diagnostico} = extraer([nombre: :a, largo: 4, tipo: :entero, signo: :final], "   -")

      assert diagnostico.causa_probable == "el campo trae solo el signo, sin dígitos"
    end

    test "un signo al final con separador explícito escala igual que con signo adelante" do
      assert extraer(
               [
                 nombre: :a,
                 largo: 10,
                 tipo: :decimal,
                 precision: 2,
                 separador: :coma,
                 signo: :final
               ],
               "   1234,5-"
             ) == {:ok, {-123_450, 2}}
    end

    test "con el default :inicial, un signo al final sugiere declarar signo: :final" do
      {:error, diagnostico} = extraer([nombre: :a, largo: 8, tipo: :entero], "0125000-")

      assert diagnostico.esperado == "el signo antes de los dígitos, como -1250"
      assert diagnostico.causa_probable =~ "declare signo: :final"
    end

    test "con :inicial, el signo adelante sigue funcionando igual que antes" do
      assert extraer([nombre: :a, largo: 8, tipo: :decimal, precision: 2], "-0125000") ==
               {:ok, {-125_000, 2}}
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

  describe ":decimal como Decimal" do
    test "con como: :decimal el valor es un Decimal con la escala del campo" do
      campo =
        Campo.nuevo!(
          nombre: :m,
          posicion: 1,
          largo: 8,
          tipo: :decimal,
          precision: 2,
          como: :decimal
        )

      assert {:ok, decimal} = Campo.extraer(campo, "00123456")
      assert Decimal.equal?(decimal, Decimal.new("1234.56"))
      assert decimal.exp == -2

      assert {:ok, negativo} = Campo.extraer(campo, "-0012345")
      assert Decimal.equal?(negativo, Decimal.new("-123.45"))

      con_moneda =
        Campo.nuevo!(
          nombre: :m,
          posicion: 1,
          largo: 8,
          tipo: :decimal,
          moneda: :usd,
          como: :decimal
        )

      assert {:ok, decimal} = Campo.extraer(con_moneda, "00123456")
      assert Decimal.equal?(decimal, Decimal.new("1234.56"))
    end

    test "al escribir, cualquier :decimal acepta un Decimal, un entero o un string" do
      campo = Campo.nuevo!(nombre: :m, posicion: 1, largo: 8, tipo: :decimal, precision: 2)
      assert Campo.formatear(campo, Decimal.new("1234.56")) == {:ok, "00123456", []}
      assert Campo.formatear(campo, Decimal.new("1234.5")) == {:ok, "00123450", []}
      assert Campo.formatear(campo, Decimal.new("-7")) == {:ok, "-0000700", []}
      assert Campo.formatear(campo, 1234) == {:ok, "00123400", []}
      assert Campo.formatear(campo, "1234.56") == {:ok, "00123456", []}

      con_punto =
        Campo.nuevo!(
          nombre: :m,
          posicion: 1,
          largo: 8,
          tipo: :decimal,
          precision: 2,
          separador: :punto
        )

      assert Campo.formatear(con_punto, Decimal.new("12.5")) == {:ok, "00012.50", []}

      con_moneda = Campo.nuevo!(nombre: :m, posicion: 1, largo: 8, tipo: :decimal, moneda: :clp)
      assert Campo.formatear(con_moneda, Decimal.new("125000")) == {:ok, "00125000", []}
    end

    test "más decimales que la precisión es un diagnóstico, nunca un redondeo" do
      campo = Campo.nuevo!(nombre: :m, posicion: 1, largo: 8, tipo: :decimal, precision: 2)

      assert {:error, d} = Campo.formatear(campo, Decimal.new("1234.567"))
      assert d.esperado == "un monto {unidades, 2}, un Decimal o un entero"
      assert d.recibido == "Decimal.new(\"1234.567\")"
      assert d.causa_probable =~ "más decimales que la precisión del campo (2)"

      assert {:error, %{causa_probable: causa}} = Campo.formatear(campo, "12.345")
      assert causa =~ "más decimales"

      assert {:error, %{causa_probable: "el string no es un número decimal"}} =
               Campo.formatear(campo, "12,5")

      assert {:error, %{causa_probable: "NaN o infinito no son un monto"}} =
               Campo.formatear(campo, Decimal.new("NaN"))
    end

    test "la definición valida :como" do
      assert {:error, [d]} =
               Campo.nuevo(nombre: :m, largo: 8, tipo: :decimal, precision: 2, como: :float)

      assert d.esperado == "como: :decimal, o ninguno para leer {unidades, precision}"

      assert {:error, [d]} = Campo.nuevo(nombre: :m, largo: 8, tipo: :entero, como: :decimal)
      assert d.esperado == ":como solo en campos :decimal"
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

      assert diagnostico.causa_probable =~ "se esperaban 8 posiciones (DDMMAAAA)"
    end
  end

  describe ":fecha con más formatos" do
    test "cada formato con nombre lee y escribe la misma fecha" do
      for {formato, texto} <- [
            aaaammdd: "20240131",
            ddmmaaaa: "31012024",
            mmddaaaa: "01312024",
            aammdd: "240131",
            ddmmaa: "310124",
            mmddaa: "013124",
            aaaaddd: "2024031",
            aaddd: "24031"
          ] do
        campo =
          Campo.nuevo!(
            nombre: :f,
            posicion: 1,
            largo: String.length(texto),
            tipo: :fecha,
            formato: formato
          )

        assert Campo.extraer(campo, texto) == {:ok, ~D[2024-01-31]}, "#{formato}"
        assert Campo.formatear(campo, ~D[2024-01-31]) == {:ok, texto, []}, "#{formato}"
      end
    end

    test "un patrón explícito con separadores" do
      campo = Campo.nuevo!(nombre: :f, posicion: 1, largo: 10, tipo: :fecha, formato: "DD/MM/AAAA")
      assert Campo.extraer(campo, "31/01/2024") == {:ok, ~D[2024-01-31]}
      assert Campo.formatear(campo, ~D[2024-01-31]) == {:ok, "31/01/2024", []}

      iso = Campo.nuevo!(nombre: :f, posicion: 1, largo: 10, tipo: :fecha, formato: "AAAA-MM-DD")
      assert Campo.extraer(iso, "2024-01-31") == {:ok, ~D[2024-01-31]}

      assert {:error, d} = Campo.extraer(campo, "31-01-2024")
      assert d.causa_probable == "los separadores no están donde el patrón DD/MM/AAAA los espera"
    end

    test "el año de dos dígitos se expande con el pivote" do
      campo = Campo.nuevo!(nombre: :f, posicion: 1, largo: 6, tipo: :fecha, formato: :aammdd)
      assert Campo.extraer(campo, "990131") == {:ok, ~D[2099-01-31]}

      con_pivote =
        Campo.nuevo!(
          nombre: :f,
          posicion: 1,
          largo: 6,
          tipo: :fecha,
          formato: :aammdd,
          pivote: 1970
        )

      assert Campo.extraer(con_pivote, "690131") == {:ok, ~D[2069-01-31]}
      assert Campo.extraer(con_pivote, "700131") == {:ok, ~D[1970-01-31]}
      assert Campo.formatear(con_pivote, ~D[1985-06-15]) == {:ok, "850615", []}

      assert {:error, d} = Campo.formatear(campo, ~D[1985-06-15])
      assert d.causa_probable =~ "el año 1985 no cabe en dos dígitos con pivote 2000"
    end

    test "una fecha juliana que no existe, y una con ceros en un patrón con separadores" do
      campo = Campo.nuevo!(nombre: :f, posicion: 1, largo: 7, tipo: :fecha, formato: :aaaaddd)

      assert {:error, %{causa_probable: "el día 366 no existe en el año 2023"}} =
               Campo.extraer(campo, "2023366")

      assert Campo.extraer(campo, "2024366") == {:ok, ~D[2024-12-31]}

      opcional =
        Campo.nuevo!(
          nombre: :f,
          posicion: 1,
          largo: 10,
          tipo: :fecha,
          formato: "DD/MM/AAAA",
          opcional: true
        )

      assert Campo.extraer(opcional, "00/00/0000") == {:ok, nil}
      assert Campo.extraer(opcional, "          ") == {:ok, nil}
    end

    test "un valor imposible es un diagnóstico, no una excepción" do
      campo = Campo.nuevo!(nombre: :f, posicion: 1, largo: 8, tipo: :fecha, formato: :aaaammdd)
      assert {:error, d} = Campo.extraer(campo, "20261332")
      assert d.causa_probable == "el mes 13 no existe: puede que el formato sea el inverso"
      assert {:error, %{causa_probable: causa}} = Campo.extraer(campo, "2026AB01")
      assert causa == "el mes trae \"AB\", que no es numérico"
    end

    test "la definición valida el patrón" do
      assert {:error, [d]} = Campo.nuevo(nombre: :f, largo: 8, tipo: :fecha, formato: "AAAAMMD")
      assert d.esperado =~ "\"D\" suelto no es un token"

      assert {:error, [d]} = Campo.nuevo(nombre: :f, largo: 8, tipo: :fecha, formato: "AAAAMM")
      assert d.esperado == "un :formato con año con mes y día, o año con día del año (DDD)"

      assert {:error, [d]} = Campo.nuevo(nombre: :f, largo: 8, tipo: :fecha, formato: :hhmmss)
      assert d.esperado =~ "solo tokens de fecha"

      assert {:error, [d]} = Campo.nuevo(nombre: :f, largo: 6, tipo: :fecha, formato: :aaaammdd)
      assert d.esperado == "un :largo de al menos 8 para el formato AAAAMMDD"

      assert {:error, [d]} = Campo.nuevo(nombre: :f, largo: 8, tipo: :fecha, formato: "AAAAMMDDMM")
      assert d.esperado =~ "el mes se repite"

      assert {:error, [d]} =
               Campo.nuevo(nombre: :f, largo: 6, tipo: :fecha, formato: :aammdd, pivote: :si)

      assert d.esperado =~ "un :pivote entero"
    end
  end

  describe ":hora" do
    test "lee y escribe HHMMSS, HHMM y un patrón con separadores" do
      for {formato, texto, hora} <- [
            {:hhmmss, "093015", ~T[09:30:15]},
            {:hhmm, "0930", ~T[09:30:00]},
            {"HH:MM:SS", "09:30:15", ~T[09:30:15]}
          ] do
        campo =
          Campo.nuevo!(
            nombre: :h,
            posicion: 1,
            largo: String.length(texto),
            tipo: :hora,
            formato: formato
          )

        assert Campo.extraer(campo, texto) == {:ok, hora}
        assert Campo.formatear(campo, hora) == {:ok, texto, []}
      end
    end

    test "una hora que no existe dice qué parte falla" do
      campo = Campo.nuevo!(nombre: :h, posicion: 1, largo: 6, tipo: :hora, formato: :hhmmss)

      assert {:error, %{causa_probable: "la hora 24 no existe: el día tiene 24"}} =
               Campo.extraer(campo, "240000")

      assert {:error, %{causa_probable: "el minuto 61 no existe"}} = Campo.extraer(campo, "126100")
      assert {:error, %{causa_probable: "el segundo 61 no existe"}} = Campo.extraer(campo, "120061")
    end

    test "blancos y ceros: nil con opcional, diagnóstico sin" do
      campo =
        Campo.nuevo!(nombre: :h, posicion: 1, largo: 4, tipo: :hora, formato: :hhmm, opcional: true)

      assert Campo.extraer(campo, "0000") == {:ok, nil}
      assert Campo.extraer(campo, "    ") == {:ok, nil}

      estricta = Campo.nuevo!(nombre: :h, posicion: 1, largo: 4, tipo: :hora, formato: :hhmm)
      assert {:error, d} = Campo.extraer(estricta, "0000")
      assert d.causa_probable =~ "blancos o ceros para 'sin hora'"
    end

    test "un patrón de fecha en un :hora, o sin minutos, es un layout inválido" do
      assert {:error, [d]} = Campo.nuevo(nombre: :h, largo: 8, tipo: :hora, formato: :aaaammdd)
      assert d.esperado =~ "solo tokens de hora"

      assert {:error, [d]} = Campo.nuevo(nombre: :h, largo: 2, tipo: :hora, formato: "HH")
      assert d.esperado == "un :formato con hora y minuto (HHMM), y segundos si los hay"

      assert {:error, [d]} = Campo.nuevo(nombre: :h, largo: 4, tipo: :hora)
      assert d.causa_probable == "el orden de una hora no se adivina: hay que declararlo"
    end

    test "escribir algo que no es Time es un diagnóstico" do
      campo = Campo.nuevo!(nombre: :h, posicion: 1, largo: 4, tipo: :hora, formato: :hhmm)
      assert {:error, %{esperado: "una hora (Time)"}} = Campo.formatear(campo, "0930")
    end
  end

  describe ":fecha_hora" do
    test "lee y escribe los formatos con nombre y un patrón ISO" do
      for {formato, texto, valor} <- [
            {:aaaammddhhmmss, "20240131093015", ~N[2024-01-31 09:30:15]},
            {:aaaammddhhmm, "202401310930", ~N[2024-01-31 09:30:00]},
            {:ddmmaaaahhmmss, "31012024093015", ~N[2024-01-31 09:30:15]},
            {:ddmmaaaahhmm, "310120240930", ~N[2024-01-31 09:30:00]},
            {"AAAA-MM-DD HH:MM:SS", "2024-01-31 09:30:15", ~N[2024-01-31 09:30:15]}
          ] do
        campo =
          Campo.nuevo!(
            nombre: :fh,
            posicion: 1,
            largo: String.length(texto),
            tipo: :fecha_hora,
            formato: formato
          )

        assert Campo.extraer(campo, texto) == {:ok, valor}, "#{inspect(formato)}"
        assert Campo.formatear(campo, valor) == {:ok, texto, []}, "#{inspect(formato)}"
      end
    end

    test "la fecha o la hora inválidas se diagnostican con su causa" do
      campo =
        Campo.nuevo!(
          nombre: :fh,
          posicion: 1,
          largo: 14,
          tipo: :fecha_hora,
          formato: :aaaammddhhmmss
        )

      assert {:error, %{causa_probable: "el día no existe en ese mes"}} =
               Campo.extraer(campo, "20230229120000")

      assert {:error, %{causa_probable: "la hora 25 no existe: el día tiene 24"}} =
               Campo.extraer(campo, "20240131250000")

      assert {:error, %{esperado: "una fecha y hora válidas en formato AAAAMMDDHHMMSS"}} =
               Campo.extraer(campo, "2024013125000X")
    end

    test "con año de dos dígitos y pivote, en blanco con opcional, y la definición" do
      campo =
        Campo.nuevo!(
          nombre: :fh,
          posicion: 1,
          largo: 10,
          tipo: :fecha_hora,
          formato: "AAMMDDHHMM",
          pivote: 1990
        )

      assert Campo.extraer(campo, "9501311200") == {:ok, ~N[1995-01-31 12:00:00]}
      assert Campo.formatear(campo, ~N[2089-01-31 12:00:00]) == {:ok, "8901311200", []}

      opcional =
        Campo.nuevo!(
          nombre: :fh,
          posicion: 1,
          largo: 14,
          tipo: :fecha_hora,
          formato: :aaaammddhhmmss,
          opcional: true
        )

      assert Campo.extraer(opcional, "00000000000000") == {:ok, nil}

      assert {:error, [d]} =
               Campo.nuevo(nombre: :fh, largo: 8, tipo: :fecha_hora, formato: :aaaammdd)

      assert d.esperado =~ "hora y minuto además de la fecha"

      assert {:error, [d]} = Campo.nuevo(nombre: :fh, largo: 6, tipo: :fecha_hora, formato: :hhmmss)
      assert d.esperado =~ "una fecha completa además de la hora"
    end
  end

  describe ":rut" do
    test "normaliza a cuerpo-DV sin puntos ni ceros a la izquierda" do
      assert extraer([nombre: :a, largo: 13, tipo: :rut], "0000123456785") == {:ok, "12345678-5"}
      assert extraer([nombre: :a, largo: 12, tipo: :rut], "12.345.678-5") == {:ok, "12345678-5"}
      assert extraer([nombre: :a, largo: 10, tipo: :rut], "12345678-5") == {:ok, "12345678-5"}
    end

    test "un DV que no cuadra es diagnóstico con el DV esperado y causa probable" do
      {:error, diagnostico} = extraer([nombre: :a, largo: 10, tipo: :rut], "12345678-9")

      assert diagnostico.tipo == :campo_invalido
      assert diagnostico.esperado =~ "para ese cuerpo corresponde 5"
      assert diagnostico.recibido == ~s("12345678-9")
      assert diagnostico.causa_probable =~ "posible error de digitación o campo corrido"
    end

    test "un RUT con letras es diagnóstico de formato" do
      {:error, diagnostico} = extraer([nombre: :a, largo: 10, tipo: :rut], "1234567A-9")

      assert diagnostico.esperado == "un RUT con dígito verificador"
      assert diagnostico.causa_probable =~ "se esperaban dígitos"
    end

    test "dv: :no_validar deja pasar el DV malo" do
      assert extraer([nombre: :a, largo: 10, tipo: :rut, dv: :no_validar], "12345678-9") ==
               {:ok, "12345678-9"}
    end

    test "dv: :ausente lee solo el cuerpo" do
      assert extraer([nombre: :a, largo: 10, tipo: :rut, dv: :ausente], "0012345678") ==
               {:ok, "12345678"}

      {:error, diagnostico} =
        extraer([nombre: :a, largo: 10, tipo: :rut, dv: :ausente], "12345678-5")

      assert diagnostico.esperado == "el cuerpo de un RUT, sin dígito verificador"
    end

    test "en blanco con :opcional es nil, sin :opcional sugiere la opción" do
      assert extraer([nombre: :a, largo: 10, tipo: :rut, opcional: true], "          ") ==
               {:ok, nil}

      {:error, diagnostico} = extraer([nombre: :a, largo: 10, tipo: :rut], "          ")
      assert diagnostico.causa_probable =~ "declare opcional: true"
    end

    test ":dv solo aplica a :rut y rechaza valores desconocidos" do
      {:error, [diagnostico]} = Campo.nuevo(nombre: :a, largo: 10, dv: :ausente)
      assert diagnostico.esperado == ":dv solo en campos :rut"

      {:error, [diagnostico]} = Campo.nuevo(nombre: :a, largo: 10, tipo: :rut, dv: :quizas)
      assert diagnostico.esperado == ":dv en [:validar, :no_validar, :ausente]"
    end
  end

  describe ":constante" do
    test "lee el literal, con el relleno final sin contar" do
      campo = Campo.nuevo!(nombre: :tipo, posicion: 1, largo: 2, tipo: :constante, valor: "01")
      assert Campo.extraer(campo, "01xxxx") == {:ok, "01"}

      literal = Campo.nuevo!(nombre: :h, posicion: 1, largo: 10, tipo: :constante, valor: "HEADER")
      assert Campo.extraer(literal, "HEADER    ") == {:ok, "HEADER"}

      assert {:error, %AnchoFijo.Diagnostico{tipo: :largo_de_linea}} =
               Campo.extraer(literal, "HEADER")
    end

    test "otro literal es un diagnóstico con esperado y recibido" do
      campo = Campo.nuevo!(nombre: :tipo, posicion: 1, largo: 2, tipo: :constante, valor: "01")

      assert {:error, d} = Campo.extraer(campo, "02xxxx", linea: 3)

      assert %AnchoFijo.Diagnostico{tipo: :campo_invalido, campo: :tipo, linea: 3, posicion: {1, 2}} =
               d

      assert d.esperado == "el literal \"01\""
      assert d.recibido == "\"02\""
      assert d.causa_probable =~ "puede ser un archivo multiregistro"

      literal = Campo.nuevo!(nombre: :h, posicion: 1, largo: 10, tipo: :constante, valor: "HEADER")

      assert {:error, %AnchoFijo.Diagnostico{recibido: "\"HEADER  X \""}} =
               Campo.extraer(literal, "HEADER  X ")
    end

    test "se escribe solo, o con el mismo literal; otro valor es un diagnóstico" do
      campo = Campo.nuevo!(nombre: :h, posicion: 1, largo: 10, tipo: :constante, valor: "HEADER")
      assert Campo.formatear(campo, nil) == {:ok, "HEADER    ", []}
      assert Campo.formatear(campo, "HEADER") == {:ok, "HEADER    ", []}

      assert {:error, d} = Campo.formatear(campo, "TRAILER")
      assert d.esperado == "el literal \"HEADER\", o el campo ausente del mapa"
      assert d.causa_probable =~ "constante del formato"

      ceros =
        Campo.nuevo!(nombre: :c, posicion: 1, largo: 4, tipo: :constante, valor: "9", relleno: "9")

      assert Campo.formatear(ceros, nil) == {:ok, "9999", []}
      assert Campo.extraer(ceros, "9999") == {:ok, "9"}
    end

    test "la definición exige un :valor que quepa" do
      assert {:error, [d]} = Campo.nuevo(nombre: :t, largo: 2, tipo: :constante)
      assert d.esperado =~ "un :valor binario no vacío"

      assert {:error, [d]} = Campo.nuevo(nombre: :t, largo: 2, tipo: :constante, valor: "ABC")
      assert d.esperado == "un :valor de hasta 2 caracteres"

      assert {:error, [d]} = Campo.nuevo(nombre: :t, largo: 2, tipo: :texto, valor: "AB")
      assert d.esperado == ":valor solo en campos :constante"
    end
  end

  describe ":relleno" do
    test "no lee nada y se escribe con su carácter" do
      campo = Campo.nuevo!(nombre: :filler, posicion: 1, largo: 5, tipo: :relleno)
      assert Campo.extraer(campo, "basur") == {:ok, nil}
      assert Campo.formatear(campo, nil) == {:ok, "     ", []}

      ceros = Campo.nuevo!(nombre: :ceros, posicion: 1, largo: 3, tipo: :relleno, relleno: "0")
      assert Campo.formatear(ceros, nil) == {:ok, "000", []}
    end

    test "un valor en el mapa para el relleno es un diagnóstico" do
      campo = Campo.nuevo!(nombre: :filler, posicion: 1, largo: 5, tipo: :relleno)
      assert {:error, d} = Campo.formatear(campo, "algo")
      assert d.esperado == "ningún valor para el campo de relleno, o nil"
      assert d.causa_probable =~ "saque la clave del mapa"
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

  describe "encoding por campo" do
    test "un campo UTF-8 dentro de un layout latin-1, y al revés" do
      utf8 = Campo.nuevo!(nombre: :m, posicion: 1, largo: 10, encoding: :utf8)
      assert Campo.extraer(utf8, "operación ", encoding: :latin1) == {:ok, "operación"}

      latin1 = Campo.nuevo!(nombre: :n, posicion: 1, largo: 5, encoding: :latin1)
      assert Campo.extraer(latin1, <<74, 79, 83, 0xC9, 32>>, encoding: :utf8) == {:ok, "JOSÉ"}
    end

    test "al escribir, el encoding del campo manda sobre el del layout" do
      utf8 = Campo.nuevo!(nombre: :m, posicion: 1, largo: 12, encoding: :utf8)
      assert Campo.formatear(utf8, "operación", %{encoding: :latin1}) == {:ok, "operación  ", []}

      latin1 = Campo.nuevo!(nombre: :n, posicion: 1, largo: 5, encoding: :latin1)

      assert Campo.formatear(latin1, "JOSÉ", %{encoding: :utf8}) ==
               {:ok, <<74, 79, 83, 0xC9, 32>>, []}
    end

    test "un encoding que no existe, o uno por campo con unidad :caracteres, es un layout inválido" do
      assert {:error, [d]} = Campo.nuevo(nombre: :m, largo: 10, encoding: :cp1252)
      assert d.esperado == ":encoding :utf8 o :latin1, o ninguno para usar el del layout"

      assert {:error, [d]} =
               AnchoFijo.Layout.nuevo(
                 unidad: :caracteres,
                 campos: [[nombre: :m, largo: 10, encoding: :utf8]]
               )

      assert %AnchoFijo.Diagnostico{tipo: :layout, campo: :m} = d
      assert d.esperado == "ningún :encoding por campo con unidad: :caracteres"
    end
  end

  describe "doble codificación" do
    test "se advierte con el texto reparado, y el valor queda como vino" do
      campo = Campo.nuevo!(nombre: :m, posicion: 1, largo: 12)
      assert {:ok, "operaciÃ³n", [d]} = Campo.leer(campo, "operaciÃ³n  ")

      assert %AnchoFijo.Diagnostico{tipo: :doble_codificacion, gravedad: :advertencia, campo: :m} =
               d

      assert d.esperado == "operación"
      assert d.recibido == "\"operaciÃ³n\""
      assert d.causa_probable =~ "declare encoding: :utf8 en este campo"

      assert Campo.extraer(campo, "operaciÃ³n  ") == {:ok, "operaciÃ³n"}
    end

    test "con reparar_doble_codificacion: true el valor sale reparado y la advertencia lo dice" do
      campo = Campo.nuevo!(nombre: :m, posicion: 1, largo: 12, reparar_doble_codificacion: true)
      assert {:ok, "operación", [d]} = Campo.leer(campo, "operaciÃ³n  ")

      assert d.causa_probable =~
               "se reparó porque el campo declara reparar_doble_codificacion: true"
    end

    test "un texto sano no advierte nada, y un campo sensible no muestra el texto" do
      campo = Campo.nuevo!(nombre: :m, posicion: 1, largo: 12)
      assert {:ok, "JOSÉ MUÑOZ", []} = Campo.leer(campo, "JOSÉ MUÑOZ ")

      sensible = Campo.nuevo!(nombre: :m, posicion: 1, largo: 12, sensible: true)
      assert {:ok, _, [d]} = Campo.leer(sensible, "operaciÃ³n  ")
      refute AnchoFijo.Diagnostico.mensaje(d) =~ "operaci"
      assert d.contenido == "operación"
      assert d.esperado == "el texto UTF-8 decodificado una sola vez"
    end

    test "la opción solo existe en :texto" do
      assert {:error, [d]} =
               Campo.nuevo(nombre: :n, largo: 5, tipo: :entero, reparar_doble_codificacion: true)

      assert d.esperado == ":reparar_doble_codificacion solo en campos :texto"
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

    test "rechaza un :signo que no reconoce" do
      {:error, [diagnostico]} = Campo.nuevo(nombre: :a, largo: 4, tipo: :entero, signo: :atras)

      assert diagnostico.esperado == ":signo en [:inicial, :final]"
    end

    test ":signo solo aplica a :entero y :decimal" do
      {:error, [diagnostico]} = Campo.nuevo(nombre: :a, largo: 4, signo: :final)

      assert diagnostico.esperado == ":signo solo en campos :entero o :decimal"
      assert diagnostico.causa_probable =~ "sería ignorada en silencio"
    end

    test "el default de :signo es :inicial" do
      assert Campo.nuevo!(nombre: :a, largo: 4, tipo: :entero).signo == :inicial
    end

    test "rango/1 y fin/1 son 1-based e inclusivos" do
      campo = Campo.nuevo!(nombre: :a, posicion: 21, largo: 12)

      assert Campo.rango(campo) == {21, 32}
      assert Campo.fin(campo) == 32
    end
  end
end
