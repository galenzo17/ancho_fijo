defmodule AnchoFijo.DoctestTest do
  use ExUnit.Case, async: true

  doctest AnchoFijo
  doctest AnchoFijo.Campo
  doctest AnchoFijo.Detector
  doctest AnchoFijo.Diagnostico
  doctest AnchoFijo.Formatos
  doctest AnchoFijo.Layout
  doctest AnchoFijo.Multiregistro
  doctest AnchoFijo.Parser
  doctest AnchoFijo.Rut
  doctest AnchoFijo.Transcodificacion
end
