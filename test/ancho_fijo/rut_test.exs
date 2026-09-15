defmodule AnchoFijo.RutTest do
  use ExUnit.Case, async: true

  alias AnchoFijo.Rut

  describe "digito_verificador/1" do
    # Respuestas conocidas, calculadas a mano y contrastadas con el Registro
    # Civil. Existen porque el generador de los tests de propiedades usa la
    # misma función: sin estas, una implementación equivocada se validaría a
    # sí misma.
    test "casos de tabla" do
      assert Rut.digito_verificador(12_345_678) == "5"
      assert Rut.digito_verificador(11_111_111) == "1"
      assert Rut.digito_verificador(76_086_428) == "5"
      assert Rut.digito_verificador(22_222_222) == "2"
      assert Rut.digito_verificador(99_999_999) == "9"
      assert Rut.digito_verificador(1) == "9"
      assert Rut.digito_verificador(24) == "8"
    end

    test "el resto 10 es K y el resto 11 es 0" do
      assert Rut.digito_verificador(10_000_013) == "K"
      assert Rut.digito_verificador(10_000_004) == "0"
    end

    test "la serie 2..7 vuelve a empezar después del sexto dígito" do
      # 100000000 tiene nueve dígitos: el 1 cae en el tercer multiplicador de
      # la segunda vuelta, que es 4. 11 - (4 rem 11) = 7.
      assert Rut.digito_verificador(100_000_000) == "7"
    end
  end

  describe "normalizar/2" do
    test "las variantes de presentación normalizan igual" do
      for entrada <- ["12345678-5", "123456785", "12.345.678-5", "0000123456785", " 12345678-5 "] do
        assert Rut.normalizar(entrada) == {:ok, "12345678-5"}, entrada
      end
    end

    test "la K se acepta en minúscula y se devuelve en mayúscula" do
      assert Rut.normalizar("10000013-k") == {:ok, "10000013-K"}
      assert Rut.normalizar("010000013K") == {:ok, "10000013-K"}
    end

    test "un DV que no cuadra dice cuál correspondía" do
      assert Rut.normalizar("12345678-9") == {:error, {:dv, "5", "9"}}
    end

    test "con :no_validar el DV malo pasa" do
      assert Rut.normalizar("12345678-9", :no_validar) == {:ok, "12345678-9"}
    end

    test "con :ausente el texto es solo el cuerpo" do
      assert Rut.normalizar("0012345678", :ausente) == {:ok, "12345678"}
      assert Rut.normalizar("12.345.678", :ausente) == {:ok, "12345678"}
    end

    test "con :ausente, un DV pegado al cuerpo es un error de formato" do
      assert {:error, {:formato, _}} = Rut.normalizar("12345678-5", :ausente)
      assert {:error, {:formato, _}} = Rut.normalizar("12345678K", :ausente)
    end

    test "letras que no son K, guion sin DV y cuerpo en cero son errores de formato" do
      assert {:error, {:formato, _}} = Rut.normalizar("1234567A-9")
      assert {:error, {:formato, _}} = Rut.normalizar("12345678-")
      assert {:error, {:formato, _}} = Rut.normalizar("-5")
      assert Rut.normalizar("0-0") == {:error, {:formato, "el cuerpo del RUT es cero"}}
    end
  end

  describe "valido?/1" do
    test "responde por el DV" do
      assert Rut.valido?("76.086.428-5")
      refute Rut.valido?("76.086.428-6")
      refute Rut.valido?("no es un rut")
    end
  end
end
