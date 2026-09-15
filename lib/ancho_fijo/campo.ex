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
    * `:tipo` — `:texto` (default), `:entero`, `:decimal`, `:fecha` o `:rut`.
    * `:opcional` — si es `true`, un campo en blanco (o en ceros, para fechas)
      se lee como `nil` en vez de producir un diagnóstico. Default `false`.
    * `:trim` — `:ambos` (default), `:izquierda`, `:derecha` o `false`. Solo
      aplica a `:texto`; los tipos numéricos y de fecha siempre recortan
      espacios porque el relleno no es parte del dato.
    * `:relleno` — carácter de relleno a recortar en `:texto`. Default `" "`.
    * `:precision` — obligatorio en `:decimal`. Cantidad de decimales que el
      formato declara.
    * `:separador` — en `:decimal`: `:implicito` (default), `:punto` o `:coma`.
    * `:formato` — obligatorio en `:fecha`: `:aaaammdd` o `:ddmmaaaa`.
    * `:dv` — en `:rut`: `:validar` (default), `:no_validar` o `:ausente`. Ver
      `AnchoFijo.Rut`.

  ## Tipos y valores devueltos

  | tipo | valor |
  | --- | --- |
  | `:texto` | `String.t()` ya transcodificado a UTF-8 |
  | `:entero` | `integer()` |
  | `:decimal` | `{unidades, precision}`, p. ej. `{123456, 2}` para `1234.56` |
  | `:fecha` | `Date.t()` |
  | `:rut` | `String.t()` canónico, `"12345678-5"` |

  Un `:decimal` nunca se convierte a float. Se devuelve como par
  `{unidades_minimas, precision}` —centavos y escala— porque un monto que pasa
  por punto flotante deja de cuadrar con la contabilidad del banco, y una
  librería de lectura no debería obligar a depender de `Decimal` para evitarlo.
  """

  alias AnchoFijo.Diagnostico
  alias AnchoFijo.Rut
  alias AnchoFijo.Transcodificacion

  @tipos [:texto, :entero, :decimal, :fecha, :rut]
  @formatos_fecha [:aaaammdd, :ddmmaaaa]
  @separadores [:implicito, :punto, :coma]
  @trims [:ambos, :izquierda, :derecha, false, true]

  @type tipo :: :texto | :entero | :decimal | :fecha | :rut
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
          formato: :aaaammdd | :ddmmaaaa | nil,
          dv: Rut.dv()
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
            formato: nil,
            dv: :validar

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
      {:ok, %AnchoFijo.Campo{nombre: :rut, largo: 10, tipo: :texto}}

      iex> {:error, [diagnostico]} = AnchoFijo.Campo.nuevo(nombre: :monto, largo: 12, tipo: :decimal)
      iex> AnchoFijo.Diagnostico.mensaje(diagnostico)
      "layout, campo :monto: se esperaba :precision declarada para un campo :decimal; sin precisión no se sabe si 1234 son 12,34 o 1234,00"
  """
  @spec nuevo(Enumerable.t()) :: {:ok, t()} | {:error, [Diagnostico.t()]}
  def nuevo(atributos) do
    atributos = Map.new(atributos)
    campo = struct(%__MODULE__{}, normalizar(atributos))

    case validar(campo, atributos) do
      [] -> {:ok, campo}
      diagnosticos -> {:error, diagnosticos}
    end
  end

  @doc """
  Igual que `nuevo/1` pero levanta `AnchoFijo.Error` si la definición es inválida.

      iex> AnchoFijo.Campo.nuevo!(nombre: :fecha, largo: 8, tipo: :fecha, formato: :ddmmaaaa).formato
      :ddmmaaaa
  """
  @spec nuevo!(Enumerable.t()) :: t()
  def nuevo!(atributos) do
    case nuevo(atributos) do
      {:ok, campo} -> campo
      {:error, diagnosticos} -> raise AnchoFijo.Error, diagnosticos
    end
  end

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
      iex> campo = Campo.nuevo!(nombre: :fecha, posicion: 1, largo: 8, tipo: :fecha, formato: :aaaammdd)
      iex> {:error, diagnostico} = Campo.extraer(campo, "20240230", linea: 4)
      iex> AnchoFijo.Diagnostico.mensaje(diagnostico)
      "línea 4, campo :fecha (posiciones 1-8): se esperaban una fecha válida en formato AAAAMMDD, llegaron \\"20240230\\"; el día no existe en ese mes"
  """
  @spec extraer(t(), binary(), contexto() | keyword()) :: {:ok, valor()} | {:error, Diagnostico.t()}
  def extraer(%__MODULE__{} = campo, linea, contexto \\ %{}) do
    contexto = Map.new(contexto)
    unidad = Map.get(contexto, :unidad, :bytes)

    with {:ok, crudo} <- rebanar(campo, linea, unidad, contexto),
         {:ok, texto} <- decodificar(campo, crudo, unidad, contexto) do
      convertir(campo, limpiar(texto, campo), contexto)
    end
  end

  defp normalizar(atributos) do
    atributos
    |> Map.take([
      :nombre,
      :posicion,
      :largo,
      :tipo,
      :opcional,
      :trim,
      :relleno,
      :precision,
      :separador,
      :formato,
      :dv
    ])
    |> Map.update(:trim, :ambos, fn
      true -> :ambos
      otro -> otro
    end)
  end

  defp validar(%__MODULE__{} = campo, atributos) do
    Enum.concat([
      validar_nombre(campo),
      validar_largo(campo),
      validar_posicion(campo),
      validar_tipo(campo),
      validar_trim(campo),
      validar_relleno(campo),
      validar_opciones_de_tipo(campo),
      validar_opciones_ajenas(campo, atributos)
    ])
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

  defp validar_tipo(%__MODULE__{tipo: tipo}) when tipo in @tipos, do: []

  defp validar_tipo(%__MODULE__{nombre: nombre, tipo: tipo}) do
    [falla(nombre, "un :tipo en #{inspect(@tipos)}", tipo, nil)]
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

  defp validar_opciones_de_tipo(%__MODULE__{tipo: :decimal} = campo) do
    validar_precision(campo) ++ validar_separador(campo)
  end

  defp validar_opciones_de_tipo(%__MODULE__{tipo: :fecha} = campo) do
    validar_formato(campo) ++ validar_largo_de_fecha(campo)
  end

  defp validar_opciones_de_tipo(%__MODULE__{tipo: :rut} = campo) do
    validar_dv(campo)
  end

  defp validar_opciones_de_tipo(_campo), do: []

  defp validar_dv(%__MODULE__{dv: dv} = campo) do
    if dv in Rut.modos(),
      do: [],
      else: [falla(campo.nombre, ":dv en #{inspect(Rut.modos())}", dv, nil)]
  end

  defp validar_precision(%__MODULE__{precision: precision})
       when is_integer(precision) and precision >= 0,
       do: []

  defp validar_precision(%__MODULE__{nombre: nombre, precision: precision}) do
    [
      falla(
        nombre,
        ":precision declarada para un campo :decimal",
        precision,
        "sin precisión no se sabe si 1234 son 12,34 o 1234,00"
      )
    ]
  end

  defp validar_separador(%__MODULE__{separador: separador}) when separador in @separadores, do: []

  defp validar_separador(%__MODULE__{nombre: nombre, separador: separador}) do
    [falla(nombre, ":separador en #{inspect(@separadores)}", separador, nil)]
  end

  # No hay default para :formato a propósito. Adivinar si 01022024 es el 1 de
  # febrero o el 2 de enero es justamente el error silencioso que esta librería
  # existe para impedir: la definición tiene que decirlo.
  defp validar_formato(%__MODULE__{formato: formato}) when formato in @formatos_fecha, do: []

  defp validar_formato(%__MODULE__{nombre: nombre, formato: formato}) do
    [
      falla(
        nombre,
        ":formato en #{inspect(@formatos_fecha)}",
        formato,
        "el orden de una fecha no se adivina: hay que declararlo"
      )
    ]
  end

  defp validar_largo_de_fecha(%__MODULE__{largo: largo}) when is_integer(largo) and largo >= 8,
    do: []

  defp validar_largo_de_fecha(%__MODULE__{nombre: nombre, largo: largo}) do
    [falla(nombre, "un :largo de al menos 8 para una fecha", largo, nil)]
  end

  # Se reclama por una opción declarada de verdad, no por la clave presente en
  # nil: quien construye la definición desde otro campo con `Map.from_struct/1`
  # arrastra todas las claves y no está declarando nada.
  defp validar_opciones_ajenas(%__MODULE__{tipo: tipo, nombre: nombre}, atributos) do
    [
      {:precision, :decimal, nil},
      {:separador, :decimal, :implicito},
      {:formato, :fecha, nil},
      {:dv, :rut, :validar}
    ]
    |> Enum.filter(fn {opcion, propietario, default} ->
      tipo != propietario and Map.get(atributos, opcion, default) != default
    end)
    |> Enum.map(fn {opcion, propietario, _default} -> {opcion, propietario} end)
    |> Enum.map(fn {opcion, propietario} ->
      falla(
        nombre,
        "#{inspect(opcion)} solo en campos #{inspect(propietario)}",
        "un campo #{inspect(tipo)}",
        "la opción no aplica a este tipo y sería ignorada en silencio"
      )
    end)
  end

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

  defp limpiar(texto, %__MODULE__{tipo: :texto} = campo) do
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

  defp convertir(%__MODULE__{tipo: :texto, opcional: true}, "", _contexto), do: {:ok, nil}
  defp convertir(%__MODULE__{tipo: :texto}, texto, _contexto), do: {:ok, texto}

  defp convertir(%__MODULE__{} = campo, "", contexto), do: vacio(campo, contexto)

  defp convertir(%__MODULE__{tipo: :entero} = campo, texto, contexto) do
    case Integer.parse(texto) do
      {numero, ""} ->
        {:ok, numero}

      _no_entero ->
        {:error,
         diagnostico(campo, contexto,
           esperado: "#{campo.largo} posiciones con un número entero",
           recibido: inspect(texto),
           causa_probable: "hay caracteres no numéricos o el campo está corrido"
         )}
    end
  end

  defp convertir(%__MODULE__{tipo: :decimal} = campo, texto, contexto) do
    {signo, digitos} = separar_signo(texto)

    case unidades(digitos, campo) do
      {:ok, unidades} -> {:ok, {signo * unidades, campo.precision}}
      {:error, {:exceso, fraccion}} -> {:error, exceso_de_decimales(campo, fraccion, contexto)}
      {:error, :formato} -> {:error, error_decimal(campo, texto, contexto)}
    end
  end

  defp convertir(%__MODULE__{tipo: :rut} = campo, texto, contexto) do
    case Rut.normalizar(texto, campo.dv) do
      {:ok, rut} ->
        {:ok, rut}

      {:error, {:dv, esperado, _recibido}} ->
        {:error,
         diagnostico(campo, contexto,
           esperado:
             "un RUT cuyo dígito verificador cuadre; para ese cuerpo corresponde #{esperado}",
           recibido: inspect(texto),
           causa_probable:
             "el dígito verificador no cuadra: posible error de digitación o campo corrido"
         )}

      {:error, {:formato, detalle}} ->
        {:error,
         diagnostico(campo, contexto,
           esperado: descripcion_rut(campo.dv),
           recibido: inspect(texto),
           causa_probable: detalle
         )}
    end
  end

  defp convertir(%__MODULE__{tipo: :fecha} = campo, texto, contexto) do
    if fecha_nula?(texto),
      do: fecha_vacia(campo, texto, contexto),
      else: armar_fecha(campo, texto, contexto)
  end

  defp separar_signo("-" <> resto), do: {-1, resto}
  defp separar_signo("+" <> resto), do: {1, resto}
  defp separar_signo(texto), do: {1, texto}

  # Con separador implícito el campo entero ya viene en unidades mínimas: el
  # anexo dice "10 posiciones, 2 decimales" y el archivo trae 0000125000 para
  # 1.250,00. Escalarlo otra vez multiplicaría los montos por cien, que es la
  # clase de error que nadie nota hasta el cierre de mes.
  defp unidades(digitos, %__MODULE__{separador: :implicito}) do
    if solo_digitos?(digitos), do: {:ok, String.to_integer(digitos)}, else: {:error, :formato}
  end

  defp unidades(digitos, %__MODULE__{separador: separador, precision: precision}) do
    case String.split(digitos, caracter_separador(separador)) do
      [entera] -> escalar(entera, "", precision)
      [entera, fraccion] -> escalar(entera, fraccion, precision)
      _varios -> {:error, :formato}
    end
  end

  defp caracter_separador(:punto), do: "."
  defp caracter_separador(:coma), do: ","

  defp escalar(entera, fraccion, precision) do
    entera = if entera == "", do: "0", else: entera

    cond do
      not solo_digitos?(entera) -> {:error, :formato}
      fraccion != "" and not solo_digitos?(fraccion) -> {:error, :formato}
      String.length(fraccion) > precision -> {:error, {:exceso, fraccion}}
      true -> {:ok, String.to_integer(entera <> String.pad_trailing(fraccion, precision, "0"))}
    end
  end

  defp exceso_de_decimales(%__MODULE__{precision: precision} = campo, fraccion, contexto) do
    diagnostico(campo, contexto,
      esperado: "a lo más #{precision} decimales",
      recibido: "#{String.length(fraccion)} (#{inspect(fraccion)})",
      causa_probable: "la precisión declarada en el layout es menor que la del archivo"
    )
  end

  defp error_decimal(%__MODULE__{} = campo, texto, contexto) do
    diagnostico(campo, contexto,
      esperado: descripcion_decimal(campo),
      recibido: inspect(texto),
      causa_probable: causa_decimal(campo.separador)
    )
  end

  defp descripcion_decimal(%__MODULE__{separador: :implicito, largo: largo, precision: precision}) do
    "#{largo} dígitos con #{precision} decimales implícitos"
  end

  defp descripcion_decimal(%__MODULE__{separador: separador, precision: precision}) do
    "un número con #{separador} decimal y a lo más #{precision} decimales"
  end

  defp causa_decimal(:implicito) do
    "el monto trae un separador decimal explícito o un carácter no numérico; " <>
      "si el archivo usa punto o coma, declare separador: :punto o :coma"
  end

  defp causa_decimal(_separador), do: "hay caracteres no numéricos o más de un separador"

  # Un campo :fecha en blanco y uno en ceros son la misma cosa en la práctica:
  # el sistema emisor no tenía el dato. Los formatos bancarios usan ambos.
  defp fecha_nula?(texto), do: texto == "" or texto =~ ~r/\A0+\z/

  defp fecha_vacia(%__MODULE__{opcional: true}, _texto, _contexto), do: {:ok, nil}

  defp fecha_vacia(%__MODULE__{} = campo, texto, contexto) do
    {:error,
     diagnostico(campo, contexto,
       esperado: "una fecha en formato #{descripcion_formato(campo.formato)}",
       recibido: inspect(texto),
       causa_probable:
         "el emisor usa blancos o ceros para 'sin fecha'; declare opcional: true si es esperable"
     )}
  end

  defp armar_fecha(%__MODULE__{} = campo, texto, contexto) do
    with 8 <- String.length(texto),
         {:ok, anio, mes, dia} <- desarmar_fecha(texto, campo.formato),
         {:ok, fecha} <- Date.new(anio, mes, dia) do
      {:ok, fecha}
    else
      _invalida -> {:error, error_fecha(campo, texto, contexto)}
    end
  end

  defp desarmar_fecha(texto, :aaaammdd) do
    with {:ok, anio} <- tramo(texto, 0, 4),
         {:ok, mes} <- tramo(texto, 4, 2),
         {:ok, dia} <- tramo(texto, 6, 2),
         do: {:ok, anio, mes, dia}
  end

  defp desarmar_fecha(texto, :ddmmaaaa) do
    with {:ok, dia} <- tramo(texto, 0, 2),
         {:ok, mes} <- tramo(texto, 2, 2),
         {:ok, anio} <- tramo(texto, 4, 4),
         do: {:ok, anio, mes, dia}
  end

  defp tramo(texto, desde, largo) do
    trozo = binary_part(texto, desde, largo)

    case Integer.parse(trozo) do
      {numero, ""} -> {:ok, numero}
      _no_numerico -> :error
    end
  end

  defp error_fecha(%__MODULE__{} = campo, texto, contexto) do
    diagnostico(campo, contexto,
      esperado: "una fecha válida en formato #{descripcion_formato(campo.formato)}",
      recibido: inspect(texto),
      causa_probable: causa_fecha(texto, campo.formato)
    )
  end

  defp causa_fecha(texto, formato) do
    if String.length(texto) == 8 and Regex.match?(~r/\A\d{8}\z/, texto) do
      causa_fecha_numerica(texto, formato)
    else
      "se esperaban 8 dígitos; el campo puede estar corrido o traer separadores"
    end
  end

  defp causa_fecha_numerica(texto, formato) do
    {:ok, anio, mes, dia} = desarmar_fecha(texto, formato)

    cond do
      mes < 1 or mes > 12 -> "el mes #{mes} no existe: puede que el formato sea el inverso"
      dia < 1 -> "el día viene en cero"
      anio == 0 -> "el año viene en cero"
      true -> "el día no existe en ese mes"
    end
  end

  defp descripcion_rut(:ausente), do: "el cuerpo de un RUT, sin dígito verificador"
  defp descripcion_rut(_con_dv), do: "un RUT con dígito verificador"

  defp descripcion_formato(:aaaammdd), do: "AAAAMMDD"
  defp descripcion_formato(:ddmmaaaa), do: "DDMMAAAA"
  defp descripcion_formato(otro), do: inspect(otro)

  defp vacio(%__MODULE__{opcional: true}, _contexto), do: {:ok, nil}

  defp vacio(%__MODULE__{} = campo, contexto) do
    {:error,
     diagnostico(campo, contexto,
       esperado: "un valor #{inspect(campo.tipo)}",
       recibido: "un campo en blanco",
       causa_probable:
         "el emisor no envió el dato; declare opcional: true si el campo puede venir vacío"
     )}
  end

  defp solo_digitos?(texto), do: texto != "" and Regex.match?(~r/\A\d+\z/, texto)

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
