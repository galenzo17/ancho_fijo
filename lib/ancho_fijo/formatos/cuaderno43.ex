defmodule AnchoFijo.Formatos.Cuaderno43 do
  @fuente "Asociación Española de Banca (AEB), Cuaderno 43, «Información normalizada de " <>
            "cuenta corriente», versión de junio de 2012 (la vigente), tal como la publica " <>
            "la AEB y la reproducen las guías de exportación de los bancos; posiciones " <>
            "verificadas contra esa norma, consultada el 2026-10-29."

  @moduledoc """
  Cuaderno 43 de la AEB: el extracto bancario normalizado de España, el que
  exportan todos los bancos y consumen las contabilidades, los ERP y las
  fintech de conciliación.

  Registros de 80 posiciones, con seis tipos: cabecera de cuenta (11),
  movimiento (22), concepto complementario (23, de cero a cinco por
  movimiento), información de equivalencia de importe (24), final de cuenta
  (33) y fin de fichero (88). Un archivo trae una o varias cuentas, cada una
  como un bloque cabecera, movimientos, final.

  ## Fuente

  #{@fuente}

  Los nombres de los campos son los de la norma, en español y en
  `snake_case`, para verificar el layout campo por campo contra el cuaderno:
  `clave_debe_haber` es "Clave debe o haber", posición 28 del registro 22.

  ## Qué valida la librería y qué valida este módulo

  `AnchoFijo.parsear/3` con `AnchoFijo.Formatos.cuaderno43/1` lee cada
  registro con su layout, verifica el discriminador, que haya al menos una
  cabecera y un final de cuenta y exactamente un fin de fichero. Lo que es
  propio del cuaderno lo hace `validar/1` sobre los registros leídos:

    * por cuenta, en el registro 33: el número de apuntes y el total de
      importes al debe y al haber, contados y sumados de los movimientos
      según su clave; que el saldo final sea el inicial más el haber menos
      el debe, con el signo que dice cada clave; y que la entidad, la
      oficina y la cuenta sean las de la cabecera;
    * en el archivo, en el registro 88: el número de registros (todos los
      anteriores al 88);
    * la estructura: un movimiento, un concepto o un final sin cabecera, un
      concepto o una equivalencia sin movimiento, una cabecera sin final.

  Cada desacuerdo es un `AnchoFijo.Diagnostico` de tipo `:control` o
  `:estructura`, con la línea del registro, el valor calculado, el
  declarado y de qué se calculó. `cuentas/1` arma la estructura anidada:
  cada cuenta con su cabecera, sus movimientos (cada uno con sus conceptos
  complementarios y sus equivalencias) y su final.

  ## Lo que no está

  Las fechas `AAMMDD` se leen con pivote 2000: `24` es 2024. Los importes
  vienen en céntimos, `{unidades, 2}`, con la clave debe/haber aparte, como
  en la norma; `saldo/1` los junta en un entero con signo. La clave de
  divisa es el código numérico ISO 4217 (`"978"` es el euro) y se lee como
  texto.
  """

  alias AnchoFijo.Diagnostico
  alias AnchoFijo.Layout
  alias AnchoFijo.Multiregistro

  @doc "La fuente de la que se transcribió el formato."
  @spec fuente() :: String.t()
  def fuente, do: @fuente

  @largo 80
  @pivote 2000

  @doc """
  El multiregistro del formato. El discriminador son las dos primeras
  posiciones, el código de registro.
  """
  @spec multiregistro() :: Multiregistro.t()
  def multiregistro do
    Multiregistro.nuevo!(
      nombre: "Cuaderno 43 (AEB)",
      discriminador: [posicion: 1, largo: 2],
      orden: :libre,
      registros: [
        cabecera_de_cuenta: [valor: "11", cantidad: :al_menos_uno, layout: cabecera_de_cuenta()],
        movimiento: [valor: "22", cantidad: :varios, layout: movimiento()],
        concepto_complementario: [
          valor: "23",
          cantidad: :varios,
          layout: concepto_complementario()
        ],
        equivalencia_de_importe: [
          valor: "24",
          cantidad: :varios,
          layout: equivalencia_de_importe()
        ],
        final_de_cuenta: [valor: "33", cantidad: :al_menos_uno, layout: final_de_cuenta()],
        fin_de_fichero: [valor: "88", cantidad: :uno, layout: fin_de_fichero()]
      ]
    )
  end

  @doc """
  Registro de cabecera de cuenta, código 11.

  Declara la identidad del extracto para `AnchoFijo.identidad/3`: la
  entidad, la oficina, la cuenta y las fechas inicial y final del período.
  """
  @spec cabecera_de_cuenta() :: Layout.t()
  def cabecera_de_cuenta do
    Layout.nuevo!(
      nombre: "Cuaderno 43 cabecera de cuenta",
      largo: @largo,
      identidad: [
        campos: [:clave_entidad, :clave_oficina, :numero_de_cuenta, :fecha_inicial, :fecha_final]
      ],
      campos: [
        [nombre: :codigo_de_registro, largo: 2],
        [nombre: :clave_entidad, largo: 4],
        [nombre: :clave_oficina, largo: 4],
        [nombre: :numero_de_cuenta, largo: 10],
        [nombre: :fecha_inicial, largo: 6, tipo: :fecha, formato: :aammdd, pivote: @pivote],
        [nombre: :fecha_final, largo: 6, tipo: :fecha, formato: :aammdd, pivote: @pivote],
        [nombre: :clave_debe_haber, largo: 1, en: ["1", "2"]],
        [nombre: :importe_saldo_inicial, largo: 14, tipo: :decimal, precision: 2],
        [nombre: :clave_divisa, largo: 3],
        [nombre: :modalidad_de_informacion, largo: 1, en: ["1", "2", "3"]],
        [nombre: :nombre_abreviado, largo: 26],
        [nombre: :libre, largo: 3, tipo: :relleno]
      ]
    )
  end

  @doc "Registro principal de movimiento, código 22."
  @spec movimiento() :: Layout.t()
  def movimiento do
    Layout.nuevo!(
      nombre: "Cuaderno 43 movimiento",
      largo: @largo,
      campos: [
        [nombre: :codigo_de_registro, largo: 2],
        [nombre: :libre, largo: 4, tipo: :relleno],
        [nombre: :clave_oficina_origen, largo: 4],
        [nombre: :fecha_operacion, largo: 6, tipo: :fecha, formato: :aammdd, pivote: @pivote],
        [nombre: :fecha_valor, largo: 6, tipo: :fecha, formato: :aammdd, pivote: @pivote],
        [nombre: :concepto_comun, largo: 2],
        [nombre: :concepto_propio, largo: 3],
        [nombre: :clave_debe_haber, largo: 1, en: ["1", "2"]],
        [nombre: :importe, largo: 14, tipo: :decimal, precision: 2],
        [nombre: :numero_de_documento, largo: 10],
        [nombre: :referencia_1, largo: 12],
        [nombre: :referencia_2, largo: 16]
      ]
    )
  end

  @doc "Registro complementario de concepto, código 23: de cero a cinco por movimiento."
  @spec concepto_complementario() :: Layout.t()
  def concepto_complementario do
    Layout.nuevo!(
      nombre: "Cuaderno 43 concepto complementario",
      largo: @largo,
      campos: [
        [nombre: :codigo_de_registro, largo: 2],
        [nombre: :codigo_de_dato, largo: 2, en: ["01", "02", "03", "04", "05"]],
        [nombre: :concepto_1, largo: 38],
        [nombre: :concepto_2, largo: 38]
      ]
    )
  end

  @doc "Registro complementario de información de equivalencia de importe, código 24."
  @spec equivalencia_de_importe() :: Layout.t()
  def equivalencia_de_importe do
    Layout.nuevo!(
      nombre: "Cuaderno 43 equivalencia de importe",
      largo: @largo,
      campos: [
        [nombre: :codigo_de_registro, largo: 2],
        [nombre: :codigo_de_dato, largo: 2],
        [nombre: :clave_divisa_origen, largo: 3],
        [nombre: :importe, largo: 14, tipo: :decimal, precision: 2],
        [nombre: :libre, largo: 59, tipo: :relleno]
      ]
    )
  end

  @doc "Registro final de cuenta, código 33."
  @spec final_de_cuenta() :: Layout.t()
  def final_de_cuenta do
    Layout.nuevo!(
      nombre: "Cuaderno 43 final de cuenta",
      largo: @largo,
      campos: [
        [nombre: :codigo_de_registro, largo: 2],
        [nombre: :clave_entidad, largo: 4],
        [nombre: :clave_oficina, largo: 4],
        [nombre: :numero_de_cuenta, largo: 10],
        [nombre: :numero_de_apuntes_debe, largo: 5, tipo: :entero],
        [nombre: :total_importes_debe, largo: 14, tipo: :decimal, precision: 2],
        [nombre: :numero_de_apuntes_haber, largo: 5, tipo: :entero],
        [nombre: :total_importes_haber, largo: 14, tipo: :decimal, precision: 2],
        [nombre: :codigo_saldo_final, largo: 1, en: ["1", "2"]],
        [nombre: :importe_saldo_final, largo: 14, tipo: :decimal, precision: 2],
        [nombre: :clave_divisa, largo: 3],
        [nombre: :libre, largo: 4, tipo: :relleno]
      ]
    )
  end

  @doc "Registro de fin de fichero, código 88."
  @spec fin_de_fichero() :: Layout.t()
  def fin_de_fichero do
    Layout.nuevo!(
      nombre: "Cuaderno 43 fin de fichero",
      largo: @largo,
      campos: [
        [nombre: :codigo_de_registro, largo: 2],
        [nombre: :nueves, largo: 20, en: [String.duplicate("9", 20)]],
        [nombre: :numero_de_registros, largo: 6, tipo: :entero],
        [nombre: :libre, largo: 52, tipo: :relleno]
      ]
    )
  end

  # ---------------------------------------------------------------- cuentas

  @type movimiento :: %{movimiento: map(), conceptos: [map()], equivalencias: [map()]}
  @type cuenta :: %{cabecera: map(), movimientos: [movimiento()], final: map() | nil}

  @doc """
  Arma las cuentas a partir de la lista ordenada de registros: cada una con
  su cabecera, sus movimientos (cada uno con sus conceptos complementarios y
  sus equivalencias de importe) y su final. Lo que aparece fuera de lugar
  se ignora acá; `validar/1` lo reporta.
  """
  @spec cuentas([Multiregistro.registro()]) :: [cuenta()]
  def cuentas(registros) do
    registros
    |> Enum.with_index(1)
    |> cuentas_numeradas()
    |> Enum.map(&Map.delete(&1, :linea))
  end

  # Las cuentas con el número de línea de su final, que es donde se reporta.
  defp cuentas_numeradas(numerados) do
    numerados
    |> Enum.reduce({[], nil}, fn
      {{:cabecera_de_cuenta, r}, n}, {cuentas, abierta} ->
        {cerrar(cuentas, abierta), %{cabecera: r, movimientos: [], final: nil, linea: n}}

      {{:movimiento, r}, _n}, {cuentas, %{} = cuenta} ->
        {cuentas,
         %{
           cuenta
           | movimientos: [%{movimiento: r, conceptos: [], equivalencias: []} | cuenta.movimientos]
         }}

      {{:concepto_complementario, r}, _n}, {cuentas, %{movimientos: [actual | resto]} = cuenta} ->
        {cuentas, %{cuenta | movimientos: [%{actual | conceptos: [r | actual.conceptos]} | resto]}}

      {{:equivalencia_de_importe, r}, _n}, {cuentas, %{movimientos: [actual | resto]} = cuenta} ->
        {cuentas,
         %{cuenta | movimientos: [%{actual | equivalencias: [r | actual.equivalencias]} | resto]}}

      {{:final_de_cuenta, r}, n}, {cuentas, %{} = cuenta} ->
        {cerrar(cuentas, %{cuenta | final: r, linea: n}), nil}

      _otro, acumulado ->
        acumulado
    end)
    |> then(fn {cuentas, abierta} -> cerrar(cuentas, abierta) end)
    |> Enum.reverse()
    |> Enum.map(fn cuenta ->
      movimientos =
        cuenta.movimientos
        |> Enum.reverse()
        |> Enum.map(
          &%{
            &1
            | conceptos: Enum.reverse(&1.conceptos),
              equivalencias: Enum.reverse(&1.equivalencias)
          }
        )

      %{cuenta | movimientos: movimientos}
    end)
  end

  defp cerrar(cuentas, nil), do: cuentas
  defp cerrar(cuentas, cuenta), do: [cuenta | cuentas]

  @doc """
  Un importe con su clave debe/haber como entero con signo, en céntimos: al
  debe negativo, al haber positivo.

      iex> AnchoFijo.Formatos.Cuaderno43.saldo("1", {25_050, 2})
      -25050
      iex> AnchoFijo.Formatos.Cuaderno43.saldo("2", {320_000, 2})
      320000
  """
  @spec saldo(String.t(), {integer(), 2}) :: integer()
  def saldo("1", {centimos, 2}), do: -centimos
  def saldo("2", {centimos, 2}), do: centimos

  # -------------------------------------------------------------- controles

  @doc """
  Verifica los controles propios del cuaderno sobre los registros leídos y
  devuelve los diagnósticos; una lista vacía es un extracto que cuadra.
  Recibe lo que devuelve `AnchoFijo.parsear/3` con `Formatos.cuaderno43/1`,
  en el orden del archivo, con cada registro como `{tipo, mapa}` y una
  `:__traza__` opcional que no se mira.
  """
  @spec validar([Multiregistro.registro()]) :: [Diagnostico.t()]
  def validar(registros) do
    numerados = Enum.with_index(registros, 1)
    cuentas = cuentas_numeradas(numerados)

    Enum.concat([
      estructura(numerados),
      Enum.flat_map(cuentas, &validar_cuenta/1),
      validar_fichero(numerados)
    ])
  end

  defp estructura(numerados) do
    numerados
    |> Enum.reduce({[], :fuera, false}, fn
      {{:cabecera_de_cuenta, _}, _n}, {diagnosticos, :fuera, _mov?} ->
        {diagnosticos, :en_cuenta, false}

      {{:cabecera_de_cuenta, _}, n}, {diagnosticos, :en_cuenta, _mov?} ->
        {[
           rota(
             n,
             "un final de cuenta antes de otra cabecera",
             "una cabecera con la anterior sin cerrar"
           )
           | diagnosticos
         ], :en_cuenta, false}

      {{:movimiento, _}, n}, {diagnosticos, :fuera, mov?} ->
        {[
           rota(
             n,
             "una cabecera de cuenta antes de los movimientos",
             "un movimiento fuera de una cuenta"
           )
           | diagnosticos
         ], :fuera, mov?}

      {{:movimiento, _}, _n}, {diagnosticos, :en_cuenta, _mov?} ->
        {diagnosticos, :en_cuenta, true}

      {{tipo, _}, n}, {diagnosticos, estado, false}
      when tipo in [:concepto_complementario, :equivalencia_de_importe] ->
        {[
           rota(
             n,
             "un movimiento antes de sus complementarios",
             "#{tipo_en_prosa(tipo)} sin movimiento"
           )
           | diagnosticos
         ], estado, false}

      {{:final_de_cuenta, _}, n}, {diagnosticos, :fuera, mov?} ->
        {[
           rota(n, "una cabecera de cuenta antes de su final", "un final de cuenta sin cabecera")
           | diagnosticos
         ], :fuera, mov?}

      {{:final_de_cuenta, _}, _n}, {diagnosticos, :en_cuenta, _mov?} ->
        {diagnosticos, :fuera, false}

      _otro, acumulado ->
        acumulado
    end)
    |> then(fn
      {diagnosticos, :en_cuenta, _mov?} ->
        [
          rota(
            nil,
            "un final de cuenta al final de la última cuenta",
            "el fin del archivo con una cuenta sin cerrar"
          )
          | diagnosticos
        ]

      {diagnosticos, :fuera, _mov?} ->
        diagnosticos
    end)
    |> Enum.reverse()
  end

  defp tipo_en_prosa(:concepto_complementario), do: "un concepto complementario"
  defp tipo_en_prosa(:equivalencia_de_importe), do: "una equivalencia de importe"

  defp rota(linea, esperado, recibido) do
    Diagnostico.nuevo(
      tipo: :estructura,
      linea: linea,
      esperado: esperado,
      recibido: recibido,
      causa_probable:
        "cada cuenta del cuaderno 43 va cabecera (11), movimientos (22) con sus complementarios " <>
          "(23, 24) y final (33), y el archivo termina con el 88"
    )
  end

  defp validar_cuenta(%{final: nil}), do: []

  defp validar_cuenta(%{cabecera: cabecera, movimientos: movimientos, final: final, linea: linea}) do
    detalles = Enum.map(movimientos, & &1.movimiento)
    {debe, haber} = Enum.split_with(detalles, &(&1.clave_debe_haber == "1"))
    total_debe = Enum.sum(Enum.map(debe, &centimos(&1.importe)))
    total_haber = Enum.sum(Enum.map(haber, &centimos(&1.importe)))

    saldo_final =
      saldo(cabecera.clave_debe_haber, cabecera.importe_saldo_inicial) + total_haber - total_debe

    Enum.concat([
      control(
        linea,
        :numero_de_apuntes_debe,
        length(debe),
        final.numero_de_apuntes_debe,
        "los movimientos con clave debe"
      ),
      control(
        linea,
        :total_importes_debe,
        {total_debe, 2},
        final.total_importes_debe,
        "la suma de los importes con clave debe"
      ),
      control(
        linea,
        :numero_de_apuntes_haber,
        length(haber),
        final.numero_de_apuntes_haber,
        "los movimientos con clave haber"
      ),
      control(
        linea,
        :total_importes_haber,
        {total_haber, 2},
        final.total_importes_haber,
        "la suma de los importes con clave haber"
      ),
      control(
        linea,
        :importe_saldo_final,
        saldo_final,
        saldo(final.codigo_saldo_final, final.importe_saldo_final),
        "el saldo inicial más el haber menos el debe, en céntimos con signo"
      ),
      control(
        linea,
        :clave_entidad,
        cabecera.clave_entidad,
        final.clave_entidad,
        "la cabecera de la cuenta"
      ),
      control(
        linea,
        :clave_oficina,
        cabecera.clave_oficina,
        final.clave_oficina,
        "la cabecera de la cuenta"
      ),
      control(
        linea,
        :numero_de_cuenta,
        cabecera.numero_de_cuenta,
        final.numero_de_cuenta,
        "la cabecera de la cuenta"
      )
    ])
  end

  defp centimos({centimos, 2}), do: centimos

  defp validar_fichero(numerados) do
    case Enum.find(numerados, &match?({{:fin_de_fichero, _}, _}, &1)) do
      {{:fin_de_fichero, fin}, linea} ->
        control(
          linea,
          :numero_de_registros,
          linea - 1,
          fin.numero_de_registros,
          "los registros anteriores al 88"
        )

      nil ->
        []
    end
  end

  defp control(_linea, _campo, calculado, calculado, _de_que), do: []

  defp control(linea, campo, calculado, declarado, de_que) do
    [
      Diagnostico.nuevo(
        tipo: :control,
        linea: linea,
        campo: campo,
        esperado: "#{inspect(calculado)}, que es #{de_que}",
        recibido: inspect(declarado),
        causa_probable:
          "el registro de control no cuadra con los movimientos: el archivo se cortó, se editó o se generó mal"
      )
    ]
  end
end
