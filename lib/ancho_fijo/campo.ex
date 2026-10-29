defmodule AnchoFijo.Campo do
  @moduledoc """
  Definición de un campo del layout: dónde está, cuánto mide y cómo se lee.

  Un campo es data. Se define con una keyword list y se valida al construirlo,
  antes de tocar un solo archivo.

      iex> alias AnchoFijo.Campo
      iex> campo = Campo.nuevo!(nombre: :monto, posicion: 11, largo: 12, tipo: :decimal, precision: 2)
      iex> Campo.rango(campo)
      {11, 22}

  ## Opciones

    * `:nombre` — átomo, obligatorio. Es la clave del registro parseado.
    * `:largo` — entero positivo, obligatorio.
    * `:posicion` — entero positivo, 1-based. Si se omite, `AnchoFijo.Layout`
      la calcula encadenando el campo anterior.
    * `:tipo` — `:texto` (default), `:entero`, `:decimal`, `:fecha`,
      `:hora`, `:fecha_hora`, `:rut`, `:constante`, `:relleno`, o un módulo
      que implemente `AnchoFijo.Tipo` para un tipo propio. Las opciones
      propias de ese tipo quedan en `:opciones`.
    * `:opcional` — si es `true`, un campo en blanco (o en ceros, para fechas)
      se lee como `nil` en vez de producir un diagnóstico. Default `false`.
    * `:trim` — `:ambos` (default), `:izquierda`, `:derecha` o `false`. Solo
      aplica a `:texto`; los tipos numéricos y de fecha siempre recortan
      espacios porque el relleno no es parte del dato.
    * `:relleno` — carácter de relleno a recortar en `:texto`. Default `" "`.
    * `:encoding` — `:utf8` o `:latin1` para este campo, por encima del
      `:encoding` del layout. Para los archivos que mezclan: offsets en bytes
      y latin-1 en todo, salvo el campo de texto libre que viene en UTF-8.
      Solo con `unidad: :bytes`; con `:caracteres` la línea se decodifica
      entera antes de cortar los campos.
    * `:reparar_doble_codificacion` — en `:texto`: si es `true`, un valor con
      doble codificación (`operaciÃ³n`) se lee reparado (`operación`), con
      una advertencia `:doble_codificacion`. Default `false`: se lee como
      viene y la advertencia trae el texto reparado como sugerencia.
    * `:precision` — obligatorio en `:decimal`. Cantidad de decimales que el
      formato declara.
    * `:separador` — en `:decimal`: `:implicito` (default), `:punto` o `:coma`.
    * `:moneda` — en `:decimal`: código ISO 4217 como átomo (`:clp`, `:usd`).
      El valor pasa a ser un `AnchoFijo.Monto` y la `:precision` se toma de
      la escala de la moneda; declararla distinta es un layout inválido.
    * `:como` — en `:decimal`: `:decimal` para leer un `%Decimal{}` en vez de
      la tupla (o del `Monto`); requiere la librería `Decimal`. Ver
      `AnchoFijo.Tipo.Decimal`. El layout lo fija para todos con
      `decimales_como: :decimal`.
    * `:signo` — en `:entero` y `:decimal`: `:inicial` (default) o `:final`.
      Con `:final` el signo va después de los dígitos, `0125000-`, como en los
      formatos heredados de mainframe.
    * `:formato` — obligatorio en `:fecha`, `:hora` y `:fecha_hora`: un
      nombre (`:aaaammdd`, `:ddmmaa`, `:hhmmss`, `:aaaammddhhmmss`...) o un
      patrón (`"DD/MM/AAAA"`). Ver `AnchoFijo.Tipo.Fecha`.
    * `:pivote` — en `:fecha` y `:fecha_hora` con año de dos dígitos: el
      primer año de la ventana de cien. Default `2000`.
    * `:valor` — obligatorio en `:constante`: el literal que el formato fija
      en esas posiciones. Ver `AnchoFijo.Tipo.Constante`.
    * `:campos` y `:repetir` — en `:grupo`: los campos internos y cuántas
      veces se repiten. El `:largo` se calcula. Ver `AnchoFijo.Tipo.Grupo`.
    * `:segun` y `:variantes` — en `:variante`: el campo anterior que elige
      la variante y el mapa de valor a campos internos. Ver
      `AnchoFijo.Tipo.Variante`.
    * `:dv` — en `:rut`: `:validar` (default), `:no_validar` o `:ausente`. Ver
      `AnchoFijo.Rut`.
    * `:en`, `:rango`, `:patron`, `:requerido_si`, `:prohibido_si` — reglas
      del dominio, verificadas al leer y al escribir: `en: ["01", "02"]`
      (o una función `valor -> boolean`), `rango: {min, max}` (con `nil` en
      el extremo abierto) en `:entero`, `:decimal`, `:fecha`, `:hora` y
      `:fecha_hora`, `patron: ~r/.../` en `:texto` sobre el valor ya
      recortado, y `requerido_si: [campo: :tipo, en: ["02"]]` o
      `prohibido_si: [campo: :otro]` (sin `en:`, la condición es que el otro
      campo tenga valor). Las reglas miran el valor canónico del campo, el
      que `leer/3` devuelve: al escribir, un `%Decimal{}`, un entero o un
      string en un `:decimal` se llevan a la tupla, el `Monto` o el
      `Decimal` del campo, y un `:texto` se recorta. Los valores de `en:` y
      los extremos de `rango:` tienen que ser del tipo del campo (entre las
      formas numéricas de un `:decimal`, `{100, 2}` y `Decimal.new("1.00")`
      son el mismo valor); el layout lo verifica. Cada falla es un
      diagnóstico `:regla`; en modo tolerante el registro se entrega igual y
      el diagnóstico se acumula, en estricto la línea se rechaza.
    * `:generador` — un generador de `StreamData` propio para
      `AnchoFijo.Test.Generadores`, para los campos con reglas que no se
      pueden deducir (un `:patron`, un `:en` con función).
    * `:descripcion` y `:ejemplo` — texto libre para la especificación que
      genera `AnchoFijo.Documentacion` (y `mix ancho_fijo.documentar`). El
      parser los ignora.
    * `:sensible` — si es `true`, los diagnósticos del campo muestran la forma
      del valor y no el valor en `AnchoFijo.Diagnostico.mensaje/1` y en
      `inspect/1`. Default `false`, salvo en `:rut`, donde es `true`: un RUT
      es siempre un dato personal.

  ## Tipos y valores devueltos

  | tipo | valor |
  | --- | --- |
  | `:texto` | `String.t()` ya transcodificado a UTF-8 |
  | `:entero` | `integer()` |
  | `:decimal` | `{unidades, precision}`, p. ej. `{123456, 2}` para `1234.56`; con `:moneda`, un `AnchoFijo.Monto`; con `como: :decimal`, un `%Decimal{}` |
  | `:fecha` | `Date.t()` |
  | `:hora` | `Time.t()` |
  | `:fecha_hora` | `NaiveDateTime.t()` |
  | `:rut` | `String.t()` canónico, `"12345678-5"`; solo el cuerpo, `"12345678"`, con `dv: :ausente` |
  | `:constante` | el literal declarado en `:valor`, verificado contra la línea |
  | `:relleno` | no aparece en el registro; al escribir se emite el carácter de `:relleno` |
  | `:grupo` | una lista de `repetir` mapas con los campos internos |
  | `:variante` | el mapa de la variante que eligió el campo `segun` |

  Un `:decimal` nunca se convierte a float. Se devuelve como par
  `{unidades_minimas, precision}` —centavos y escala— porque un monto que pasa
  por punto flotante deja de cuadrar con la contabilidad del banco, y una
  librería de lectura no debería obligar a depender de `Decimal` para evitarlo.
  """

  @compile {:no_warn_undefined, Decimal}

  alias AnchoFijo.Diagnostico
  alias AnchoFijo.Monto
  alias AnchoFijo.Opciones
  alias AnchoFijo.Reglas
  alias AnchoFijo.Rut
  alias AnchoFijo.Tipo
  alias AnchoFijo.Transcodificacion

  @comunes [
    :nombre,
    :posicion,
    :largo,
    :tipo,
    :opcional,
    :trim,
    :relleno,
    :sensible,
    :encoding,
    :descripcion,
    :ejemplo,
    :en,
    :rango,
    :patron,
    :requerido_si,
    :prohibido_si,
    :generador
  ]
  @de_tipos_internos [
    reparar_doble_codificacion: false,
    precision: nil,
    separador: :implicito,
    moneda: nil,
    como: nil,
    signo: :inicial,
    formato: nil,
    pivote: nil,
    dv: :validar,
    valor: nil,
    campos: nil,
    repetir: nil,
    segun: nil,
    variantes: nil
  ]
  @trims [:ambos, :izquierda, :derecha, false, true]

  @typedoc "Un átomo de los tipos internos o un módulo que implementa `AnchoFijo.Tipo`."
  @type tipo ::
          :texto
          | :entero
          | :decimal
          | :fecha
          | :hora
          | :fecha_hora
          | :rut
          | :constante
          | :relleno
          | :grupo
          | :variante
          | module()
  @type valor ::
          String.t()
          | integer()
          | {integer(), non_neg_integer()}
          | struct()
          | Date.t()
          | Time.t()
          | NaiveDateTime.t()
          | nil

  @type t :: %__MODULE__{
          nombre: atom(),
          posicion: pos_integer() | nil,
          largo: pos_integer(),
          tipo: tipo(),
          opcional: boolean(),
          trim: :ambos | :izquierda | :derecha | false,
          relleno: String.t(),
          encoding: :utf8 | :latin1 | nil,
          descripcion: String.t() | nil,
          ejemplo: String.t() | nil,
          reglas: Reglas.t(),
          generador: term(),
          reparar_doble_codificacion: boolean(),
          precision: non_neg_integer() | nil,
          separador: :implicito | :punto | :coma,
          moneda: Monto.moneda() | nil,
          como: atom() | nil,
          signo: :inicial | :final,
          formato: atom() | String.t() | nil,
          pivote: pos_integer() | nil,
          dv: Rut.dv(),
          valor: String.t() | nil,
          campos: [t()] | nil,
          repetir: pos_integer() | nil,
          segun: atom() | nil,
          variantes: %{term() => [t()]} | nil,
          sensible: boolean(),
          modulo: module() | nil,
          opciones: map()
        }

  defstruct nombre: nil,
            posicion: nil,
            largo: nil,
            tipo: :texto,
            opcional: false,
            trim: :ambos,
            relleno: " ",
            encoding: nil,
            descripcion: nil,
            ejemplo: nil,
            reglas: %Reglas{},
            generador: nil,
            reparar_doble_codificacion: false,
            precision: nil,
            separador: :implicito,
            moneda: nil,
            como: nil,
            signo: :inicial,
            formato: nil,
            pivote: nil,
            dv: :validar,
            valor: nil,
            campos: nil,
            repetir: nil,
            segun: nil,
            variantes: nil,
            sensible: false,
            modulo: nil,
            opciones: %{}

  @typedoc """
  Contexto de lectura que aporta el layout: cómo medir, cómo decodificar y en
  qué línea vamos, para que el diagnóstico sepa ubicarse.
  """
  @type contexto :: %{
          optional(:unidad) => :bytes | :caracteres,
          optional(:encoding) => :utf8 | :latin1,
          optional(:linea) => pos_integer() | nil,
          optional(:truncar) => boolean()
        }

  @doc """
  Valida y construye un campo.

  Devuelve `{:ok, campo}` o `{:error, diagnosticos}` con un diagnóstico por
  problema encontrado en la definición.

      iex> AnchoFijo.Campo.nuevo(nombre: :rut, largo: 10)
      {:ok, %AnchoFijo.Campo{nombre: :rut, largo: 10, tipo: :texto, modulo: AnchoFijo.Tipo.Texto}}

      iex> {:error, [diagnostico]} = AnchoFijo.Campo.nuevo(nombre: :monto, largo: 12, tipo: :decimal)
      iex> AnchoFijo.Diagnostico.mensaje(diagnostico)
      "layout, campo :monto: se esperaba :precision declarada para un campo :decimal; sin precisión no se sabe si 1234 son 12,34 o 1234,00"
  """
  @spec nuevo(term()) :: {:ok, t()} | {:error, [Diagnostico.t()]}
  def nuevo(atributos) do
    case Opciones.a_mapa(atributos) do
      {:ok, atributos} ->
        construir(atributos)

      :error ->
        {:error,
         [
           falla(
             nil,
             "la definición del campo como keyword list o mapa",
             atributos,
             "el elemento de :campos no es una definición de campo"
           )
         ]}
    end
  end

  defp construir(atributos) do
    campo = struct(%__MODULE__{}, normalizar(atributos))
    campo = %{campo | reglas: Reglas.desde_atributos(campo_reglas(atributos))}

    case Tipo.resolver(campo.tipo) do
      {:ok, modulo} ->
        campo =
          %{campo | modulo: modulo, opciones: opciones_propias(modulo, atributos)}
          |> sensible_por_tipo(atributos)
          |> precision_por_moneda()

        with {:ok, campo} <- construir_anidados(campo),
             [] <- validar(campo, atributos) do
          {:ok, campo}
        else
          {:error, diagnosticos} -> {:error, diagnosticos}
          diagnosticos when is_list(diagnosticos) -> {:error, diagnosticos}
        end

      {:error, esperado} ->
        {:error, validar_sin_tipo(campo) ++ [falla(campo.nombre, esperado, campo.tipo, nil)]}
    end
  end

  # Un grupo o una variante construye sus campos internos como un layout
  # chico: posiciones encadenadas desde 1, sin solapamientos ni nombres
  # repetidos. El largo del campo sale de ahí: el de una repetición por
  # `repetir`, o el de la variante más ancha (o el declarado, si es mayor).
  defp construir_anidados(%__MODULE__{modulo: Tipo.Grupo} = campo) do
    with {:ok, campos} <- construir_internos(campo.campos, ruta_de(campo.nombre)),
         repetir = campo.repetir || 1,
         {:ok, largo} <- largo_anidado(campo, AnchoFijo.Anidados.ancho_de(campos) * repetir, :igual) do
      {:ok, %__MODULE__{campo | campos: campos, repetir: repetir, largo: largo}}
    end
  end

  defp construir_anidados(%__MODULE__{modulo: Tipo.Variante, variantes: variantes} = campo)
       when is_map(variantes) and map_size(variantes) > 0 do
    construidas =
      Enum.reduce_while(variantes, {:ok, %{}}, fn {valor, definiciones}, {:ok, acumulado} ->
        case construir_internos(definiciones, "#{ruta_de(campo.nombre)}{#{inspect(valor)}}") do
          {:ok, campos} -> {:cont, {:ok, Map.put(acumulado, valor, campos)}}
          {:error, diagnosticos} -> {:halt, {:error, diagnosticos}}
        end
      end)

    with {:ok, variantes} <- construidas,
         maximo =
           variantes |> Map.values() |> Enum.map(&AnchoFijo.Anidados.ancho_de/1) |> Enum.max(),
         {:ok, largo} <- largo_anidado(campo, maximo, :al_menos) do
      {:ok, %__MODULE__{campo | variantes: variantes, largo: largo}}
    end
  end

  defp construir_anidados(campo), do: {:ok, campo}

  defp construir_internos(definiciones, ruta) when is_list(definiciones) and definiciones != [] do
    {campos, diagnosticos} =
      Enum.reduce(definiciones, {[], []}, fn definicion, {campos, diagnosticos} ->
        case nuevo(definicion) do
          {:ok, campo} -> {[campo | campos], diagnosticos}
          {:error, nuevos} -> {campos, diagnosticos ++ Enum.map(nuevos, &con_ruta(&1, ruta))}
        end
      end)

    campos = campos |> Enum.reverse() |> posicionar_internos()

    case diagnosticos ++ solapados(campos, ruta) ++ repetidos(campos, ruta) do
      [] -> {:ok, campos}
      diagnosticos -> {:error, diagnosticos}
    end
  end

  defp construir_internos(_otro, _ruta), do: {:ok, []}

  # La ruta de un campo anidado en sus diagnósticos. Un nombre que no es
  # átomo todavía no se reclamó (eso lo hace validar_nombre/1 después), y
  # no puede romper la construcción.
  defp ruta_de(nombre) when is_atom(nombre), do: nombre
  defp ruta_de(otro), do: inspect(otro)

  defp posicionar_internos(campos) do
    campos
    |> Enum.map_reduce(1, fn %__MODULE__{} = campo, siguiente ->
      campo = %__MODULE__{campo | posicion: campo.posicion || siguiente}
      {campo, fin(campo) + 1}
    end)
    |> elem(0)
    |> Enum.sort_by(& &1.posicion)
  end

  defp solapados(campos, ruta) do
    campos
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.flat_map(fn [anterior, actual] ->
      if actual.posicion <= fin(anterior),
        do: [
          falla(
            "#{ruta}.#{ruta_de(actual.nombre)}",
            "que empezara en la posición #{fin(anterior) + 1} o después",
            actual.posicion,
            "se solapa con el campo #{inspect(anterior.nombre)} del mismo grupo"
          )
        ],
        else: []
    end)
  end

  defp repetidos(campos, ruta) do
    campos
    |> Enum.frequencies_by(& &1.nombre)
    |> Enum.filter(fn {_nombre, veces} -> veces > 1 end)
    |> Enum.map(fn {nombre, veces} ->
      falla(ruta, "nombres únicos dentro del grupo", "#{inspect(nombre)} #{veces} veces", nil)
    end)
  end

  defp largo_anidado(%__MODULE__{largo: nil}, calculado, _modo), do: {:ok, calculado}

  defp largo_anidado(%__MODULE__{largo: largo}, calculado, :igual) when largo == calculado,
    do: {:ok, largo}

  defp largo_anidado(%__MODULE__{largo: largo}, calculado, :al_menos)
       when is_integer(largo) and largo >= calculado,
       do: {:ok, largo}

  defp largo_anidado(%__MODULE__{} = campo, calculado, modo) do
    {:error,
     [
       falla(
         campo.nombre,
         if(modo == :igual,
           do: "un :largo de #{calculado}, el de una repetición por :repetir, o ninguno",
           else: "un :largo de al menos #{calculado}, la variante más ancha, o ninguno"
         ),
         campo.largo,
         "el largo de un campo anidado sale de sus campos internos"
       )
     ]}
  end

  defp con_ruta(%Diagnostico{campo: nombre} = d, ruta),
    do: %Diagnostico{d | campo: "#{ruta}.#{nombre}"}

  # Con moneda y sin precisión, la precisión es la escala de la moneda. Con
  # las dos, `AnchoFijo.Tipo.Decimal` revisa que coincidan.
  defp precision_por_moneda(
         %__MODULE__{modulo: Tipo.Decimal, moneda: moneda, precision: nil} = campo
       )
       when not is_nil(moneda) do
    case Monto.escala(moneda) do
      {:ok, escala} -> %__MODULE__{campo | precision: escala}
      :error -> campo
    end
  end

  defp precision_por_moneda(campo), do: campo

  # Las opciones propias de un tipo externo viven en `:opciones`; las de los
  # tipos internos son campos del struct y no se duplican acá.
  defp opciones_propias(modulo, atributos) do
    propias = modulo.opciones() -- Keyword.keys(@de_tipos_internos)
    Map.take(atributos, propias)
  end

  @doc false
  # Las claves que una definición de campo puede traer, para la serialización.
  @spec claves() :: [atom()]
  def claves, do: @comunes ++ Keyword.keys(@de_tipos_internos)

  @doc """
  Igual que `nuevo/1` pero levanta `AnchoFijo.Error` si la definición es inválida.

      iex> AnchoFijo.Campo.nuevo!(nombre: :fecha, largo: 8, tipo: :fecha, formato: :ddmmaaaa).formato
      :ddmmaaaa
  """
  @spec nuevo!(term()) :: t()
  def nuevo!(atributos) do
    case nuevo(atributos) do
      {:ok, campo} -> campo
      {:error, diagnosticos} -> raise AnchoFijo.Error, diagnosticos
    end
  end

  @doc """
  Si el campo es de tipo `:texto`, el único cuyo relleno se puede reponer y
  cuyo recorte se configura con `:trim`.

      iex> AnchoFijo.Campo.texto?(AnchoFijo.Campo.nuevo!(nombre: :a, largo: 2))
      true
      iex> AnchoFijo.Campo.texto?(AnchoFijo.Campo.nuevo!(nombre: :a, largo: 2, tipo: :entero))
      false
  """
  @spec texto?(t()) :: boolean()
  def texto?(%__MODULE__{modulo: modulo}), do: modulo == Tipo.Texto

  @doc """
  Si el campo es de tipo `:relleno`: no se lee, no aparece en el registro y
  su relleno se puede reponer al final de la línea como el de un `:texto`.

      iex> AnchoFijo.Campo.relleno?(AnchoFijo.Campo.nuevo!(nombre: :f, largo: 5, tipo: :relleno))
      true
  """
  @spec relleno?(t()) :: boolean()
  def relleno?(%__MODULE__{modulo: modulo}), do: modulo == Tipo.Relleno

  @doc """
  Si el campo es un `:grupo` o una `:variante`: se lee y se escribe campo
  por campo, con el módulo interno de campos anidados.

      iex> AnchoFijo.Campo.anidado?(AnchoFijo.Campo.nuevo!(nombre: :t, tipo: :grupo, repetir: 2, campos: [[nombre: :a, largo: 1]]))
      true
  """
  @spec anidado?(t()) :: boolean()
  def anidado?(%__MODULE__{tipo: tipo}), do: tipo in [:grupo, :variante]

  @doc """
  Si el campo es de tipo `:constante`: un literal del formato.

      iex> AnchoFijo.Campo.constante?(AnchoFijo.Campo.nuevo!(nombre: :t, largo: 1, tipo: :constante, valor: "H"))
      true
  """
  @spec constante?(t()) :: boolean()
  def constante?(%__MODULE__{modulo: modulo}), do: modulo == Tipo.Constante

  @doc """
  Rango de posiciones que ocupa el campo, 1-based e inclusivo en ambos extremos.

      iex> AnchoFijo.Campo.rango(%AnchoFijo.Campo{nombre: :a, posicion: 1, largo: 10})
      {1, 10}
  """
  @spec rango(t()) :: {pos_integer(), pos_integer()}
  def rango(%__MODULE__{posicion: posicion} = campo), do: {posicion, fin(campo)}

  @doc """
  Última posición que ocupa el campo.

      iex> AnchoFijo.Campo.fin(%AnchoFijo.Campo{nombre: :a, posicion: 11, largo: 5})
      15
  """
  @spec fin(t()) :: pos_integer()
  def fin(%__MODULE__{posicion: posicion, largo: largo})
      when is_integer(posicion) and posicion > 0 and is_integer(largo) and largo > 0 do
    posicion + largo - 1
  end

  @doc false
  # El código ISO de la moneda, para la documentación.
  @spec nombre_moneda(Monto.moneda()) :: String.t()
  def nombre_moneda(moneda), do: Monto.codigo(moneda)

  @doc """
  Nombre de la unidad de medida, para redactar diagnósticos.

      iex> AnchoFijo.Campo.nombre_unidad(:bytes)
      "bytes"
  """
  @spec nombre_unidad(:bytes | :caracteres) :: String.t()
  def nombre_unidad(:caracteres), do: "caracteres"
  def nombre_unidad(_bytes), do: "bytes"

  @doc """
  Extrae y convierte el valor del campo desde una línea completa.

      iex> alias AnchoFijo.Campo
      iex> campo = Campo.nuevo!(nombre: :monto, posicion: 1, largo: 8, tipo: :decimal, precision: 2)
      iex> Campo.extraer(campo, "00123456")
      {:ok, {123456, 2}}

      iex> alias AnchoFijo.Campo
      iex> campo = Campo.nuevo!(nombre: :nombre, posicion: 1, largo: 6)
      iex> Campo.extraer(campo, <<74, 79, 83, 201, 32, 32>>, encoding: :latin1)
      {:ok, "JOSÉ"}

      iex> alias AnchoFijo.Campo
      iex> campo = Campo.nuevo!(nombre: :saldo, posicion: 1, largo: 8, tipo: :decimal, precision: 2, signo: :final)
      iex> Campo.extraer(campo, "0125000-")
      {:ok, {-125000, 2}}

      iex> alias AnchoFijo.Campo
      iex> campo = Campo.nuevo!(nombre: :fecha, posicion: 1, largo: 8, tipo: :fecha, formato: :aaaammdd)
      iex> {:error, diagnostico} = Campo.extraer(campo, "20240230", linea: 4)
      iex> AnchoFijo.Diagnostico.mensaje(diagnostico)
      "línea 4, campo :fecha (posiciones 1-8): se esperaban una fecha válida en formato AAAAMMDD, llegaron \\"20240230\\"; el día no existe en ese mes"
  """
  @spec extraer(t(), binary(), contexto() | keyword()) :: {:ok, valor()} | {:error, Diagnostico.t()}
  def extraer(%__MODULE__{} = campo, linea, contexto \\ %{}) do
    case leer(campo, linea, contexto) do
      {:ok, valor, _advertencias} -> {:ok, valor}
      {:error, diagnostico} -> {:error, diagnostico}
    end
  end

  @doc """
  Como `extraer/3`, pero con los diagnósticos que no impiden leer el
  valor: las advertencias (la doble codificación de un `:texto`) y las
  reglas del campo que no se cumplen (`en:`, `rango:`, `patron:`), que son
  errores de tipo `:regla` con el valor ya leído.

      iex> campo = AnchoFijo.Campo.nuevo!(nombre: :glosa, posicion: 1, largo: 12)
      iex> {:ok, "operaciÃ³n", [advertencia]} = AnchoFijo.Campo.leer(campo, "operaciÃ³n ")
      iex> advertencia.tipo
      :doble_codificacion
      iex> advertencia.esperado
      "operación"
  """
  @spec leer(t(), binary(), contexto() | keyword()) ::
          {:ok, valor(), [Diagnostico.t()]} | {:error, Diagnostico.t()}
  def leer(%__MODULE__{} = campo, linea, contexto \\ %{}) do
    contexto = contexto |> Map.new() |> con_encoding_del_campo(campo)
    unidad = Map.get(contexto, :unidad, :bytes)

    with {:ok, crudo} <- campo |> rebanar(linea, unidad, contexto) |> sensibilizar(campo, nil),
         {:ok, texto} <- campo |> decodificar(crudo, unidad, contexto) |> sensibilizar(campo, nil) do
      {texto, advertencias} = texto |> limpiar(campo) |> revisar_doble_codificacion(campo, contexto)

      case campo |> convertir(texto, contexto) |> sensibilizar(campo, texto) do
        {:ok, valor} -> {:ok, valor, advertencias ++ Reglas.del_valor(campo, valor, contexto)}
        {:error, diagnostico} -> {:error, diagnostico}
      end
    end
  end

  # El encoding del campo manda sobre el del layout, al leer y al escribir.
  defp con_encoding_del_campo(contexto, %__MODULE__{encoding: nil}), do: contexto

  defp con_encoding_del_campo(contexto, %__MODULE__{encoding: encoding}),
    do: Map.put(contexto, :encoding, encoding)

  # Solo un :texto puede traer doble codificación que valga la pena señalar:
  # en un número o una fecha el byte raro ya es un diagnóstico del tipo.
  defp revisar_doble_codificacion(texto, %__MODULE__{modulo: Tipo.Texto} = campo, contexto) do
    case Transcodificacion.doble_codificacion(texto) do
      {:ok, reparado} ->
        if campo.reparar_doble_codificacion,
          do: {reparado, [doble_codificacion(campo, texto, reparado, true, contexto)]},
          else: {texto, [doble_codificacion(campo, texto, reparado, false, contexto)]}

      :no ->
        {texto, []}
    end
  end

  defp revisar_doble_codificacion(texto, _campo, _contexto), do: {texto, []}

  defp doble_codificacion(%__MODULE__{} = campo, texto, reparado, reparado?, contexto) do
    # En un campo sensible el texto reparado también es el dato: queda en
    # :contenido, que la redacción oculta, y :esperado lo describe.
    diagnostico =
      diagnostico(campo, contexto,
        tipo: :doble_codificacion,
        gravedad: :advertencia,
        esperado:
          if(campo.sensible, do: "el texto UTF-8 decodificado una sola vez", else: reparado),
        recibido: inspect(texto),
        contenido: reparado,
        causa_probable:
          if(reparado?,
            do:
              "el campo traía UTF-8 decodificado como latin-1 y vuelto a codificar; " <>
                "se reparó porque el campo declara reparar_doble_codificacion: true",
            else:
              "el campo trae UTF-8 decodificado como latin-1 y vuelto a codificar; " <>
                "si el archivo mezcla encodings, declare encoding: :utf8 en este campo; " <>
                "si el emisor ya lo mandó así, reparar_doble_codificacion: true"
          )
      )

    if campo.sensible, do: Diagnostico.marcar_sensible(diagnostico, texto), else: diagnostico
  end

  # Cada diagnóstico de un campo sensible sale marcado, con la forma del valor
  # cuando el diagnóstico es sobre el valor. Una línea corta o un byte inválido
  # no traen el dato en `:recibido`; ahí solo se oculta `:contenido`.
  defp sensibilizar({:error, diagnostico}, %__MODULE__{sensible: true}, valor) do
    {:error, Diagnostico.marcar_sensible(diagnostico, valor)}
  end

  defp sensibilizar(resultado, _campo, _valor), do: resultado

  # Un RUT es un dato personal siempre; el default se decide por tipo y se
  # puede apagar a propósito con `sensible: false`.
  defp sensible_por_tipo(%__MODULE__{modulo: Tipo.Rut} = campo, atributos) do
    if Map.has_key?(atributos, :sensible), do: campo, else: %__MODULE__{campo | sensible: true}
  end

  defp sensible_por_tipo(campo, _atributos), do: campo

  # Un campo en blanco con `opcional: true` es `nil` para todos los tipos; sin
  # `:opcional`, el texto vacío llega al tipo y él decide.
  defp convertir(%__MODULE__{opcional: true}, "", _contexto), do: {:ok, nil}

  defp convertir(%__MODULE__{modulo: modulo} = campo, texto, contexto),
    do: modulo.leer(texto, campo, contexto)

  # Las reglas van juntas en `:reglas` (ver `AnchoFijo.Reglas`); aquí solo
  # se separan de los demás atributos.
  defp campo_reglas(%{reglas: %Reglas{} = reglas} = atributos),
    do: reglas |> Map.from_struct() |> Map.merge(Map.take(atributos, Reglas.claves()))

  defp campo_reglas(atributos), do: Map.take(atributos, Reglas.claves())

  defp normalizar(atributos) do
    atributos
    |> Map.update(:moneda, nil, fn moneda -> if is_atom(moneda), do: moneda, else: nil end)
    |> Map.take(@comunes ++ Keyword.keys(@de_tipos_internos))
    |> Map.update(:trim, :ambos, fn
      true -> :ambos
      otro -> otro
    end)
  end

  defp validar(%__MODULE__{modulo: modulo} = campo, atributos) do
    Enum.concat([
      validar_sin_tipo(campo),
      modulo.validar(campo),
      validar_moneda_cruda(campo, atributos),
      validar_opciones_ajenas(campo, atributos)
    ])
  end

  # La moneda se valida sobre lo que llegó, no sobre el struct: `normalizar/1`
  # no deja entrar al struct nada que no sea un átomo, para que el campo
  # tenga siempre el tipo que declara.
  defp validar_moneda_cruda(%__MODULE__{nombre: nombre}, atributos) do
    case Map.get(atributos, :moneda) do
      moneda when is_atom(moneda) -> []
      otro -> [falla(nombre, "una :moneda como átomo ISO 4217, por ejemplo :clp o :usd", otro, nil)]
    end
  end

  # Lo que se valida aunque el tipo no haya resuelto, para reportar todo junto.
  defp validar_sin_tipo(%__MODULE__{} = campo) do
    Enum.concat([
      validar_nombre(campo),
      validar_largo(campo),
      validar_posicion(campo),
      validar_trim(campo),
      validar_relleno(campo),
      validar_opcional(campo),
      validar_sensible(campo),
      validar_encoding(campo),
      validar_texto_libre(campo, :descripcion),
      validar_texto_libre(campo, :ejemplo),
      Reglas.validar(campo)
    ])
  end

  defp validar_texto_libre(%__MODULE__{nombre: nombre} = campo, opcion) do
    case Map.fetch!(campo, opcion) do
      valor when is_nil(valor) or is_binary(valor) -> []
      otro -> [falla(nombre, "#{inspect(opcion)} como texto, o ninguno", otro, nil)]
    end
  end

  defp validar_encoding(%__MODULE__{encoding: encoding}) when encoding in [nil, :utf8, :latin1],
    do: []

  defp validar_encoding(%__MODULE__{nombre: nombre, encoding: encoding}) do
    [falla(nombre, ":encoding :utf8 o :latin1, o ninguno para usar el del layout", encoding, nil)]
  end

  defp validar_nombre(%__MODULE__{nombre: :__traza__}) do
    [
      falla(
        :__traza__,
        "un :nombre que no sea :__traza__",
        :__traza__,
        "es la clave reservada para la traza del registro (ver AnchoFijo.Traza)"
      )
    ]
  end

  defp validar_nombre(%__MODULE__{nombre: nombre}) when is_atom(nombre) and not is_nil(nombre),
    do: []

  defp validar_nombre(%__MODULE__{nombre: nombre}) do
    [
      falla(
        nil,
        "un :nombre átomo",
        nombre,
        "cada campo necesita un nombre para ser una clave del registro"
      )
    ]
  end

  # El largo de un grupo o una variante sale de sus campos internos: lo que
  # haya que reclamar lo reclama el tipo (repetir, campos, variantes).
  defp validar_largo(%__MODULE__{tipo: tipo}) when tipo in [:grupo, :variante], do: []
  defp validar_largo(%__MODULE__{largo: largo}) when is_integer(largo) and largo > 0, do: []

  defp validar_largo(%__MODULE__{nombre: nombre, largo: largo}) do
    [
      falla(
        nombre,
        "un :largo entero mayor que cero",
        largo,
        "revise la especificación del formato"
      )
    ]
  end

  defp validar_posicion(%__MODULE__{posicion: nil}), do: []

  defp validar_posicion(%__MODULE__{posicion: posicion}) when is_integer(posicion) and posicion > 0,
    do: []

  defp validar_posicion(%__MODULE__{nombre: nombre, posicion: posicion}) do
    [
      falla(nombre, "una :posicion entera 1-based", posicion, "las posiciones parten en 1, no en 0")
    ]
  end

  defp validar_trim(%__MODULE__{trim: trim}) when trim in @trims, do: []

  defp validar_trim(%__MODULE__{nombre: nombre, trim: trim}) do
    [falla(nombre, ":trim en [:ambos, :izquierda, :derecha, false]", trim, nil)]
  end

  defp validar_relleno(%__MODULE__{relleno: relleno}) when is_binary(relleno) do
    if String.length(relleno) == 1,
      do: [],
      else: [falla(nil, "un :relleno de un solo carácter", relleno, nil)]
  end

  defp validar_relleno(%__MODULE__{nombre: nombre, relleno: relleno}) do
    [falla(nombre, "un :relleno binario de un carácter", relleno, nil)]
  end

  defp validar_opcional(%__MODULE__{opcional: opcional}) when is_boolean(opcional), do: []

  defp validar_opcional(%__MODULE__{nombre: nombre, opcional: opcional}) do
    [falla(nombre, ":opcional true o false", opcional, nil)]
  end

  defp validar_sensible(%__MODULE__{sensible: sensible}) when is_boolean(sensible), do: []

  defp validar_sensible(%__MODULE__{nombre: nombre, sensible: sensible}) do
    [falla(nombre, ":sensible true o false", sensible, nil)]
  end

  # Se reclama por una opción declarada de verdad, no por la clave presente en
  # su default: quien construye la definición desde otro campo con
  # `Map.from_struct/1` arrastra todas las claves y no está declarando nada.
  # Una opción que ningún tipo conoce también se reclama: `precison: 2` mal
  # escrito no puede pasar en silencio.
  defp validar_opciones_ajenas(%__MODULE__{modulo: modulo, nombre: nombre} = campo, atributos) do
    propias = modulo.opciones()

    internas =
      @de_tipos_internos
      |> Enum.filter(fn {opcion, default} ->
        opcion not in propias and Map.get(atributos, opcion, default) != default
      end)
      |> Enum.map(fn {opcion, _default} -> opcion end)

    conocidas =
      @comunes ++
        propias ++ Keyword.keys(@de_tipos_internos) ++ [:__struct__, :modulo, :opciones, :reglas]

    desconocidas = atributos |> Map.keys() |> Enum.reject(&(&1 in conocidas))

    Enum.map(internas, fn opcion ->
      falla(
        nombre,
        "#{inspect(opcion)} solo en campos #{Enum.map_join(propietarios(opcion), " o ", &inspect/1)}",
        "un campo #{inspect(campo.tipo)}",
        "la opción no aplica a este tipo y sería ignorada en silencio"
      )
    end) ++
      Enum.map(desconocidas, fn opcion ->
        falla(
          nombre,
          "opciones de #{inspect(campo.tipo)}: #{describir_opciones(propias)}",
          opcion,
          "la opción no existe para este tipo y sería ignorada en silencio"
        )
      end)
  end

  defp propietarios(opcion) do
    Tipo.internos()
    |> Enum.filter(fn {_atomo, modulo} -> opcion in modulo.opciones() end)
    |> Enum.map(fn {atomo, _modulo} -> atomo end)
  end

  defp describir_opciones([]), do: "ninguna además de las comunes"
  defp describir_opciones(propias), do: Enum.map_join(propias, ", ", &inspect/1)

  defp falla(nombre, esperado, recibido, causa) do
    Diagnostico.nuevo(
      tipo: :layout,
      campo: nombre,
      esperado: esperado,
      recibido: recibido,
      causa_probable: causa
    )
  end

  defp rebanar(%__MODULE__{} = campo, linea, :bytes, contexto) do
    desde = campo.posicion - 1

    if byte_size(linea) >= desde + campo.largo do
      {:ok, :binary.part(linea, desde, campo.largo)}
    else
      {:error, fuera_de_rango(campo, byte_size(linea), :bytes, contexto)}
    end
  end

  defp rebanar(%__MODULE__{} = campo, linea, :caracteres, contexto) do
    trozo = String.slice(linea, campo.posicion - 1, campo.largo)

    if String.length(trozo) == campo.largo do
      {:ok, trozo}
    else
      {:error, fuera_de_rango(campo, String.length(linea), :caracteres, contexto)}
    end
  end

  defp fuera_de_rango(%__MODULE__{} = campo, medida, unidad, contexto) do
    unidad = nombre_unidad(unidad)

    diagnostico(campo, contexto,
      tipo: :largo_de_linea,
      esperado: "al menos #{fin(campo)} #{unidad}",
      recibido: "#{medida}",
      causa_probable: "la línea termina antes de este campo"
    )
  end

  defp decodificar(_campo, crudo, :caracteres, _contexto), do: {:ok, crudo}

  defp decodificar(%__MODULE__{} = campo, crudo, :bytes, contexto) do
    encoding = Map.get(contexto, :encoding, :utf8)

    case Transcodificacion.a_utf8(crudo, encoding) do
      {:ok, texto} ->
        {:ok, texto}

      {:error, detalle} ->
        {:error, error_de_encoding(campo, crudo, encoding, detalle, contexto)}
    end
  end

  defp error_de_encoding(%__MODULE__{} = campo, crudo, encoding, detalle, contexto) do
    diagnostico(campo, contexto,
      tipo: :encoding,
      esperado: "bytes válidos en #{encoding}",
      recibido: Transcodificacion.describir_byte(detalle, campo.posicion),
      causa_probable: Transcodificacion.causa_probable(detalle, encoding),
      contenido: inspect(crudo, binaries: :as_binaries)
    )
  end

  defp limpiar(texto, %__MODULE__{modulo: Tipo.Texto} = campo) do
    case campo.trim do
      :ambos -> texto |> String.trim_leading(campo.relleno) |> String.trim_trailing(campo.relleno)
      :izquierda -> String.trim_leading(texto, campo.relleno)
      :derecha -> String.trim_trailing(texto, campo.relleno)
      false -> texto
    end
  end

  # Un literal se compara entero: el tipo decide qué relleno final no cuenta.
  defp limpiar(texto, %__MODULE__{modulo: Tipo.Constante}), do: texto

  # En los tipos no textuales el relleno nunca es dato: un monto viene con
  # ceros o espacios a la izquierda según el humor del sistema emisor.
  defp limpiar(texto, _campo), do: String.trim(texto)

  @doc """
  El inverso de `extraer/3`: escribe el valor con el ancho, el relleno, el
  signo y el encoding que el campo declara.

  Devuelve `{:ok, texto, advertencias}` con el texto ya en el encoding del
  layout y midiendo exactamente `:largo` en la unidad del layout, o
  `{:error, diagnostico}`. El contexto es el de `AnchoFijo.Layout.contexto/2`
  más `:truncar` (ver `AnchoFijo.Escritor`).

      iex> campo = AnchoFijo.Campo.nuevo!(nombre: :monto, posicion: 1, largo: 8, tipo: :decimal, precision: 2, signo: :final)
      iex> AnchoFijo.Campo.formatear(campo, {-123_456, 2}, %{})
      {:ok, "0123456-", []}

      iex> campo = AnchoFijo.Campo.nuevo!(nombre: :glosa, posicion: 1, largo: 6)
      iex> AnchoFijo.Campo.formatear(campo, "ab", %{})
      {:ok, "ab    ", []}

  Un tipo propio escribe con su `c:AnchoFijo.Tipo.escribir/2`; si no lo
  implementa, el campo no se puede escribir y es un diagnóstico.
  """
  @spec formatear(t(), term(), contexto() | keyword()) ::
          {:ok, binary(), [Diagnostico.t()]} | {:error, Diagnostico.t()}
  def formatear(%__MODULE__{} = campo, valor, contexto \\ %{}) do
    contexto = contexto |> Map.new() |> con_encoding_del_campo(campo)

    resultado =
      with [] <- Reglas.del_valor(campo, canonico(campo, valor), contexto),
           {:ok, texto, advertencias} <- representar(campo, valor, contexto),
           {:ok, codificado} <- codificar(campo, texto, contexto) do
        {:ok, codificado, advertencias}
      else
        [regla | _] -> {:error, regla}
        {:error, diagnostico} -> {:error, diagnostico}
      end

    sensibilizar_escritura(resultado, campo, valor)
  end

  @doc false
  # El valor como lo devolvería `leer/3` para ese campo, para que las reglas
  # miren lo mismo al leer y al escribir: un `%Decimal{}`, un entero o un
  # string de un `:decimal` son la tupla, el `Monto` o el `Decimal` del
  # campo; un `:texto` se recorta como al leer. Lo que no se puede llevar
  # queda como vino, y `representar/3` lo reclama después.
  @spec canonico(t(), term()) :: term()
  def canonico(%__MODULE__{modulo: Tipo.Decimal} = campo, valor)
      when is_struct(valor, Decimal) or is_integer(valor) or is_binary(valor) do
    case Tipo.Decimal.a_unidades(valor, campo) do
      {:ok, unidades} -> Tipo.Decimal.valor(unidades, campo)
      {:error, _causa} -> valor
    end
  end

  def canonico(
        %__MODULE__{modulo: Tipo.Decimal, precision: precision} = campo,
        {unidades, precision}
      )
      when is_integer(unidades),
      do: Tipo.Decimal.valor(unidades, campo)

  def canonico(%__MODULE__{modulo: Tipo.Texto} = campo, valor) when is_binary(valor),
    do: limpiar(valor, campo)

  def canonico(_campo, valor), do: valor

  # Al escribir, el dato es el valor del mapa, en el tipo en que vino, y los
  # diagnósticos lo llevan en `:recibido` como al leer: un texto que no cabe,
  # un RUT con el DV malo, un entero donde iba una fecha. Salen marcados con
  # la forma del valor, también la advertencia de un texto truncado.
  defp sensibilizar_escritura({:error, diagnostico}, %__MODULE__{sensible: true}, valor),
    do: {:error, Diagnostico.marcar_sensible(diagnostico, Diagnostico.texto_de(valor))}

  defp sensibilizar_escritura({:ok, texto, advertencias}, %__MODULE__{sensible: true}, valor) do
    forma = Diagnostico.texto_de(valor)
    {:ok, texto, Enum.map(advertencias, &Diagnostico.marcar_sensible(&1, forma))}
  end

  defp sensibilizar_escritura(resultado, _campo, _valor), do: resultado

  # Un relleno se escribe solo, con su carácter; un valor en el mapa es un
  # error, porque el relleno no es dato de nadie.
  defp representar(%__MODULE__{modulo: Tipo.Relleno} = campo, nil, contexto),
    do: completar(campo, "", campo.largo, contexto)

  defp representar(%__MODULE__{modulo: Tipo.Relleno} = campo, valor, contexto) do
    {:error,
     diagnostico(campo, contexto,
       esperado: "ningún valor para el campo de relleno, o nil",
       recibido: inspect(valor),
       causa_probable: "el relleno lo pone el layout, no el registro; saque la clave del mapa"
     )}
  end

  # Una constante se escribe sola, o con el mismo literal en el mapa; otro
  # valor no es un dato distinto, es otro formato.
  defp representar(%__MODULE__{modulo: Tipo.Constante, valor: valor} = campo, dado, contexto)
       when is_nil(dado) or dado == valor do
    ancho = medir(valor, contexto)

    if ancho <= campo.largo,
      do: completar(campo, valor, campo.largo - ancho, contexto),
      else:
        {:error,
         no_cabe(campo, valor, ancho, "un literal de hasta #{campo.largo} posiciones", contexto)}
  end

  defp representar(%__MODULE__{modulo: Tipo.Constante, valor: valor} = campo, dado, contexto) do
    {:error,
     diagnostico(campo, contexto,
       esperado: "el literal #{inspect(valor)}, o el campo ausente del mapa",
       recibido: inspect(dado),
       causa_probable: "el campo es una constante del formato y no se escribe desde el registro"
     )}
  end

  # nil solo cabe en un campo opcional, y se escribe como blanco.
  defp representar(%__MODULE__{opcional: true, largo: largo}, nil, _contexto),
    do: {:ok, String.duplicate(" ", largo), []}

  defp representar(%__MODULE__{} = campo, nil, contexto) do
    {:error,
     diagnostico(campo, contexto,
       esperado: "un valor #{inspect(campo.tipo)}",
       recibido: "nil",
       causa_probable: "el registro no trae el campo; declare opcional: true si puede ir en blanco"
     )}
  end

  defp representar(%__MODULE__{modulo: Tipo.Texto} = campo, valor, contexto)
       when is_binary(valor) do
    ancho = medir(valor, contexto)

    cond do
      ancho == campo.largo ->
        {:ok, valor, []}

      ancho < campo.largo and campo.trim != false ->
        completar(campo, valor, campo.largo - ancho, contexto)

      ancho < campo.largo ->
        {:error,
         no_cabe(
           campo,
           valor,
           ancho,
           "un texto de exactamente #{campo.largo} posiciones (trim: false)",
           contexto
         )}

      Map.get(contexto, :truncar, false) ->
        {:ok, recortar(valor, campo.largo, contexto), [truncado(campo, valor, ancho, contexto)]}

      true ->
        {:error,
         no_cabe(campo, valor, ancho, "un texto de hasta #{campo.largo} posiciones", contexto)}
    end
  end

  defp representar(%__MODULE__{modulo: Tipo.Entero} = campo, valor, contexto)
       when is_integer(valor) do
    con_signo(
      campo,
      valor,
      Integer.to_string(abs(valor)),
      "un entero de hasta #{campo.largo} dígitos",
      contexto
    )
  end

  # Un `%Decimal{}`, un entero en unidades enteras o un string numérico se
  # llevan a unidades mínimas sin redondear; con moneda, pasan por el mismo
  # camino que la tupla.
  defp representar(%__MODULE__{modulo: Tipo.Decimal} = campo, valor, contexto)
       when is_struct(valor, Decimal) or is_integer(valor) or is_binary(valor) do
    case Tipo.Decimal.a_unidades(valor, campo) do
      {:ok, unidades} ->
        representar(campo, {unidades, campo.precision}, contexto)

      {:error, causa} ->
        {:error,
         diagnostico(campo, contexto,
           esperado: descripcion_de_valor(campo),
           recibido: inspect(valor),
           causa_probable: causa
         )}
    end
  end

  # Un `AnchoFijo.Monto` se escribe si es de la moneda y la precisión del
  # campo: es exactamente lo que `extraer/3` devuelve para ese campo.
  defp representar(
         %__MODULE__{modulo: Tipo.Decimal, moneda: moneda, precision: precision} = campo,
         %Monto{moneda: moneda, precision: precision, unidades: unidades},
         contexto
       )
       when not is_nil(moneda) do
    representar(campo, {unidades, precision}, contexto)
  end

  defp representar(
         %__MODULE__{modulo: Tipo.Decimal, moneda: moneda} = campo,
         %Monto{} = monto,
         contexto
       )
       when not is_nil(moneda) do
    {:error,
     diagnostico(campo, contexto,
       esperado: "un AnchoFijo.Monto en #{Monto.codigo(moneda)} con precisión #{campo.precision}",
       recibido: inspect(monto),
       causa_probable: "el monto es de otra moneda o de otra precisión; convierta antes"
     )}
  end

  # La representación mínima: los dígitos de las unidades, y con separador
  # explícito la parte entera (que puede ser vacía) y los decimales. Los
  # ceros a la izquierda los pone `con_signo/5` hasta llenar el campo, así
  # que `{-1, 2}` en tres posiciones es `-01`, como lo lee el parser.
  defp representar(
         %__MODULE__{modulo: Tipo.Decimal, precision: precision} = campo,
         {unidades, precision},
         contexto
       )
       when is_integer(unidades) do
    digitos = Integer.to_string(abs(unidades))

    texto =
      case campo.separador do
        :implicito ->
          digitos

        separador ->
          con_fraccion = String.pad_leading(digitos, precision, "0")

          {entera, fraccion} =
            String.split_at(con_fraccion, String.length(con_fraccion) - precision)

          entera <> caracter_separador(separador) <> fraccion
      end

    con_signo(campo, unidades, texto, descripcion_decimal(campo), contexto)
  end

  defp representar(%__MODULE__{modulo: Tipo.Decimal} = campo, {unidades, otra}, contexto)
       when is_integer(unidades) and is_integer(otra) do
    {:error,
     diagnostico(campo, contexto,
       esperado: "un monto {unidades, #{campo.precision}} con la precisión del campo",
       recibido: inspect({unidades, otra}),
       causa_probable:
         "la precisión del valor no es la del campo; escalar acá es donde se pierde el peso, convierta antes"
     )}
  end

  # Fecha, hora y fecha-hora escriben con el patrón del campo; el texto
  # mide lo que el patrón y se completa a la derecha hasta el largo.
  defp representar(%__MODULE__{modulo: modulo} = campo, valor, contexto)
       when (modulo == Tipo.Fecha and is_struct(valor, Date)) or
              (modulo == Tipo.Hora and is_struct(valor, Time)) or
              (modulo == Tipo.FechaHora and is_struct(valor, NaiveDateTime)) do
    case modulo.escribir(valor, campo) do
      {:ok, texto} ->
        {:ok, String.pad_trailing(texto, campo.largo), []}

      {:error, causa} ->
        {:error,
         diagnostico(campo, contexto,
           esperado:
             "#{descripcion_de_valor(campo)} que quepa en el formato #{inspect(campo.formato)}",
           recibido: inspect(valor),
           causa_probable: causa
         )}
    end
  end

  defp representar(%__MODULE__{modulo: Tipo.Rut} = campo, valor, contexto) when is_binary(valor) do
    case Rut.normalizar(valor, campo.dv) do
      {:ok, canonico} when byte_size(canonico) <= campo.largo ->
        {:ok, String.pad_trailing(canonico, campo.largo), []}

      # El guion es presentación: si el campo no tiene lugar para él se
      # omite, como en los formatos que reservan nueve posiciones. Lo que
      # nunca se omite es el dígito verificador.
      {:ok, canonico} when byte_size(canonico) - 1 <= campo.largo ->
        {:ok, canonico |> String.replace("-", "") |> String.pad_trailing(campo.largo), []}

      {:ok, canonico} ->
        {:error,
         no_cabe(
           campo,
           canonico,
           byte_size(canonico) - 1,
           "#{descripcion_rut(campo.dv)} de hasta #{campo.largo} posiciones",
           contexto
         )}

      {:error, {:dv, esperado, _}} ->
        {:error,
         diagnostico(campo, contexto,
           esperado:
             "un RUT cuyo dígito verificador cuadre; para ese cuerpo corresponde #{esperado}",
           recibido: inspect(valor),
           causa_probable: "el dígito verificador no cuadra; un RUT inválido no se escribe"
         )}

      {:error, {:formato, detalle}} ->
        {:error,
         diagnostico(campo, contexto,
           esperado: descripcion_rut(campo.dv),
           recibido: inspect(valor),
           causa_probable: detalle
         )}
    end
  end

  defp representar(%__MODULE__{modulo: modulo} = campo, valor, contexto) do
    if Tipo.interno?(modulo),
      do: {:error, valor_de_otro_tipo(campo, valor, contexto)},
      else: representar_externo(campo, valor, contexto)
  end

  # Un tipo propio escribe con `escribir/2`; el texto tiene que medir lo que
  # el campo declara, porque el lector va a contar exactamente eso.
  defp representar_externo(%__MODULE__{modulo: modulo} = campo, valor, contexto) do
    if function_exported?(modulo, :escribir, 2) do
      valor |> modulo.escribir(campo) |> medir_externo(campo, valor, contexto)
    else
      {:error,
       diagnostico(campo, contexto,
         esperado: "un tipo que implemente escribir/2",
         recibido: inspect(modulo),
         causa_probable:
           "el tipo #{inspect(modulo)} solo sabe leer; implemente escribir/2 para escribirlo"
       )}
    end
  end

  defp medir_externo({:ok, texto}, %__MODULE__{} = campo, valor, contexto) when is_binary(texto) do
    ancho = medir(texto, contexto)

    if ancho == campo.largo do
      {:ok, texto, []}
    else
      esperado = "un texto de exactamente #{campo.largo} posiciones"
      {:error, no_cabe(campo, valor, ancho, esperado, contexto)}
    end
  end

  defp medir_externo({:error, causa}, %__MODULE__{modulo: modulo} = campo, valor, contexto) do
    {:error,
     diagnostico(campo, contexto,
       esperado: "un valor que #{inspect(modulo)} sepa escribir",
       recibido: inspect(valor),
       causa_probable: causa
     )}
  end

  defp valor_de_otro_tipo(%__MODULE__{} = campo, valor, contexto) do
    diagnostico(campo, contexto,
      esperado: descripcion_de_valor(campo),
      recibido: inspect(valor),
      causa_probable: "el valor no es del tipo que el campo escribe"
    )
  end

  defp descripcion_de_valor(%__MODULE__{modulo: Tipo.Texto}), do: "un binario"
  defp descripcion_de_valor(%__MODULE__{modulo: Tipo.Entero}), do: "un entero"

  defp descripcion_de_valor(%__MODULE__{modulo: Tipo.Decimal, moneda: moneda, precision: p})
       when not is_nil(moneda),
       do:
         "un AnchoFijo.Monto en #{Monto.codigo(moneda)}, un monto {unidades, #{p}}, " <>
           "un Decimal o un entero"

  defp descripcion_de_valor(%__MODULE__{modulo: Tipo.Decimal, precision: p}),
    do: "un monto {unidades, #{p}}, un Decimal o un entero"

  defp descripcion_de_valor(%__MODULE__{modulo: Tipo.Fecha}), do: "una fecha (Date)"
  defp descripcion_de_valor(%__MODULE__{modulo: Tipo.Hora}), do: "una hora (Time)"

  defp descripcion_de_valor(%__MODULE__{modulo: Tipo.FechaHora}),
    do: "una fecha y hora (NaiveDateTime)"

  defp descripcion_de_valor(%__MODULE__{modulo: Tipo.Rut}), do: "un RUT como binario"

  # El signo ocupa una posición solo en los negativos, del lado que el layout
  # declara; los ceros van a la izquierda de los dígitos, nunca del signo.
  defp con_signo(%__MODULE__{} = campo, valor, digitos, esperado, contexto) do
    ancho_signo = if valor < 0, do: 1, else: 0
    disponible = campo.largo - ancho_signo

    if String.length(digitos) > disponible do
      {:error, no_cabe(campo, valor, String.length(digitos) + ancho_signo, esperado, contexto)}
    else
      rellenado = String.pad_leading(digitos, disponible, "0")

      texto =
        case {valor < 0, campo.signo} do
          {false, _} -> rellenado
          {true, :inicial} -> "-" <> rellenado
          {true, :final} -> rellenado <> "-"
        end

      {:ok, texto, []}
    end
  end

  # Completa el valor hasta el largo del campo repitiendo el relleno. El
  # relleno tiene que medir exactamente una posición en la unidad del layout:
  # con `unidad: :bytes` y UTF-8, un relleno de dos bytes ("·") no puede dar
  # un ancho exacto, y escribirlo igual correría todas las columnas que
  # siguen. Es un error del layout que se reporta al escribir (y como
  # advertencia en `Layout.nuevo/1`).
  defp completar(%__MODULE__{}, valor, 0, _contexto), do: {:ok, valor, []}

  defp completar(%__MODULE__{relleno: relleno} = campo, valor, faltan, contexto) do
    case medir(relleno, contexto) do
      1 ->
        {:ok, rellenar_texto(valor, campo, faltan), []}

      medida ->
        {:error,
         diagnostico(campo, contexto,
           tipo: :layout,
           esperado: "un :relleno de una posición en #{nombre_unidad(unidad_efectiva(contexto))}",
           recibido: inspect(relleno),
           causa_probable:
             "el relleno mide #{medida} #{nombre_unidad(unidad_efectiva(contexto))} y hay " <>
               "#{faltan} posiciones por completar: el campo no puede quedar de su largo exacto"
         )}
    end
  end

  defp rellenar_texto(valor, %__MODULE__{trim: :izquierda, relleno: relleno}, faltan),
    do: String.duplicate(relleno, faltan) <> valor

  defp rellenar_texto(valor, %__MODULE__{relleno: relleno}, faltan),
    do: valor <> String.duplicate(relleno, faltan)

  defp unidad_efectiva(%{unidad: :caracteres}), do: :caracteres
  defp unidad_efectiva(_contexto), do: :bytes

  # Cuando bytes y caracteres no coinciden, el mensaje dice los dos: es la
  # diferencia que explica por qué "cinco letras" no caben en cinco
  # posiciones.
  defp describir_ancho(valor, contexto) when is_binary(valor) do
    bytes =
      case Map.get(contexto, :encoding, :utf8) do
        :latin1 -> String.length(valor)
        _utf8 -> byte_size(valor)
      end

    caracteres = String.length(valor)

    if bytes == caracteres,
      do: "",
      else: " (#{bytes} bytes, #{caracteres} caracteres)"
  end

  defp describir_ancho(_valor, _contexto), do: ""

  defp caracter_separador(:punto), do: "."
  defp caracter_separador(:coma), do: ","

  defp descripcion_decimal(%__MODULE__{separador: :implicito, largo: largo, precision: precision}) do
    "#{largo} dígitos con #{precision} decimales implícitos"
  end

  defp descripcion_decimal(%__MODULE__{separador: separador, precision: precision}) do
    "un número con #{separador} decimal y a lo más #{precision} decimales"
  end

  defp descripcion_rut(:ausente), do: "el cuerpo de un RUT, sin dígito verificador"
  defp descripcion_rut(_con_dv), do: "un RUT con dígito verificador"

  # El ancho se mide como lo medirá el lector: en bytes del encoding del
  # layout, o en caracteres.
  defp medir(texto, %{unidad: :caracteres}), do: String.length(texto)

  defp medir(texto, contexto) do
    case Map.get(contexto, :encoding, :utf8) do
      :latin1 -> String.length(texto)
      _utf8 -> byte_size(texto)
    end
  end

  defp recortar(texto, largo, %{unidad: :caracteres}), do: String.slice(texto, 0, largo)

  defp recortar(texto, largo, contexto) do
    case Map.get(contexto, :encoding, :utf8) do
      :latin1 -> String.slice(texto, 0, largo)
      _utf8 -> recortar_bytes(texto, largo)
    end
  end

  # Nunca a la mitad de un carácter multibyte: se recorta por grafemas hasta
  # que quepa en bytes, y lo que falte se completa con espacios.
  defp recortar_bytes(texto, largo) do
    recortado =
      texto
      |> String.graphemes()
      |> Enum.reduce_while("", fn grafema, acumulado ->
        candidato = acumulado <> grafema
        if byte_size(candidato) <= largo, do: {:cont, candidato}, else: {:halt, acumulado}
      end)

    recortado <> String.duplicate(" ", largo - byte_size(recortado))
  end

  # Latin-1 cubre los puntos de código hasta 255; el primero que se pasa se
  # reporta con su posición, que es lo que hace falta para corregir el dato.
  defp codificar(%__MODULE__{} = campo, texto, %{encoding: :latin1} = contexto) do
    case Enum.find_index(String.to_charlist(texto), &(&1 > 255)) do
      nil ->
        {:ok, :unicode.characters_to_binary(texto, :utf8, :latin1)}

      indice ->
        caracter =
          texto |> String.to_charlist() |> Enum.at(indice) |> List.wrap() |> List.to_string()

        {:error,
         diagnostico(campo, contexto,
           tipo: :encoding,
           esperado: "caracteres representables en latin1",
           recibido: "#{inspect(caracter)} en la posición #{indice + 1} del valor",
           causa_probable:
             "el layout declara encoding: :latin1 y el valor trae un carácter que latin-1 no tiene"
         )}
    end
  end

  defp codificar(%__MODULE__{}, texto, _contexto), do: {:ok, texto}

  defp no_cabe(%__MODULE__{} = campo, valor, ancho, esperado, contexto) do
    diagnostico(campo, contexto,
      esperado: esperado,
      recibido: inspect(valor),
      causa_probable:
        "el valor no cabe en el campo: #{ancho} posiciones en #{campo.largo}" <>
          describir_ancho(valor, contexto)
    )
  end

  defp truncado(%__MODULE__{} = campo, valor, ancho, contexto) do
    diagnostico(campo, contexto,
      tipo: :campo_truncado,
      gravedad: :advertencia,
      esperado: "un texto de hasta #{campo.largo} posiciones",
      recibido: inspect(valor),
      causa_probable:
        "se recortó a #{campo.largo} posiciones porque se pidió truncar: true; sobraban #{ancho - campo.largo}" <>
          describir_ancho(valor, contexto)
    )
  end

  defp diagnostico(%__MODULE__{} = campo, contexto, atributos) do
    atributos
    |> Keyword.put_new(:tipo, :campo_invalido)
    |> Keyword.merge(
      campo: campo.nombre,
      posicion: rango(campo),
      linea: Map.get(contexto, :linea)
    )
    |> Diagnostico.nuevo()
  end
end
