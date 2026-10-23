defmodule AnchoFijo.Tipo do
  @moduledoc """
  El behaviour de los tipos de campo. Los tipos de la librería (`:texto`,
  `:entero`, `:decimal`, `:fecha`, `:hora`, `:fecha_hora`, `:rut`,
  `:constante`, `:relleno`) lo implementan, y un tipo propio se agrega sin
  tocar la librería: un módulo con tres funciones y `tipo: MiApp.Hora` en
  el layout.

  ## Un tipo completo

  Una hora `HHMM` que se lee como `Time`, con una opción propia:

      defmodule MiApp.Hora do
        @behaviour AnchoFijo.Tipo

        alias AnchoFijo.Tipo

        @impl true
        def opciones, do: [:segundos]

        @impl true
        def validar(campo) do
          cond do
            campo.largo not in [4, 6] ->
              [Tipo.falla(campo, "un :largo de 4 (HHMM) o 6 (HHMMSS)", campo.largo, nil)]

            not is_boolean(Map.get(campo.opciones, :segundos, false)) ->
              [Tipo.falla(campo, ":segundos true o false", campo.opciones.segundos, nil)]

            true ->
              []
          end
        end

        @impl true
        def leer("", campo, contexto), do: {:error, Tipo.vacio(campo, contexto)}

        def leer(texto, campo, contexto) do
          with {hora, ""} <- Integer.parse(binary_part(texto, 0, 2)),
               {minuto, ""} <- Integer.parse(binary_part(texto, 2, 2)),
               {:ok, time} <- Time.new(hora, minuto, 0) do
            {:ok, time}
          else
            _ ->
              {:error,
               Tipo.diagnostico(campo, contexto,
                 esperado: "una hora HHMM",
                 recibido: inspect(texto),
                 causa_probable: "hay caracteres no numéricos o la hora no existe"
               )}
          end
        end
      end

  Y en el layout:

      [nombre: :hora_pago, largo: 4, tipo: MiApp.Hora]

  Los diagnósticos que produce son indistinguibles de los internos: `Tipo.diagnostico/3`
  les pone el campo, las posiciones y la línea, igual que a los demás.

  ## Los callbacks

    * `c:opciones/0` — las opciones propias del tipo, además de las comunes
      (`:nombre`, `:largo`, `:posicion`, `:opcional`, `:trim`, `:relleno`).
      Una opción que no es común ni está acá es un error del layout: así un
      `precison: 2` mal escrito no pasa en silencio. Los valores llegan en
      `campo.opciones`.
    * `c:validar/1` — al construir el layout, no al parsear. Devuelve una
      lista de diagnósticos, vacía si la definición está bien. Es lo que
      permite que un `:fecha` sin `:formato` siga siendo un layout inválido.
    * `c:leer/3` — convierte el texto del campo en el valor. Recibe el texto
      ya recortado (`String.trim/1`; el tipo `:texto` tiene su propio `:trim`),
      el campo y el contexto de lectura. Un campo en blanco con
      `opcional: true` se resuelve antes y nunca llega acá; sin `:opcional`,
      llega `""` y el tipo decide (lo usual es `Tipo.vacio/2`).
    * `c:escribir/2` — opcional: serializa el valor al ancho del campo, para
      `AnchoFijo.escribir/3`. Un tipo sin `escribir/2` se lee pero no se
      escribe, y `AnchoFijo.Campo.formatear/3` lo dice como diagnóstico.

  ## Cuándo se verifica que el módulo implementa el behaviour

  Al construir el layout, no al parsear: `Code.ensure_loaded?/1` más
  `function_exported?/3` sobre los tres callbacks obligatorios. Un módulo que
  no existe o no los implementa es un diagnóstico `:layout`, no un
  `UndefinedFunctionError` en la línea 40.000. `ensure_loaded?` importa: en
  un release los módulos se cargan recién cuando se usan, y
  `function_exported?/3` a secas diría `false` para un módulo perfectamente
  válido que todavía nadie llamó.
  """

  alias AnchoFijo.Campo
  alias AnchoFijo.Diagnostico

  @doc "Las opciones propias del tipo, además de las comunes a todos los campos."
  @callback opciones() :: [atom()]

  @doc "Valida la definición del campo al construir el layout. Vacía si está bien."
  @callback validar(campo :: Campo.t()) :: [Diagnostico.t()]

  @doc "Convierte el texto del campo, ya recortado, en el valor."
  @callback leer(texto :: String.t(), campo :: Campo.t(), contexto :: Campo.contexto()) ::
              {:ok, term()} | {:error, Diagnostico.t()}

  @doc "Serializa un valor al ancho del campo. Opcional, para la escritura."
  @callback escribir(valor :: term(), campo :: Campo.t()) :: {:ok, binary()} | {:error, String.t()}

  @optional_callbacks escribir: 2

  # Keyword list y no mapa: el orden es el de la documentación y el de los
  # mensajes de error.
  @internos [
    texto: AnchoFijo.Tipo.Texto,
    entero: AnchoFijo.Tipo.Entero,
    decimal: AnchoFijo.Tipo.Decimal,
    fecha: AnchoFijo.Tipo.Fecha,
    hora: AnchoFijo.Tipo.Hora,
    fecha_hora: AnchoFijo.Tipo.FechaHora,
    rut: AnchoFijo.Tipo.Rut,
    constante: AnchoFijo.Tipo.Constante,
    relleno: AnchoFijo.Tipo.Relleno
  ]

  @doc "Los tipos internos, por su átomo, en el orden de la documentación."
  @spec internos() :: keyword(module())
  def internos, do: @internos

  @doc "Si el módulo es uno de los tipos internos."
  @spec interno?(module()) :: boolean()
  def interno?(modulo), do: modulo in Keyword.values(@internos)

  @doc """
  Resuelve el `:tipo` de una definición al módulo que lo implementa.

      iex> AnchoFijo.Tipo.resolver(:entero)
      {:ok, AnchoFijo.Tipo.Entero}
      iex> AnchoFijo.Tipo.resolver(AnchoFijo.Tipo.Fecha)
      {:ok, AnchoFijo.Tipo.Fecha}
      iex> AnchoFijo.Tipo.resolver(:fechas)
      {:error, "un :tipo en [:texto, :entero, :decimal, :fecha, :hora, :fecha_hora, :rut, :constante, :relleno] o un módulo que implemente AnchoFijo.Tipo"}
      iex> AnchoFijo.Tipo.resolver(Enum)
      {:error, "un módulo que implemente AnchoFijo.Tipo; Enum no implementa opciones/0, validar/1 y leer/3"}
  """
  @spec resolver(term()) :: {:ok, module()} | {:error, String.t()}
  def resolver(modulo) when is_atom(modulo) and not is_nil(modulo) do
    cond do
      Keyword.has_key?(@internos, modulo) ->
        {:ok, Keyword.fetch!(@internos, modulo)}

      not candidato_a_modulo?(modulo) ->
        {:error, descripcion_de_tipos()}

      not Code.ensure_loaded?(modulo) ->
        {:error, "un módulo que implemente AnchoFijo.Tipo; #{inspect(modulo)} no existe"}

      not implementa?(modulo) ->
        {:error,
         "un módulo que implemente AnchoFijo.Tipo; #{inspect(modulo)} no implementa " <>
           "opciones/0, validar/1 y leer/3"}

      true ->
        {:ok, modulo}
    end
  end

  def resolver(_otro), do: {:error, descripcion_de_tipos()}

  # Un átomo con mayúscula inicial es un alias de módulo; `:hora` no lo es y
  # el mensaje tiene que listar los tipos, no decir que no existe.
  defp candidato_a_modulo?(modulo), do: String.starts_with?(Atom.to_string(modulo), "Elixir.")

  defp implementa?(modulo) do
    function_exported?(modulo, :opciones, 0) and function_exported?(modulo, :validar, 1) and
      function_exported?(modulo, :leer, 3)
  end

  defp descripcion_de_tipos do
    "un :tipo en #{inspect(Keyword.keys(@internos))} o un módulo que implemente AnchoFijo.Tipo"
  end

  @doc """
  Un diagnóstico de lectura con el campo, las posiciones y la línea puestos.

  Es lo que usan los tipos internos; un tipo propio que lo use produce
  diagnósticos indistinguibles. `tipo:` es `:campo_invalido` salvo que se
  diga otra cosa.
  """
  @spec diagnostico(Campo.t(), Campo.contexto(), keyword()) :: Diagnostico.t()
  def diagnostico(%Campo{} = campo, contexto, atributos) do
    atributos
    |> Keyword.put_new(:tipo, :campo_invalido)
    |> Keyword.merge(
      campo: campo.nombre,
      posicion: Campo.rango(campo),
      linea: Map.get(contexto, :linea)
    )
    |> Diagnostico.nuevo()
  end

  @doc """
  El diagnóstico estándar para un campo en blanco que no es opcional.
  """
  @spec vacio(Campo.t(), Campo.contexto()) :: Diagnostico.t()
  def vacio(%Campo{} = campo, contexto) do
    diagnostico(campo, contexto,
      esperado: "un valor #{inspect(campo.tipo)}",
      recibido: "un campo en blanco",
      causa_probable:
        "el emisor no envió el dato; declare opcional: true si el campo puede venir vacío"
    )
  end

  @doc """
  Un diagnóstico de layout sobre la definición del campo, para `c:validar/1`.
  """
  @spec falla(Campo.t(), String.t(), term(), String.t() | nil) :: Diagnostico.t()
  def falla(%Campo{nombre: nombre}, esperado, recibido, causa) do
    Diagnostico.nuevo(
      tipo: :layout,
      campo: nombre,
      esperado: esperado,
      recibido: recibido,
      causa_probable: causa
    )
  end

  @doc """
  Si el texto es uno o más dígitos ASCII y nada más.

  Un recorrido de bytes y no un regex: se llama dos o tres veces por campo
  numérico y el regex costaba más que todo el resto de la conversión.
  """
  @spec solo_digitos?(String.t()) :: boolean()
  def solo_digitos?(""), do: false
  def solo_digitos?(texto), do: digitos?(texto)

  defp digitos?(<<byte, resto::binary>>) when byte in ?0..?9, do: digitos?(resto)
  defp digitos?(""), do: true
  defp digitos?(_otro), do: false
end
