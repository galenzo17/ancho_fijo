defmodule AnchoFijo.Test do
  @moduledoc """
  Lo que todo consumidor termina escribiendo en sus tests, en tres
  aserciones: parsear una línea y comparar, verificar que un diagnóstico
  apunta donde debe, y el round-trip de escribir y volver a leer.

      defmodule MiApp.NominaTest do
        use ExUnit.Case
        import AnchoFijo.Test

        @layout MiApp.Nomina.layout()

        test "una línea válida" do
          assert_parsea(@layout, "12345678-5JUAN PEREZ  0012345620240131", %{rut: "12345678-5", monto: {123_456, 2}})
        end

        test "un monto con letras se diagnostica en el monto" do
          @layout |> AnchoFijo.parsear("12345678-5JUAN PEREZ  00AB345620240131\\n") |> assert_diagnostico(campo: :monto, causa: ~r/no numérico/)
        end

        test "lo que se escribe se vuelve a leer" do
          assert_round_trip(@layout, %{rut: "12345678-5", beneficiario: "JUAN PEREZ", monto: {123_456, 2}, fecha_pago: ~D[2024-01-31]})
        end
      end

  Con `StreamData` en el proyecto, `AnchoFijo.Test.Generadores` genera
  registros válidos para cualquier layout, y el round-trip se vuelve una
  propiedad:

      property "escribir y leer da lo mismo para cualquier registro" do
        check all registro <- AnchoFijo.Test.Generadores.registro(@layout) do
          assert_round_trip(@layout, registro)
        end
      end

  Las aserciones levantan `ExUnit.AssertionError` con los diagnósticos en
  el mensaje, así que el fallo se lee en la salida de `mix test` sin
  `inspect` de por medio. No dependen de nada más que de ExUnit, que viene
  con Elixir.
  """

  alias AnchoFijo.Diagnostico
  alias AnchoFijo.Layout
  alias AnchoFijo.Multiregistro

  @doc """
  Parsea una línea (o varias: el contenido) con el layout y afirma que los
  registros son exactamente `esperado` (un mapa, o una lista de mapas o de
  `{tipo, mapa}` para un multiregistro). Devuelve los registros. Acepta las
  opciones de `AnchoFijo.parsear/3`; el terminador final se agrega si falta.
  """
  @spec assert_parsea(
          Layout.t() | Multiregistro.t() | Enumerable.t(),
          binary(),
          map() | [term()],
          keyword()
        ) ::
          [term()]
  def assert_parsea(layout, contenido, esperado, opts \\ []) do
    esperados = if is_map(esperado), do: [esperado], else: esperado

    case AnchoFijo.parsear(layout, con_terminador(contenido), opts) do
      {:ok, ^esperados, _advertencias} ->
        esperados

      {:ok, registros, diagnosticos} ->
        fallar(
          "los registros no son los esperados",
          esperado: esperados,
          obtenido: registros,
          diagnosticos: diagnosticos
        )

      {:error, diagnosticos} ->
        fallar("no se pudo parsear", esperado: esperados, diagnosticos: diagnosticos)
    end
  end

  @doc """
  Afirma que entre los diagnósticos hay uno que cumple todos los filtros y
  lo devuelve. `resultado` es lo que devuelve `parsear/3`, `escribir/3` o
  `Layout.nuevo/1` (`{:error, diagnosticos}` o `{:ok, _, diagnosticos}`),
  o una lista de diagnósticos.

  Filtros: `tipo:`, `gravedad:`, `campo:`, `linea:` (igualdad) y `causa:`,
  `esperado:`, `recibido:` (un string que tiene que estar contenido, o una
  expresión regular).
  """
  @spec assert_diagnostico(term(), keyword()) :: Diagnostico.t()
  def assert_diagnostico(resultado, filtros) when is_list(filtros) do
    diagnosticos = diagnosticos_de(resultado)

    case Enum.find(diagnosticos, &cumple?(&1, filtros)) do
      %Diagnostico{} = diagnostico ->
        diagnostico

      nil ->
        fallar(
          "ningún diagnóstico cumple #{inspect(filtros)}",
          diagnosticos: diagnosticos
        )
    end
  end

  @doc """
  Escribe el registro (o los `{tipo, mapa}` de un multiregistro) con el
  layout, vuelve a parsear lo escrito y afirma que se obtiene lo mismo, sin
  diagnósticos. Devuelve el contenido escrito. Con un multiregistro, los
  controles que el trailer no trae salen calculados, y lo que se compara es
  lo leído contra lo leído de nuevo.
  """
  @spec assert_round_trip(
          Layout.t() | Multiregistro.t() | Enumerable.t(),
          map() | [term()],
          keyword()
        ) :: binary()
  def assert_round_trip(layout, registro, opts \\ []) do
    registros = if is_map(registro), do: [registro], else: registro

    contenido =
      case AnchoFijo.escribir(layout, registros, opts) do
        {:ok, contenido, _advertencias} ->
          contenido

        {:error, diagnosticos} ->
          fallar("no se pudo escribir", registros: registros, diagnosticos: diagnosticos)
      end

    case AnchoFijo.parsear(layout, contenido) do
      {:ok, ^registros, []} ->
        contenido

      {:ok, leidos, []} when is_struct(layout, Multiregistro) ->
        reescribir(layout, leidos, contenido, opts)

      {:ok, leidos, diagnosticos} ->
        fallar("lo escrito no se lee igual",
          escrito: contenido,
          esperado: registros,
          obtenido: leidos,
          diagnosticos: diagnosticos
        )

      {:error, diagnosticos} ->
        fallar("lo escrito no se puede leer", escrito: contenido, diagnosticos: diagnosticos)
    end
  end

  # Un multiregistro completa los controles al escribir: lo leído puede traer
  # más que lo escrito, y el round-trip que importa es el de lo leído.
  defp reescribir(layout, leidos, contenido, opts) do
    case AnchoFijo.escribir(layout, leidos, opts) do
      {:ok, ^contenido, _} ->
        contenido

      otro ->
        fallar("lo leído no se vuelve a escribir igual",
          escrito: contenido,
          releido: leidos,
          resultado: otro
        )
    end
  end

  @doc """
  Escribe el registro con el layout y afirma que la línea es exactamente
  `esperada` (sin terminador). Devuelve la línea.
  """
  @spec assert_escribe(Layout.t() | Enumerable.t(), map(), binary(), keyword()) :: binary()
  def assert_escribe(layout, registro, esperada, opts \\ []) do
    case AnchoFijo.escribir(layout, [registro], Keyword.put(opts, :terminador, :ninguno)) do
      {:ok, ^esperada, _} ->
        esperada

      {:ok, linea, _} ->
        fallar("la línea escrita no es la esperada", esperado: esperada, obtenido: linea)

      {:error, diagnosticos} ->
        fallar("no se pudo escribir", registro: registro, diagnosticos: diagnosticos)
    end
  end

  defp con_terminador(contenido) when is_binary(contenido) do
    if String.ends_with?(contenido, ["\n", "\r"]), do: contenido, else: contenido <> "\n"
  end

  defp con_terminador(otro), do: otro

  defp diagnosticos_de({:error, diagnosticos}) when is_list(diagnosticos), do: diagnosticos
  defp diagnosticos_de({:ok, _registros, diagnosticos}) when is_list(diagnosticos), do: diagnosticos
  defp diagnosticos_de(diagnosticos) when is_list(diagnosticos), do: diagnosticos
  defp diagnosticos_de(%Diagnostico{} = diagnostico), do: [diagnostico]
  defp diagnosticos_de(otro), do: fallar("no es un resultado con diagnósticos", obtenido: otro)

  defp cumple?(%Diagnostico{} = d, filtros) do
    Enum.all?(filtros, fn
      {clave, patron} when clave in [:causa, :esperado, :recibido] ->
        coincide?(Map.get(d, campo_de(clave)), patron)

      {clave, valor} ->
        Map.get(d, clave) == valor
    end)
  end

  defp campo_de(:causa), do: :causa_probable
  defp campo_de(clave), do: clave

  defp coincide?(nil, _patron), do: false
  defp coincide?(texto, %Regex{} = patron), do: Regex.match?(patron, texto)
  defp coincide?(texto, patron) when is_binary(patron), do: String.contains?(texto, patron)

  @spec fallar(String.t(), keyword()) :: no_return()
  defp fallar(titulo, detalles) do
    cuerpo =
      Enum.map_join(detalles, "\n", fn
        {:diagnosticos, []} ->
          "diagnósticos: ninguno"

        {:diagnosticos, lista} ->
          "diagnósticos:\n  " <> Enum.map_join(lista, "\n  ", &Diagnostico.mensaje/1)

        {clave, valor} ->
          "#{clave}: #{inspect(valor, pretty: true, width: 100)}"
      end)

    raise ExUnit.AssertionError, message: titulo <> "\n" <> cuerpo
  end
end
