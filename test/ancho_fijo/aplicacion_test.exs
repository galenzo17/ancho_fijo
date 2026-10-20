defmodule AnchoFijo.AplicacionTest do
  use ExUnit.Case, async: true

  # `Traza.huella/2` usa :crypto, que es de OTP pero no viene solo: un release
  # incluye únicamente las aplicaciones alcanzables desde `applications`, y
  # sin esta declaración huella/2 revienta recién en producción.
  test ":crypto está declarado entre las aplicaciones de ancho_fijo" do
    assert :crypto in Application.spec(:ancho_fijo, :applications)
  end
end
