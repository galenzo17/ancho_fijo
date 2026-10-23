defmodule AnchoFijo.TipoTest do
  use ExUnit.Case, async: true

  alias AnchoFijo.Campo
  alias AnchoFijo.Diagnostico
  alias AnchoFijo.Layout
  alias AnchoFijo.Tipo
  alias AnchoFijo.TipoHora

  describe "los tipos internos son implementaciones del behaviour" do
    test "cada átomo resuelve a su módulo y cada módulo implementa los callbacks" do
      for {atomo, modulo} <- Tipo.internos() do
        assert {:ok, ^modulo} = Tipo.resolver(atomo)
        assert {:ok, ^modulo} = Tipo.resolver(modulo)
        assert Tipo in (modulo.module_info(:attributes)[:behaviour] || [])
        assert is_list(modulo.opciones())
      end
    end

    test "el módulo queda en el campo y se puede declarar directamente" do
      por_atomo = Campo.nuevo!(nombre: :a, posicion: 1, largo: 8, tipo: :entero)
      por_modulo = Campo.nuevo!(nombre: :a, posicion: 1, largo: 8, tipo: Tipo.Entero)

      assert por_atomo.modulo == Tipo.Entero
      assert por_modulo.modulo == Tipo.Entero
      assert Campo.extraer(por_modulo, "00001234", %{}) == {:ok, 1234}
    end
  end

  describe "un tipo propio" do
    @layout Layout.nuevo!(
              campos: [
                [nombre: :codigo, largo: 3, tipo: :entero],
                [nombre: :hora, largo: 4, tipo: TipoHora],
                [nombre: :hora_exacta, largo: 6, tipo: TipoHora, segundos: true]
              ]
            )

    test "parsea con sus opciones propias" do
      assert {:ok, [registro], []} = AnchoFijo.parsear(@layout, "0011430093015\n")
      assert registro == %{codigo: 1, hora: ~T[14:30:00], hora_exacta: ~T[09:30:15]}
    end

    test "sus opciones viven en :opciones y las comunes en el struct" do
      [_, hora, exacta] = @layout.campos
      assert hora.opciones == %{}
      assert exacta.opciones == %{segundos: true}
      assert exacta.largo == 6
      assert exacta.tipo == TipoHora
      assert exacta.modulo == TipoHora
    end

    test "produce diagnósticos indistinguibles de los internos" do
      assert {:ok, [], [propio, interno]} =
               AnchoFijo.parsear(@layout, "00125xx093015\n0x11430093015\n", modo: :tolerante)

      assert %Diagnostico{tipo: :campo_invalido, linea: 1, campo: :hora, posicion: {4, 7}} = propio

      assert %Diagnostico{tipo: :campo_invalido, linea: 2, campo: :codigo, posicion: {1, 3}} =
               interno

      assert Diagnostico.mensaje(propio) ==
               "línea 1, campo :hora (posiciones 4-7): se esperaban una hora HHMM, llegaron \"25xx\"; " <>
                 "hay caracteres no numéricos o la hora no existe"
    end

    test "valida sus opciones al construir el layout, no al parsear" do
      assert {:error, [diagnostico]} =
               Layout.nuevo(campos: [[nombre: :h, largo: 4, tipo: TipoHora, segundos: :si]])

      assert %Diagnostico{tipo: :layout, campo: :h, esperado: ":segundos true o false"} =
               diagnostico

      assert {:error, [diagnostico]} =
               Layout.nuevo(campos: [[nombre: :h, largo: 5, tipo: TipoHora]])

      assert diagnostico.esperado == "un :largo de 4 para la hora"
    end

    test "una opción que el tipo no declara es un error del layout" do
      assert {:error, [diagnostico]} =
               Layout.nuevo(campos: [[nombre: :h, largo: 4, tipo: TipoHora, segundo: true]])

      assert diagnostico.recibido == ":segundo"
      assert diagnostico.esperado == "opciones de AnchoFijo.TipoHora: :segundos"
    end

    test "las opciones de los tipos internos tampoco se cuelan en un tipo propio" do
      assert {:error, [diagnostico]} =
               Layout.nuevo(campos: [[nombre: :h, largo: 4, tipo: TipoHora, precision: 2]])

      assert diagnostico.esperado == ":precision solo en campos :decimal"
    end

    test "en blanco: nil con opcional, diagnóstico estándar sin él" do
      opcional = Campo.nuevo!(nombre: :h, posicion: 1, largo: 4, tipo: TipoHora, opcional: true)
      assert Campo.extraer(opcional, "    ", %{}) == {:ok, nil}

      obligatorio = Campo.nuevo!(nombre: :h, posicion: 1, largo: 4, tipo: TipoHora)
      assert {:error, diagnostico} = Campo.extraer(obligatorio, "    ", %{linea: 3})
      assert diagnostico.recibido == "un campo en blanco"
      assert diagnostico.esperado == "un valor AnchoFijo.TipoHora"
      assert diagnostico.linea == 3
    end
  end

  describe "un módulo que no sirve como tipo" do
    test "uno que no implementa el behaviour es un diagnóstico de layout" do
      assert {:error, [diagnostico]} =
               Layout.nuevo(campos: [[nombre: :h, largo: 4, tipo: AnchoFijo.TipoIncompleto]])

      assert diagnostico.tipo == :layout

      assert diagnostico.esperado =~
               "AnchoFijo.TipoIncompleto no implementa opciones/0, validar/1 y leer/3"
    end

    test "uno que no existe es un diagnóstico de layout" do
      assert {:error, [diagnostico]} =
               Layout.nuevo(campos: [[nombre: :h, largo: 4, tipo: MiApp.NoExiste]])

      assert diagnostico.esperado =~ "MiApp.NoExiste no existe"
    end

    test "un átomo que no es tipo interno lista los tipos" do
      assert {:error, [diagnostico]} = Layout.nuevo(campos: [[nombre: :h, largo: 4, tipo: :hora]])

      assert diagnostico.esperado ==
               "un :tipo en [:texto, :entero, :decimal, :fecha, :rut, :constante, :relleno] o un módulo que implemente AnchoFijo.Tipo"

      assert diagnostico.recibido == ":hora"
    end

    test "el resto de la definición se valida igual, para reportar todo junto" do
      assert {:error, diagnosticos} = Layout.nuevo(campos: [[nombre: :h, largo: 0, tipo: :hora]])
      assert Enum.map(diagnosticos, & &1.recibido) == ["0", ":hora"]
    end
  end
end
