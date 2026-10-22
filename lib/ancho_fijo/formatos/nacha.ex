defmodule AnchoFijo.Formatos.Nacha do
  @fuente "Nacha Operating Rules & Guidelines, Appendix Three (ACH Record Format " <>
            "Specifications), ediciones 2021 en adelante; posiciones verificadas contra la " <>
            "guía pública de Nacha en https://achdevguide.nacha.org/ach-file-details, " <>
            "consultada el 2026-10-16."

  @moduledoc """
  NACHA/ACH: el formato de transferencias de la red ACH de Estados Unidos.

  Registros de 94 caracteres, con seis tipos: encabezado de archivo (1),
  encabezado de lote (5), detalle de entrada (6), addenda (7), control de
  lote (8) y control de archivo (9), más las líneas de relleno de nueves que
  completan el último bloque de diez registros.

  ## Fuente

  #{@fuente}

  Los nombres de los campos son los de la especificación, en inglés y en
  `snake_case`, para que el layout se pueda verificar campo por campo
  contra el Apéndice Tres sin traducir: `immediate_destination` es
  "Immediate Destination", posiciones 4 a 13. Los nombres de los tipos de
  registro sí están en español, porque son los de esta librería.

  ## Qué valida la librería y qué valida este módulo

  `AnchoFijo.parsear/3` con `AnchoFijo.Formatos.nacha/1` lee cada registro
  con su layout, verifica el discriminador y que haya un encabezado y un
  control de archivo, y que los lotes tengan al menos un encabezado y un
  control. Lo que es propio de NACHA lo hace `validar/1` sobre los registros
  leídos:

    * en cada lote: la cuenta de entradas y addendas, el *entry hash* (la
      suma de los `receiving_dfi_identification`, con los diez dígitos de la
      derecha si se pasa), los totales de débitos y de créditos según el
      código de transacción, y que el *service class code* del control sea
      el del encabezado;
    * en el archivo: la cuenta de lotes, la de entradas y addendas, el hash
      (la suma de los hashes de los lotes, mismos diez dígitos), los totales,
      y la cuenta de bloques (registros sobre diez, hacia arriba, sin contar
      el relleno);
    * la estructura de los lotes: un control sin encabezado, un encabezado
      sin control, una entrada fuera de un lote.

  Cada desacuerdo es un `AnchoFijo.Diagnostico` de tipo `:control` o
  `:estructura`, con la línea del registro de control, el valor calculado,
  el declarado y de qué se calculó. `lotes/1` arma la estructura anidada:
  cada lote con su encabezado, sus entradas (cada una con sus addendas) y
  su control.

  ## Lo que no está

  Solo las entradas de las clases PPD y CCD (y las que comparten su layout,
  como WEB y TEL). Las entradas IAT, con sus siete addendas obligatorias,
  tienen otro layout y no están. Las fechas `YYMMDD` se leen como texto: el
  tipo `:fecha` lee ocho dígitos, y adivinar el siglo no es cosa del parser.
  Los montos vienen en centavos, `{unidades, 2}`.
  """

  alias AnchoFijo.Diagnostico
  alias AnchoFijo.Layout
  alias AnchoFijo.Multiregistro

  @doc "La fuente de la que se transcribió el formato."
  @spec fuente() :: String.t()
  def fuente, do: @fuente

  @largo 94
  @modulo_hash 10_000_000_000

  @doc """
  El multiregistro del formato. El discriminador son las dos primeras
  posiciones: el tipo de registro y el primer dígito del campo siguiente,
  que es lo que distingue el control de archivo (`90`) de las líneas de
  relleno (`99`).
  """
  @spec multiregistro() :: Multiregistro.t()
  def multiregistro do
    Multiregistro.nuevo!(
      nombre: "NACHA",
      discriminador: [posicion: 1, largo: 2],
      orden: :libre,
      registros: [
        encabezado_de_archivo: [valor: "10", cantidad: :uno, layout: encabezado_de_archivo()],
        encabezado_de_lote: [valor: "52", cantidad: :al_menos_uno, layout: encabezado_de_lote()],
        entrada: [valor: ["62", "63", "64", "65"], cantidad: :varios, layout: entrada()],
        addenda: [valor: ["70", "79"], cantidad: :varios, layout: addenda()],
        control_de_lote: [valor: "82", cantidad: :al_menos_uno, layout: control_de_lote()],
        control_de_archivo: [valor: "90", cantidad: :uno, layout: control_de_archivo()],
        relleno: [valor: "99", cantidad: :varios, layout: relleno()]
      ]
    )
  end

  @doc "File Header Record, tipo 1."
  @spec encabezado_de_archivo() :: Layout.t()
  def encabezado_de_archivo do
    Layout.nuevo!(
      nombre: "NACHA file header",
      largo: @largo,
      campos: [
        [nombre: :record_type_code, largo: 1],
        [nombre: :priority_code, largo: 2],
        [nombre: :immediate_destination, largo: 10],
        [nombre: :immediate_origin, largo: 10],
        [nombre: :file_creation_date, largo: 6],
        [nombre: :file_creation_time, largo: 4],
        [nombre: :file_id_modifier, largo: 1],
        [nombre: :record_size, largo: 3, tipo: :entero],
        [nombre: :blocking_factor, largo: 2, tipo: :entero],
        [nombre: :format_code, largo: 1],
        [nombre: :immediate_destination_name, largo: 23],
        [nombre: :immediate_origin_name, largo: 23],
        [nombre: :reference_code, largo: 8]
      ]
    )
  end

  @doc "Company/Batch Header Record, tipo 5."
  @spec encabezado_de_lote() :: Layout.t()
  def encabezado_de_lote do
    Layout.nuevo!(
      nombre: "NACHA batch header",
      largo: @largo,
      campos: [
        [nombre: :record_type_code, largo: 1],
        [nombre: :service_class_code, largo: 3, tipo: :entero],
        [nombre: :company_name, largo: 16],
        [nombre: :company_discretionary_data, largo: 20],
        [nombre: :company_identification, largo: 10],
        [nombre: :standard_entry_class_code, largo: 3],
        [nombre: :company_entry_description, largo: 10],
        [nombre: :company_descriptive_date, largo: 6],
        [nombre: :effective_entry_date, largo: 6],
        [nombre: :settlement_date, largo: 3],
        [nombre: :originator_status_code, largo: 1],
        [nombre: :originating_dfi_identification, largo: 8],
        [nombre: :batch_number, largo: 7, tipo: :entero]
      ]
    )
  end

  @doc "Entry Detail Record, tipo 6, clases PPD y CCD."
  @spec entrada() :: Layout.t()
  def entrada do
    Layout.nuevo!(
      nombre: "NACHA entry detail (PPD/CCD)",
      largo: @largo,
      campos: [
        [nombre: :record_type_code, largo: 1],
        [nombre: :transaction_code, largo: 2, tipo: :entero],
        [nombre: :receiving_dfi_identification, largo: 8, tipo: :entero],
        [nombre: :check_digit, largo: 1, tipo: :entero],
        [nombre: :dfi_account_number, largo: 17],
        [nombre: :amount, largo: 10, tipo: :decimal, precision: 2],
        [nombre: :individual_identification_number, largo: 15],
        [nombre: :individual_name, largo: 22],
        [nombre: :discretionary_data, largo: 2],
        [nombre: :addenda_record_indicator, largo: 1, tipo: :entero],
        [nombre: :trace_number, largo: 15]
      ]
    )
  end

  @doc "Addenda Record, tipo 7, clases PPD, CCD y WEB."
  @spec addenda() :: Layout.t()
  def addenda do
    Layout.nuevo!(
      nombre: "NACHA addenda",
      largo: @largo,
      campos: [
        [nombre: :record_type_code, largo: 1],
        [nombre: :addenda_type_code, largo: 2],
        [nombre: :payment_related_information, largo: 80],
        [nombre: :addenda_sequence_number, largo: 4, tipo: :entero],
        [nombre: :entry_detail_sequence_number, largo: 7, tipo: :entero]
      ]
    )
  end

  @doc "Company/Batch Control Record, tipo 8."
  @spec control_de_lote() :: Layout.t()
  def control_de_lote do
    Layout.nuevo!(
      nombre: "NACHA batch control",
      largo: @largo,
      campos: [
        [nombre: :record_type_code, largo: 1],
        [nombre: :service_class_code, largo: 3, tipo: :entero],
        [nombre: :entry_addenda_count, largo: 6, tipo: :entero],
        [nombre: :entry_hash, largo: 10, tipo: :entero],
        [nombre: :total_debit_entry_dollar_amount, largo: 12, tipo: :decimal, precision: 2],
        [nombre: :total_credit_entry_dollar_amount, largo: 12, tipo: :decimal, precision: 2],
        [nombre: :company_identification, largo: 10],
        [nombre: :message_authentication_code, largo: 19],
        [nombre: :reserved, largo: 6],
        [nombre: :originating_dfi_identification, largo: 8],
        [nombre: :batch_number, largo: 7, tipo: :entero]
      ]
    )
  end

  @doc "File Control Record, tipo 9."
  @spec control_de_archivo() :: Layout.t()
  def control_de_archivo do
    Layout.nuevo!(
      nombre: "NACHA file control",
      largo: @largo,
      campos: [
        [nombre: :record_type_code, largo: 1],
        [nombre: :batch_count, largo: 6, tipo: :entero],
        [nombre: :block_count, largo: 6, tipo: :entero],
        [nombre: :entry_addenda_count, largo: 8, tipo: :entero],
        [nombre: :entry_hash, largo: 10, tipo: :entero],
        [nombre: :total_debit_entry_dollar_amount, largo: 12, tipo: :decimal, precision: 2],
        [nombre: :total_credit_entry_dollar_amount, largo: 12, tipo: :decimal, precision: 2],
        [nombre: :reserved, largo: 39]
      ]
    )
  end

  @doc "Las líneas de nueves que completan el último bloque de diez registros."
  @spec relleno() :: Layout.t()
  def relleno do
    Layout.nuevo!(nombre: "NACHA filler", campos: [[nombre: :relleno, largo: @largo, trim: false]])
  end

  # ------------------------------------------------------------- estructura

  @type lote :: %{
          encabezado: map(),
          entradas: [%{entrada: map(), addendas: [map()]}],
          control: map() | nil
        }

  @doc """
  Arma los lotes a partir de la lista ordenada de registros: cada uno con su
  encabezado, sus entradas (cada una con sus addendas) y su control. Las
  entradas que aparezcan fuera de un lote y los controles sin encabezado se
  ignoran acá; `validar/1` los reporta.
  """
  @spec lotes([Multiregistro.registro()]) :: [lote()]
  def lotes(registros) do
    registros
    |> Enum.reduce({[], nil}, fn
      {:encabezado_de_lote, r}, {lotes, abierto} ->
        {cerrar(lotes, abierto), %{encabezado: r, entradas: [], control: nil}}

      {:entrada, r}, {lotes, %{} = lote} ->
        {lotes, %{lote | entradas: [%{entrada: r, addendas: []} | lote.entradas]}}

      {:addenda, r}, {lotes, %{entradas: [actual | resto]} = lote} ->
        {lotes, %{lote | entradas: [%{actual | addendas: [r | actual.addendas]} | resto]}}

      {:control_de_lote, r}, {lotes, %{} = lote} ->
        {cerrar(lotes, %{lote | control: r}), nil}

      _otro, acumulado ->
        acumulado
    end)
    |> then(fn {lotes, abierto} -> cerrar(lotes, abierto) end)
    |> Enum.reverse()
    |> Enum.map(fn lote ->
      entradas =
        lote.entradas
        |> Enum.reverse()
        |> Enum.map(&%{&1 | addendas: Enum.reverse(&1.addendas)})

      %{lote | entradas: entradas}
    end)
  end

  defp cerrar(lotes, nil), do: lotes
  defp cerrar(lotes, lote), do: [lote | lotes]

  # -------------------------------------------------------------- controles

  @doc """
  Verifica los controles propios de NACHA sobre los registros leídos y
  devuelve los diagnósticos; una lista vacía es un archivo que cuadra.

  Recibe lo que devuelve `AnchoFijo.parsear/3` con `Formatos.nacha/1`, en
  el orden del archivo, con cada registro como `{tipo, mapa}` y una
  `:__traza__` opcional que no se mira.
  """
  @spec validar([Multiregistro.registro()]) :: [Diagnostico.t()]
  def validar(registros) do
    numerados = Enum.with_index(registros, 1)
    lotes = lotes_numerados(numerados)

    Enum.concat([
      estructura(numerados),
      Enum.flat_map(lotes, &validar_lote/1),
      validar_archivo(numerados, lotes)
    ])
  end

  # Los lotes con el número de línea de su control, que es donde se reporta.
  defp lotes_numerados(numerados) do
    numerados
    |> Enum.reduce({[], nil}, fn
      {{:encabezado_de_lote, r}, n}, {lotes, abierto} ->
        {cerrar(lotes, abierto), %{encabezado: r, entradas: [], control: nil, linea: n}}

      {{:entrada, r}, _n}, {lotes, %{} = lote} ->
        {lotes, %{lote | entradas: [%{entrada: r, addendas: []} | lote.entradas]}}

      {{:addenda, r}, _n}, {lotes, %{entradas: [actual | resto]} = lote} ->
        {lotes, %{lote | entradas: [%{actual | addendas: [r | actual.addendas]} | resto]}}

      {{:control_de_lote, r}, n}, {lotes, %{} = lote} ->
        {cerrar(lotes, %{lote | control: r, linea: n}), nil}

      _otro, acumulado ->
        acumulado
    end)
    |> then(fn {lotes, abierto} -> cerrar(lotes, abierto) end)
    |> Enum.reverse()
  end

  defp estructura(numerados) do
    numerados
    |> Enum.reduce({[], false}, fn
      {{:encabezado_de_lote, _}, n}, {diagnosticos, true} ->
        {[
           estructura_rota(
             n,
             "un control de lote antes de otro encabezado",
             "un encabezado de lote con el anterior sin cerrar"
           )
           | diagnosticos
         ], true}

      {{:encabezado_de_lote, _}, _n}, {diagnosticos, false} ->
        {diagnosticos, true}

      {{tipo, _}, n}, {diagnosticos, false} when tipo in [:entrada, :addenda] ->
        {[
           estructura_rota(
             n,
             "un encabezado de lote antes de las entradas",
             "#{tipo_en_prosa(tipo)} fuera de un lote"
           )
           | diagnosticos
         ], false}

      {{:control_de_lote, _}, n}, {diagnosticos, false} ->
        {[
           estructura_rota(
             n,
             "un encabezado de lote antes de su control",
             "un control de lote sin encabezado"
           )
           | diagnosticos
         ], false}

      {{:control_de_lote, _}, _n}, {diagnosticos, true} ->
        {diagnosticos, false}

      _otro, acumulado ->
        acumulado
    end)
    |> then(fn
      {diagnosticos, true} ->
        [
          estructura_rota(
            nil,
            "un control de lote al final del último lote",
            "el fin del archivo con un lote sin cerrar"
          )
          | diagnosticos
        ]

      {diagnosticos, false} ->
        diagnosticos
    end)
    |> Enum.reverse()
  end

  defp tipo_en_prosa(:entrada), do: "una entrada"
  defp tipo_en_prosa(:addenda), do: "una addenda"

  defp estructura_rota(linea, esperado, recibido) do
    Diagnostico.nuevo(
      tipo: :estructura,
      linea: linea,
      esperado: esperado,
      recibido: recibido,
      causa_probable:
        "los lotes NACHA van encabezado (5), entradas (6) con sus addendas (7) y control (8)"
    )
  end

  defp validar_lote(%{control: nil}), do: []

  defp validar_lote(%{encabezado: encabezado, entradas: entradas, control: control, linea: linea}) do
    detalles = Enum.map(entradas, & &1.entrada)
    cuenta = length(detalles) + Enum.sum(Enum.map(entradas, &length(&1.addendas)))

    [
      control(
        linea,
        :entry_addenda_count,
        cuenta,
        control.entry_addenda_count,
        "las entradas más las addendas del lote"
      ),
      control(
        linea,
        :entry_hash,
        hash(detalles),
        control.entry_hash,
        "la suma de los receiving_dfi_identification del lote, diez dígitos de la derecha"
      ),
      control(
        linea,
        :total_debit_entry_dollar_amount,
        total(detalles, :debito),
        control.total_debit_entry_dollar_amount,
        "la suma de los montos con código de transacción de débito"
      ),
      control(
        linea,
        :total_credit_entry_dollar_amount,
        total(detalles, :credito),
        control.total_credit_entry_dollar_amount,
        "la suma de los montos con código de transacción de crédito"
      ),
      control(
        linea,
        :service_class_code,
        encabezado.service_class_code,
        control.service_class_code,
        "el service_class_code del encabezado del lote"
      )
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp validar_archivo(numerados, lotes) do
    case Enum.find(numerados, &match?({{:control_de_archivo, _}, _}, &1)) do
      nil ->
        []

      {{:control_de_archivo, control}, linea} ->
        cerrados = Enum.filter(lotes, &(&1.control != nil))
        detalles = Enum.flat_map(cerrados, fn lote -> Enum.map(lote.entradas, & &1.entrada) end)
        addendas = cerrados |> Enum.flat_map(& &1.entradas) |> Enum.flat_map(& &1.addendas)
        sin_relleno = Enum.count(numerados, fn {{tipo, _}, _} -> tipo != :relleno end)

        [
          control(
            linea,
            :batch_count,
            length(cerrados),
            control.batch_count,
            "la cantidad de lotes cerrados"
          ),
          control(
            linea,
            :block_count,
            div(sin_relleno + 9, 10),
            control.block_count,
            "los registros sin contar el relleno, sobre diez, hacia arriba"
          ),
          control(
            linea,
            :entry_addenda_count,
            length(detalles) + length(addendas),
            control.entry_addenda_count,
            "las entradas más las addendas de todos los lotes"
          ),
          control(
            linea,
            :entry_hash,
            rem(
              Enum.sum(Enum.map(cerrados, &hash(Enum.map(&1.entradas, fn e -> e.entrada end)))),
              @modulo_hash
            ),
            control.entry_hash,
            "la suma de los entry_hash de los lotes, diez dígitos de la derecha"
          ),
          control(
            linea,
            :total_debit_entry_dollar_amount,
            total(detalles, :debito),
            control.total_debit_entry_dollar_amount,
            "la suma de los débitos de todos los lotes"
          ),
          control(
            linea,
            :total_credit_entry_dollar_amount,
            total(detalles, :credito),
            control.total_credit_entry_dollar_amount,
            "la suma de los créditos de todos los lotes"
          )
        ]
        |> Enum.reject(&is_nil/1)
    end
  end

  # El entry hash es la suma de los routing numbers (sin dígito verificador)
  # de las entradas del lote; si se pasa de diez dígitos, se quedan los de
  # la derecha. Es la regla del Apéndice Tres, y la razón de que el campo
  # sea de diez posiciones.
  defp hash(detalles) do
    detalles |> Enum.map(& &1.receiving_dfi_identification) |> Enum.sum() |> rem(@modulo_hash)
  end

  # Los códigos de transacción terminados en 1 a 4 son créditos (22, 32,
  # 23...); los terminados en 5 a 9, débitos (27, 37, 28...). Los montos son
  # {centavos, 2}; la suma también.
  defp total(detalles, sentido) do
    detalles
    |> Enum.filter(&(sentido(&1.transaction_code) == sentido))
    |> Enum.map(fn %{amount: {centavos, 2}} -> centavos end)
    |> Enum.sum()
    |> then(&{&1, 2})
  end

  defp sentido(codigo) when rem(codigo, 10) in 1..4, do: :credito
  defp sentido(_codigo), do: :debito

  defp control(_linea, _campo, calculado, calculado, _de_que), do: nil

  defp control(linea, campo, calculado, declarado, de_que) do
    Diagnostico.nuevo(
      tipo: :control,
      linea: linea,
      campo: campo,
      esperado: "#{inspect(calculado)} en #{inspect(campo)}, #{de_que}",
      recibido: inspect(declarado),
      causa_probable: "el registro de control no cuadra con los registros que resume"
    )
  end
end
