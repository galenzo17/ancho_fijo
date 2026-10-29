defmodule AnchoFijo.TranscodificacionTest do
  use ExUnit.Case, async: true

  alias AnchoFijo.Transcodificacion

  describe "a_utf8/2 con :latin1" do
    test "convierte todo el rango imprimible sin fallar" do
      bytes = for byte <- 0x20..0x7E, do: byte
      binario = :erlang.list_to_binary(bytes)

      assert {:ok, texto} = Transcodificacion.a_utf8(binario, :latin1)
      assert String.valid?(texto)
    end

    test "convierte los acentos del rango alto" do
      assert Transcodificacion.a_utf8(<<0xD1, 0xE9, 0xFC>>, :latin1) == {:ok, "Ñéü"}
    end

    test "el tabulador es texto legítimo y no un control" do
      assert Transcodificacion.a_utf8(<<65, ?\t, 66>>, :latin1) == {:ok, "A\tB"}
    end
  end

  describe "a_utf8/2 y de_utf8/2 con :cp1252" do
    @cp1252 Transcodificacion.cp1252()

    test "los 27 caracteres de 0x80–0x9F se leen y se escriben, y el resto es latin-1" do
      assert map_size(@cp1252) == 27

      for {byte, codepoint} <- @cp1252 do
        assert {:ok, <<^codepoint::utf8>>} = Transcodificacion.a_utf8(<<byte>>, :cp1252)
        assert {:ok, <<^byte>>} = Transcodificacion.de_utf8(<<codepoint::utf8>>, :cp1252)
      end

      assert {:ok, "JOSÉ “X”"} =
               Transcodificacion.a_utf8(<<74, 79, 83, 201, 32, 0x93, 88, 0x94>>, :cp1252)

      assert {:ok, <<0x80, 32, 49, 48, 32, 241>>} = Transcodificacion.de_utf8("€ 10 ñ", :cp1252)
      assert {:ok, "SOLO ASCII"} = Transcodificacion.a_utf8("SOLO ASCII", :cp1252)
    end

    test "los cinco bytes sin definir y los controles son un diagnóstico" do
      for byte <- [0x81, 0x8D, 0x8F, 0x90, 0x9D] do
        assert {:error, %{motivo: :byte_sin_definir, posicion: 1, byte: ^byte} = detalle} =
                 Transcodificacion.a_utf8(<<65, byte>>, :cp1252)

        assert Transcodificacion.causa_probable(detalle, :cp1252) =~
                 "no está definido en Windows-1252"
      end

      assert {:error, %{motivo: :caracter_de_control, byte: 0}} =
               Transcodificacion.a_utf8(<<65, 0>>, :cp1252)

      assert {:error, %{motivo: :caracter_de_control, byte: 0x7F}} =
               Transcodificacion.a_utf8(<<0x7F>>, :cp1252)
    end

    test "un carácter que Windows-1252 no tiene es el primer error, con su posición" do
      assert {:error, %{posicion: 3, caracter: "→"}} = Transcodificacion.de_utf8("a → b", :cp1252)
      assert {:error, %{posicion: 2, caracter: "😀"}} = Transcodificacion.de_utf8("a😀", :latin1)

      assert {:error, %{posicion: 1, caracter: <<0x85::utf8>>}} =
               Transcodificacion.de_utf8(<<0x85::utf8>>, :cp1252)
    end

    test "detectar/1 y cp1252?/1 distinguen cp1252 de latin-1" do
      assert Transcodificacion.detectar(<<74, 79, 83, 201, 32, 0x93>>) == :cp1252
      assert Transcodificacion.detectar(<<74, 79, 83, 201>>) == :latin1
      refute Transcodificacion.cp1252?(<<0x81, 0x8D>>)
    end

    test "el diagnóstico de un layout latin-1 o UTF-8 dice que declare :cp1252" do
      assert {:error, detalle} = Transcodificacion.a_utf8(<<0x93>>, :latin1)
      assert Transcodificacion.causa_probable(detalle, :latin1) =~ "declare encoding: :cp1252"

      assert {:error, detalle} = Transcodificacion.a_utf8(<<65, 0x93, 66>>, :utf8)
      assert Transcodificacion.causa_probable(detalle, :utf8) =~ "declare encoding: :cp1252"

      # Al principio del campo, la explicación probable sigue siendo el corte de un multibyte.
      assert {:error, detalle} = Transcodificacion.a_utf8(<<0x80, 66>>, :utf8)
      assert Transcodificacion.causa_probable(detalle, :utf8) =~ "campo anterior"
    end
  end

  describe "a_utf8/2 con :utf8" do
    test "acepta multibyte válido" do
      assert Transcodificacion.a_utf8("ÑOÑO", :utf8) == {:ok, "ÑOÑO"}
    end

    test "un byte latin-1 en medio del texto se ubica exacto" do
      {:error, detalle} = Transcodificacion.a_utf8(<<65, 66, 0xF1, 67>>, :utf8)

      assert detalle == %{motivo: :bytes_invalidos, posicion: 2, byte: 0xF1}
    end

    test "un multibyte cortado a la mitad se distingue de un byte inválido" do
      {:error, detalle} = Transcodificacion.a_utf8(<<65, 0xC3>>, :utf8)

      assert detalle.motivo == :secuencia_incompleta
      assert Transcodificacion.causa_probable(detalle, :utf8) =~ "unidad: :caracteres"
    end
  end

  describe "caracteres de control" do
    test "el rango cp1252 se señala como tal" do
      for byte <- [0x91, 0x92, 0x93, 0x96] do
        {:error, detalle} = Transcodificacion.a_utf8(<<65, byte>>, :latin1)

        assert detalle.motivo == :caracter_de_control
        assert Transcodificacion.causa_probable(detalle, :latin1) =~ "cp1252"
      end
    end

    test "un byte nulo se reporta con su posición" do
      {:error, detalle} = Transcodificacion.a_utf8(<<65, 66, 67, 0>>, :latin1)

      assert detalle == %{motivo: :caracter_de_control, posicion: 3, byte: 0}
    end

    test "un carácter de control en UTF-8 válido también se rechaza" do
      {:error, detalle} = Transcodificacion.a_utf8("AÑ" <> <<0x07>>, :utf8)

      assert detalle.motivo == :caracter_de_control
      assert detalle.posicion == 3
    end
  end

  describe "un campo cortado en medio de un carácter multibyte" do
    test "la continuación suelta al inicio dice que el campo anterior lo cortó" do
      assert {:error, detalle} = Transcodificacion.a_utf8(<<0xB3, 110, 32>>, :utf8)
      assert detalle.motivo == :continuacion_suelta
      assert detalle.posicion == 0

      assert Transcodificacion.causa_probable(detalle, :utf8) =~
               "empieza con 0xB3, la continuación de un carácter multibyte que empezó en el campo anterior"

      assert Transcodificacion.causa_probable(detalle, :utf8) =~ "pruebe unidad: :caracteres"
    end

    test "una continuación suelta en el medio es un texto cortado o corrido" do
      assert {:error, %{motivo: :continuacion_suelta, posicion: 2}} =
               Transcodificacion.a_utf8(<<65, 66, 0x80, 67>>, :utf8)

      assert Transcodificacion.causa_probable(
               %{motivo: :continuacion_suelta, posicion: 2, byte: 0x80},
               :utf8
             ) =~ "sin su inicio"
    end

    test "un byte latin-1 que no es continuación sigue siendo bytes_invalidos" do
      assert {:error, %{motivo: :bytes_invalidos, byte: 0xC9}} =
               Transcodificacion.a_utf8(<<74, 0xC9, 32>>, :utf8)
    end
  end

  describe "multibyte_utf8?/1 y doble_codificacion/1" do
    test "reconoce una secuencia UTF-8 válida aunque el resto sea latin-1" do
      assert Transcodificacion.multibyte_utf8?(<<74, 79, 83, 0xC9, 32>> <> "ción")
      refute Transcodificacion.multibyte_utf8?(<<74, 79, 83, 0xC9, 32>>)
      refute Transcodificacion.multibyte_utf8?("ASCII")
      refute Transcodificacion.multibyte_utf8?(<<0xC3>>)
    end

    test "la doble codificación se repara y lo que no la tiene queda igual" do
      assert Transcodificacion.doble_codificacion("operaciÃ³n") == {:ok, "operación"}
      assert Transcodificacion.doble_codificacion("MUÃ‘OZ") == :no
      assert Transcodificacion.doble_codificacion("JOSÉ MUÑOZ") == :no
      assert Transcodificacion.doble_codificacion("Ã±andÃº") == {:ok, "ñandú"}

      # Latin-1 legítimo cuya reinterpretación es una secuencia de tres o
      # cuatro bytes válida: una vocal acentuada seguida de puntos medios.
      assert Transcodificacion.doble_codificacion("ñ···") == :no
      assert Transcodificacion.doble_codificacion("é··") == :no
      assert Transcodificacion.doble_codificacion("Año·2024") == :no
      assert Transcodificacion.doble_codificacion("日本") == :no
      assert Transcodificacion.doble_codificacion("") == :no
    end
  end

  describe "detectar/1" do
    test "ASCII significa que la pregunta no importa" do
      assert Transcodificacion.detectar("SOLO ASCII 123") == :ascii
    end

    test "UTF-8 válido con multibyte" do
      assert Transcodificacion.detectar("MUÑOZ") == :utf8
    end

    test "bytes altos que no son UTF-8 son latin-1" do
      assert Transcodificacion.detectar(<<77, 85, 0xD1, 79, 90>>) == :latin1
    end

    test "un binario vacío es ASCII" do
      assert Transcodificacion.detectar("") == :ascii
    end
  end

  describe "describir_byte/2" do
    test "traduce el offset a la posición que el usuario puede contar" do
      detalle = %{motivo: :bytes_invalidos, posicion: 0, byte: 0xD1}

      assert Transcodificacion.describir_byte(detalle, 1) == "el byte 0xD1 en la posición 1"
      assert Transcodificacion.describir_byte(detalle, 21) == "el byte 0xD1 en la posición 21"
    end

    test "rellena el hexadecimal a dos dígitos" do
      detalle = %{motivo: :caracter_de_control, posicion: 0, byte: 9}

      assert Transcodificacion.describir_byte(detalle, 1) == "el byte 0x09 en la posición 1"
    end
  end
end
