defmodule AnchoFijo do
  @moduledoc """
  Lectura de archivos de ancho fijo que empieza por desconfiar del archivo.

  El problema de una integración bancaria no es parsear ancho fijo: son treinta
  líneas de `binary_part`. El problema es que el archivo real nunca calza con el
  formato que el cliente declaró. El anexo dice 120 posiciones y llegan 118. Dice
  UTF-8 y viene latin-1. Dice ancho fijo y en realidad es un CSV que alguien
  exportó de Excel. Eso se descubre siempre tarde: después de escribir el parser.

  Por eso la primera función de esta librería no parsea, interroga:

      iex> {:ok, reporte} = AnchoFijo.detectar("nombre;monto\\nJUAN;1000\\nANA;25000\\n")
      iex> reporte.probablemente_ancho_fijo?
      false
      iex> List.last(reporte.observaciones)
      "el carácter \\";\\" aparece 1 vez en todas las líneas y en posiciones variables: esto parece un archivo delimitado, no de ancho fijo"

  Cuando el archivo sí es lo que dijeron, el layout es data y el parseo es una
  llamada:

      iex> layout = AnchoFijo.Layout.nuevo!(
      ...>   nombre: "nómina de pagos",
      ...>   campos: [
      ...>     [nombre: :rut, largo: 10],
      ...>     [nombre: :beneficiario, largo: 12],
      ...>     [nombre: :monto, largo: 8, tipo: :decimal, precision: 2],
      ...>     [nombre: :fecha_pago, largo: 8, tipo: :fecha, formato: :aaaammdd]
      ...>   ]
      ...> )
      iex> AnchoFijo.parsear(layout, "12345678-9JUAN PEREZ  0012345620240131\\n")
      {:ok, [%{rut: "12345678-9", beneficiario: "JUAN PEREZ", monto: {123456, 2}, fecha_pago: ~D[2024-01-31]}], []}

  Y cuando no lo es, el error dice qué pasó:

      iex> layout = AnchoFijo.Layout.nuevo!(campos: [[nombre: :rut, largo: 10], [nombre: :nombre, largo: 12]])
      iex> {:error, [diagnostico]} = AnchoFijo.parsear(layout, "12345678-9JUAN PEREZ\\n")
      iex> AnchoFijo.Diagnostico.mensaje(diagnostico)
      "línea 1: se esperaban 22 bytes, llegaron 20; posible campo faltante o archivo delimitado"

  ## Las cuatro funciones

  | función | para qué |
  | --- | --- |
  | `detectar/2` | interrogar el archivo antes de escribir el layout |
  | `parsear/3` | leer un archivo completo, estricto o tolerante |
  | `stream/3` | leer un archivo grande de forma lazy |
  | `escribir/3` | generar un archivo con el mismo layout |
  | `AnchoFijo.Layout.nuevo/1` | definir y validar el formato |

  `detectar!/2`, `parsear!/3` y `AnchoFijo.Layout.nuevo!/1` son las mismas
  con la convención de la stdlib: devuelven el valor o levantan
  `AnchoFijo.Error`.

  ## Montos

  Un `:decimal` se devuelve como `{unidades, precision}`: `{123456, 2}` es
  `1234,56`. Nunca hay un float en el camino, porque un monto que pasó por punto
  flotante deja de cuadrar con la contabilidad del banco y nadie sabe dónde se
  perdió el peso.

  ## Errores

  Toda falla es un `AnchoFijo.Diagnostico` con línea, campo, qué se esperaba, qué
  llegó y una causa probable. No existe `{:error, :invalid}` en este paquete.

  `parsear/3` devuelve siempre `{:ok, registros, diagnosticos}`: la tercera
  posición trae los errores de las filas que no se pudieron leer y las
  advertencias de las que sí, pero asumiendo algo. `Diagnostico.separar/1` las
  parte en dos.

  Lo único que la librería levanta por sí misma es `AnchoFijo.Error`, desde las
  funciones con `!`, y `ArgumentError` cuando la llamada está mal hecha: una
  opción que no existe, un valor de otro tipo. Ver `AnchoFijo.Error`.

  ## Alcance de 0.1

  Sin multiregistro (header/detalle/trailer): ver el `CHANGELOG.md`.
  """

  alias AnchoFijo.Detector
  alias AnchoFijo.Diagnostico
  alias AnchoFijo.Escritor
  alias AnchoFijo.Layout
  alias AnchoFijo.Parser
  alias AnchoFijo.Traza

  @doc """
  Interroga una muestra —binario o ruta— y devuelve un reporte del archivo.

  Responde "¿esto es realmente lo que me dijeron que es?": largos de línea y su
  consistencia, encoding probable, terminadores y presencia de delimitadores que
  sugieran que el archivo no es de ancho fijo. Ver `AnchoFijo.Detector` para el
  detalle del reporte y las opciones.

      iex> {:ok, reporte} = AnchoFijo.detectar("ABC1234567\\nDEF7654321\\n")
      iex> {reporte.largo_consistente?, reporte.largo_predominante, reporte.encoding_probable}
      {true, 10, :ascii}

  Con un layout, además contrasta lo declarado contra lo encontrado:

      iex> layout = AnchoFijo.Layout.nuevo!(campos: [[nombre: :todo, largo: 12]])
      iex> {:ok, reporte} = AnchoFijo.detectar("ABC1234567\\nDEF7654321\\n", layout: layout)
      iex> List.last(reporte.observaciones)
      "entrada: se esperaba un largo de línea de 12 bytes según el layout, llegó 10; el archivo tiene 2 bytes menos por línea: falta un campo, o el layout es de otra versión del formato"
  """
  @spec detectar(term(), keyword()) :: {:ok, Detector.reporte()} | {:error, [Diagnostico.t()]}
  defdelegate detectar(entrada, opts \\ []), to: Detector

  @doc """
  Igual que `detectar/2`, pero devuelve el reporte o levanta `AnchoFijo.Error`.

      iex> AnchoFijo.detectar!("ABC1234567\\nDEF7654321\\n").largo_predominante
      10

  Ver `AnchoFijo.Detector.detectar!/2`.
  """
  @spec detectar!(term(), keyword()) :: Detector.reporte()
  defdelegate detectar!(entrada, opts \\ []), to: Detector

  @doc """
  Parsea un archivo completo según un layout.

  `entrada` puede ser el contenido, una ruta a un archivo, o cualquiera de los
  dos desambiguado con `desde: :archivo | :contenido`. El layout puede venir ya
  construido o como definición en línea.

      iex> AnchoFijo.parsear(
      ...>   [campos: [[nombre: :moneda, largo: 3], [nombre: :saldo, largo: 8, tipo: :decimal, precision: 2]]],
      ...>   "CLP00123456\\n"
      ...> )
      {:ok, [%{moneda: "CLP", saldo: {123456, 2}}], []}

  En modo `:tolerante` la tercera posición trae los diagnósticos de las filas
  que no se pudieron leer, y las buenas siguen en la primera.

      iex> layout = AnchoFijo.Layout.nuevo!(campos: [[nombre: :codigo, largo: 3, tipo: :entero]])
      iex> {:ok, registros, [diagnostico]} = AnchoFijo.parsear(layout, "001\\nAB2\\n003\\n", modo: :tolerante)
      iex> registros
      [%{codigo: 1}, %{codigo: 3}]
      iex> AnchoFijo.Diagnostico.mensaje(diagnostico)
      "línea 2, campo :codigo (posiciones 1-3): se esperaban 3 posiciones con un número entero, llegaron \\"AB2\\"; hay caracteres no numéricos o el campo está corrido"

  Ver `AnchoFijo.Parser` para las opciones y la diferencia entre los modos.
  """
  @spec parsear(Layout.t() | Enumerable.t(), term(), keyword()) :: Parser.resultado()
  defdelegate parsear(layout, entrada, opts \\ []), to: Parser

  @doc """
  Igual que `parsear/3`, pero devuelve solo los registros o levanta `AnchoFijo.Error`.

  Para el script o el `Mix.Task` donde un archivo malo no deja nada que hacer
  salvo morir con un mensaje claro. En modo `:tolerante` levanta igual si hay
  filas malas, pero con todos los errores adentro, no solo el primero. Las
  advertencias no se devuelven: si importan, use `parsear/3`.

      iex> AnchoFijo.parsear!([campos: [[nombre: :moneda, largo: 3]]], "CLP\\nUSD\\n")
      [%{moneda: "CLP"}, %{moneda: "USD"}]

      iex> AnchoFijo.parsear!([campos: [[nombre: :codigo, largo: 3, tipo: :entero]]], "001\\nAB2\\n")
      ** (AnchoFijo.Error) línea 2, campo :codigo (posiciones 1-3): se esperaban 3 posiciones con un número entero, llegaron "AB2"; hay caracteres no numéricos o el campo está corrido

  Ver `AnchoFijo.Parser.parsear!/3`.
  """
  @spec parsear!(Layout.t() | Enumerable.t(), term(), keyword()) :: [Parser.registro()]
  defdelegate parsear!(layout, entrada, opts \\ []), to: Parser

  @doc """
  Igual que `parsear/3` pero lazy, para archivos que no caben en memoria.

  Devuelve un `Stream` de `{:ok, registro, advertencias}` o
  `{:error, diagnosticos}`, un elemento por línea con contenido.

      iex> layout = AnchoFijo.Layout.nuevo!(campos: [[nombre: :codigo, largo: 3, tipo: :entero]])
      iex> AnchoFijo.stream(layout, "001\\n002\\n003\\n") |> Enum.take(2)
      [{:ok, %{codigo: 1}, []}, {:ok, %{codigo: 2}, []}]

  Acepta un `File.Stream` construido por el llamador, que es la forma de leer un
  archivo de gigabytes sin cargarlo:

      "cartola.txt"
      |> File.stream!()
      |> then(&AnchoFijo.stream(layout, &1))
      |> Stream.filter(&match?({:ok, _, _}, &1))
      |> Enum.count()

  Ver `AnchoFijo.Parser.stream/3` para el detalle.
  """
  @spec stream(Layout.t() | Enumerable.t(), term(), keyword()) :: Enumerable.t()
  defdelegate stream(layout, entrada, opts \\ []), to: Parser

  @doc """
  Huella SHA-256 del lote, estable entre corridas e insensible al estilo de
  terminador de línea. Ver `AnchoFijo.Traza.huella/2`.

      iex> {:ok, "sha256:" <> _hex} = AnchoFijo.huella("001\\n002\\n")
  """
  @spec huella(term(), keyword()) :: {:ok, String.t()} | {:error, [Diagnostico.t()]}
  defdelegate huella(entrada, opts \\ []), to: Traza

  @doc """
  Escribe registros con el mismo layout que los lee: el inverso de `parsear/3`.

      iex> layout = [campos: [[nombre: :codigo, largo: 3, tipo: :entero], [nombre: :glosa, largo: 5]]]
      iex> AnchoFijo.escribir(layout, [%{codigo: 7, glosa: "ab"}, %{codigo: 42, glosa: "cde"}])
      {:ok, "007ab   \\n042cde  \\n", []}

  Todo o nada: si algún valor no se puede escribir, devuelve todos los
  diagnósticos. Ver `AnchoFijo.Escritor`, y `AnchoFijo.Escritor.stream/3`
  para la versión lazy.
  """
  @spec escribir(Layout.t() | Enumerable.t(), Enumerable.t(), keyword()) ::
          {:ok, binary(), [Diagnostico.t()]} | {:error, [Diagnostico.t()]}
  defdelegate escribir(layout, registros, opts \\ []), to: Escritor
end
