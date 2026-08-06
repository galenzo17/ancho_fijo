defmodule AnchoFijo.DoctestTest do
  use ExUnit.Case, async: true

  doctest AnchoFijo
  doctest AnchoFijo.Campo
  doctest AnchoFijo.Detector
  doctest AnchoFijo.Diagnostico
  doctest AnchoFijo.Layout
  doctest AnchoFijo.Parser
  doctest AnchoFijo.Transcodificacion
end
