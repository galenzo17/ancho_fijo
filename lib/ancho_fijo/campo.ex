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
    * `:tipo` — `:texto` (default), `:entero`, `:decimal`, `:fecha`, `:rut`,
      o un módulo que implemente `AnchoFijo.Tipo` para un tipo propio. Las
      opciones propias de ese tipo quedan en `:opciones`.
    * `:opcional` — si es `true`, un campo en blanco (o en ceros, para fechas)
      se lee como `nil` en vez de producir un diagnóstico. Default `false`.
    * `:trim` — `:ambos` (default), `:izquierda`, `:derecha` o `false`. Solo
      aplica a `:texto`; los tipos numéricos y de fecha siempre recortan
      espacios porque el relleno no es parte del dato.
    * `:relleno` — carácter de relleno a recortar en `:texto`. Default `" "`.
    * `:precision` — obligatorio en `:decimal`. Cantidad de decimales que el
      formato declara.
    * `:separador` — en `:decimal`: `:implicito` (default), `:punto` o `:coma`.
    * `:moneda` — en `:decimal`: código ISO 4217 como átomo (`:clp`, `:usd`).
      El valor pasa a ser un `AnchoFijo.Monto` y la `:precision` se toma de
      la escala de la moneda; declararla distinta es un layout inválido.
    * `:signo` — en `:entero` y `:decimal`: `:inicial` (default) o `:final`.
      Con `:final` el signo va después de los dígitos, `0125000-`, como en los
      formatos heredados de mainframe.
    * `:formato` — obligatorio en `:fecha`: `:aaaammdd` o `:ddmmaaaa`.
    * `:dv` — en `:rut`: `:validar` (default), `:no_validar` o `:ausente`. Ver
      `AnchoFijo.Rut`.
    * `:sensible` — si es `true`, los diagnósticos del campo muestran la forma
      del valor y no el valor en `AnchoFijo.Diagnostico.mensaje/1` y en
      `inspect/1`. Default `false`, salvo en `:rut`, donde es `true`: un RUT
      es siempre un dato personal.

  ## Tipos y valores devueltos

  | tipo | valor |
  | --- | --- |
  | `:texto` | `String.t()` ya transcodificado a UTF-8 |
  | `:entero` | `integer()` |
  | `:decimal` | `{unidades, precision}`, p. ej. `{123456, 2}` para `1234.56`; con `:moneda`, un `AnchoFijo.Monto` |
  | `:fecha` | `Date.t()` |
  | `:rut` | `String.t()` canónico, `"12345678-5"`; solo el cuerpo, `"12345678"`, con `dv: :ausente` |

  Un `:decimal` nunca se convierte a float. Se devuelve como par
  `{unidades_minimas, precision}` —centavos y escala— porque un monto que pasa
  por punto flotante deja de cuadrar con la contabilidad del banco, y una
  librería de lectura no debería obligar a depender de `Decimal` para evitarlo.
  """

  alias AnchoFijo.Diagnostico
  alias AnchoFijo.Monto
  alias AnchoFijo.Opciones
  alias AnchoFijo.Rut
  alias AnchoFijo.Tipo
  alias AnchoFijo.Transcodificacion

  @comunes [:nombre, :posicion, :largo, :tipo, :opcional, :trim, :relleno, :sensible]
  @de_tipos_internos [
    precision: nil,
    separador: :implicito,
    moneda: nil,
    signo: :inicial,
    formato: nil,
    dv: :validar
  ]
  @trims [:ambos, :izquierda, :derecha, false, true]

  @typedoc "Un átomo de los tipos internos o un módulo que implementa `AnchoFijo.Tipo`."
  @type tipo :: :texto | :entero | :decimal | :fecha | :rut | module()
  @type valor :: String.t() | integer() | {integer(), non_neg_integer()} | Date.t() | nil

  @type t :: %__MODULE__{
          nombre: atom(),
          posicion: pos_integer() | nil,
          largo: pos_integer(),
          tipo: tipo(),
          opcional: boolean(),
          trim: :ambos | :izquierda | :derecha | false,
          relleno: String.t(),
          precision: non_neg_integer() | nil,
          separador: :implicito | :punto | :coma,
          moneda: Monto.moneda() | nil,
          signo: :inicial | :final,
          formato: :aaaammdd | :ddmmaaaa | nil,
          dv: Rut.dv(),
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
            precision: nil,
            separador: :implicito,
            moneda: nil,
            signo: :inicial,
            formato: nil,
            dv: :validar,
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
          optional(:linea) => pos_integer() | nil
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

    case Tipo.resolver(campo.tipo) do
      {:ok, modulo} ->
        campo =
          %{campo | modulo: modulo, opciones: opciones_propias(modulo, atributos)}
          |> sensible_por_tipo(atributos)
          |> precision_por_moneda()

        case validar(campo, atributos) do
          [] -> {:ok, campo}
          diagnosticos -> {:error, diagnosticos}
        end

      {:error, esperado} ->
        {:error, validar_sin_tipo(campo) ++ [falla(campo.nombre, esperado, campo.tipo, nil)]}
    end
  end

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
    contexto = Map.new(contexto)
    unidad = Map.get(contexto, :unidad, :bytes)

    with {:ok, crudo} <- campo |> rebanar(linea, unidad, contexto) |> sensibilizar(campo, nil),
         {:ok, texto} <- campo |> decodificar(crudo, unidad, contexto) |> sensibilizar(campo, nil) do
      texto = limpiar(texto, campo)
      campo |> convertir(texto, contexto) |> sensibilizar(campo, texto)
    end
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
      validar_sensible(campo)
    ])
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
      @comunes ++ propias ++ Keyword.keys(@de_tipos_internos) ++ [:__struct__, :modulo, :opciones]

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

  # En los tipos no textuales el relleno nunca es dato: un monto viene con
  # ceros o espacios a la izquierda según el humor del sistema emisor.
  defp limpiar(texto, _campo), do: String.trim(texto)

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
