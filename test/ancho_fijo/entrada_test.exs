defmodule AnchoFijo.EntradaTest do
  # Cómo se decide si un binario es una ruta o el contenido, y qué se dice
  # cuando parece una ruta y no existe.
  use ExUnit.Case, async: true

  import AnchoFijo.Fixtures

  alias AnchoFijo.Diagnostico
  alias AnchoFijo.Multiregistro

  @layout [campos: [[nombre: :a, largo: 48]]]
  @pista "si quiso pasar el contenido y no una ruta, declare desde: :contenido"

  describe "una ruta que parece ruta y no existe" do
    test "parsear/3 dice que no existe, no que la línea mide 16 bytes" do
      assert {:error, [%Diagnostico{tipo: :entrada} = d]} =
               AnchoFijo.parsear(@layout, "nomina_enero.txt")

      assert d.esperado == ~s(un archivo legible en "nomina_enero.txt")
      assert d.recibido == ":enoent"
      assert d.causa_probable == "la ruta no existe; revise el directorio de trabajo; " <> @pista
    end

    test "parsear!/3, stream/3, detectar/2, huella/2 e identidad/3 también" do
      assert_raise AnchoFijo.Error, ~r/la ruta no existe/, fn ->
        AnchoFijo.parsear!(@layout, "datos/nomina.txt")
      end

      assert [{:error, [%Diagnostico{tipo: :entrada}]}] =
               @layout |> AnchoFijo.stream("datos/nomina.txt") |> Enum.to_list()

      assert {:error, [%Diagnostico{tipo: :entrada} = d]} = AnchoFijo.detectar("datos/nomina.txt")
      assert d.causa_probable =~ @pista

      assert {:error, [%Diagnostico{tipo: :entrada}]} = AnchoFijo.huella("nomina.txt")
      assert {:error, [%Diagnostico{tipo: :entrada}]} = AnchoFijo.identidad(@layout, "nomina.txt")
      assert {:error, [%Diagnostico{tipo: :entrada}]} = AnchoFijo.huella("nomina.txt", traza: true)
    end

    test "con un multiregistro también" do
      multi =
        Multiregistro.nuevo!(
          discriminador: [largo: 1],
          registros: [d: [valor: "D", layout: [campos: [[nombre: :t, largo: 1]]]]]
        )

      assert {:error, [%Diagnostico{tipo: :entrada}]} = AnchoFijo.parsear(multi, "lote.dat")

      assert [{:error, [%Diagnostico{tipo: :entrada}]}] =
               multi |> AnchoFijo.stream("C:\\lotes\\lote.dat") |> Enum.to_list()
    end

    test "con desde: :archivo la pista sobre desde: :contenido no aparece" do
      assert {:error, [d]} = AnchoFijo.parsear(@layout, "nomina.txt", desde: :archivo)
      assert d.causa_probable == "la ruta no existe; revise el directorio de trabajo"
    end

    test "un directorio que parece ruta es un diagnóstico de directorio" do
      assert {:error, [%Diagnostico{tipo: :entrada} = d]} = AnchoFijo.parsear(@layout, "/tmp")
      assert d.recibido == ":eisdir"
    end
  end

  describe "lo que sigue siendo contenido" do
    test "con desde: :contenido, aunque termine en una extensión" do
      assert {:ok, [%{a: "ABC.TXT"}], []} =
               AnchoFijo.parsear([campos: [[nombre: :a, largo: 7]]], "ABC.TXT", desde: :contenido)

      assert {:ok, %{lineas_analizadas: 1}} = AnchoFijo.detectar("ABC.TXT", desde: :contenido)
    end

    test "sin extensión ni separador, en :auto" do
      assert {:ok, [%{rut: "12345678-9", nombre: "JUAN PEREZ"}], []} =
               AnchoFijo.parsear(
                 [
                   campos: [
                     [nombre: :rut, largo: 10, tipo: :rut, dv: :no_validar],
                     [nombre: :nombre, largo: 10]
                   ]
                 ],
                 "12345678-9JUAN PEREZ"
               )

      assert {:ok, [%{a: "TOTAL 12.50"}], []} =
               AnchoFijo.parsear([campos: [[nombre: :a, largo: 11]]], "TOTAL 12.50")
    end

    test "una fecha con barras o un separador en el medio no son una ruta" do
      assert {:ok, [%{a: "01/01/1950"}], []} =
               AnchoFijo.parsear([campos: [[nombre: :a, largo: 10]]], "01/01/1950")

      assert {:ok, [%{a: "datos/nomina"}], []} =
               AnchoFijo.parsear([campos: [[nombre: :a, largo: 12]]], "datos/nomina")
    end

    test "un prefijo de ruta sí: absoluta, relativa, home o unidad de Windows" do
      for ruta <- [
            "/var/lotes/nomina",
            "./nomina",
            "../nomina",
            "~/nomina",
            "C:\\lotes\\nomina",
            "D:/lotes/nomina"
          ] do
        assert {:error, [%Diagnostico{tipo: :entrada, recibido: ":enoent"}]} =
                 AnchoFijo.parsear(@layout, ruta),
               ruta
      end
    end

    test "con un salto de línea, aunque parezca una ruta" do
      assert {:ok, [%{a: "nomina.txt"}], []} =
               AnchoFijo.parsear([campos: [[nombre: :a, largo: 10]]], "nomina.txt\n")
    end

    test "una ruta que sí existe se lee como archivo" do
      assert {:ok, %{lineas_analizadas: n}} = AnchoFijo.detectar(ruta("nomina_correcta.txt"))
      assert n > 1
    end
  end
end
