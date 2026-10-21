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
