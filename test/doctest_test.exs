defmodule AnchoFijo.DoctestTest do
  use ExUnit.Case, async: true

  doctest AnchoFijo
  doctest AnchoFijo.Campo
  doctest AnchoFijo.Detector
  doctest AnchoFijo.Diagnostico
  doctest AnchoFijo.Layout
  doctest AnchoFijo.Monto
  doctest AnchoFijo.Parser
  doctest AnchoFijo.Rut
  doctest AnchoFijo.Transcodificacion
  doctest AnchoFijo.Traza
end
