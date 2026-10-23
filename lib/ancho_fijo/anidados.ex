defmodule AnchoFijo.Anidados do
  @moduledoc false
  # Leer y escribir los campos anidados: un `:grupo` (OCCURS) y una
  # `:variante` (REDEFINES). Los campos internos tienen posiciones relativas;
  # acá se llevan a absolutas y se leen o escriben con `Campo`, así que el
  # encoding por campo, los sensibles y todo lo demás funcionan igual. Los
  # diagnósticos salen con la ruta del campo interno.

  alias AnchoFijo.Campo
  alias AnchoFijo.Diagnostico

  @type valores :: %{optional(atom()) => term()}

  @doc false
  @spec anidado?(Campo.t()) :: boolean()
  def anidado?(%Campo{tipo: tipo}), do: tipo in [:grupo, :variante]

  # --------------------------------------------------------------- lectura

  @doc false
  # Lee un grupo o una variante desde la línea completa. `valores` son los
  # campos ya leídos del registro, de donde sale el valor de `:segun`.
  @spec leer(Campo.t(), binary(), Campo.contexto(), valores()) ::
          {:ok, term(), [Diagnostico.t()]} | {:error, [Diagnostico.t()]}
  def leer(%Campo{tipo: :grupo} = campo, linea, contexto, _valores) do
    ancho = ancho_de(campo.campos)

    1..(campo.repetir || 1)
    |> Enum.reduce({[], [], []}, fn i, {mapas, advertencias, errores} ->
      base = campo.posicion + (i - 1) * ancho
      ruta = "#{campo.nombre}[#{i}]"

      case leer_campos(campo.campos, base, ruta, linea, contexto) do
        {:ok, mapa, nuevas} -> {[mapa | mapas], advertencias ++ nuevas, errores}
        {:error, nuevos} -> {mapas, advertencias, errores ++ nuevos}
      end
    end)
    |> case do
      {mapas, advertencias, []} -> {:ok, Enum.reverse(mapas), advertencias}
      {_mapas, _advertencias, errores} -> {:error, errores}
    end
  end

  def leer(%Campo{tipo: :variante} = campo, linea, contexto, valores) do
    with {:ok, campos} <- variante_para(campo, Map.get(valores, campo.segun), contexto) do
      leer_campos(campos, campo.posicion, Atom.to_string(campo.nombre), linea, contexto)
    end
  end

  defp leer_campos(campos, base, ruta, linea, contexto) do
    {valores, advertencias, errores} =
      campos
      |> Enum.reject(&Campo.relleno?/1)
      |> Enum.reduce({%{}, [], []}, &leer_interno(&1, base, ruta, linea, contexto, &2))

    case errores do
      [] -> {:ok, valores, advertencias}
      errores -> {:error, errores}
    end
  end

  defp leer_interno(sub, base, ruta, linea, contexto, {valores, advertencias, errores}) do
    case Campo.leer(absoluto(sub, base), linea, contexto) do
      {:ok, valor, nuevas} ->
        {Map.put(valores, sub.nombre, valor), advertencias ++ con_ruta(nuevas, ruta), errores}

      {:error, diagnostico} ->
        {valores, advertencias, errores ++ con_ruta([diagnostico], ruta)}
    end
  end

  # La clave se busca tal cual y, si no está, por su forma de texto: un
  # layout que vino de JSON tiene las claves como strings aunque el campo
  # que elige sea un entero.
  defp variante_para(%Campo{} = campo, valor, contexto) do
    with :error <- Map.fetch(campo.variantes, valor),
         :error <-
           Map.fetch(campo.variantes, if(is_binary(valor), do: valor, else: to_string(valor))) do
      sin_variante(campo, valor, contexto)
    else
      {:ok, campos} -> {:ok, campos}
    end
  end

  defp sin_variante(%Campo{} = campo, valor, contexto) do
    case :error do
      :error ->
        {:error,
         [
           Diagnostico.nuevo(
             tipo: :campo_invalido,
             linea: Map.get(contexto, :linea),
             campo: campo.nombre,
             posicion: Campo.rango(campo),
             esperado:
               "un valor de #{inspect(campo.segun)} con variante declarada: " <>
                 Enum.map_join(Map.keys(campo.variantes), ", ", &inspect/1),
             recibido: inspect(valor),
             causa_probable:
               "el formato trae un #{inspect(campo.segun)} que el layout no contempla, o el campo " <>
                 "que elige la variante no se pudo leer"
           )
         ]}
    end
  end

  # ------------------------------------------------------------- escritura

  @doc false
  # Escribe un grupo o una variante como el texto del ancho del campo.
  @spec escribir(Campo.t(), term(), map(), Campo.contexto()) ::
          {:ok, binary(), [Diagnostico.t()]} | {:error, [Diagnostico.t()]}
  def escribir(%Campo{tipo: :grupo} = campo, valor, _registro, contexto) do
    repetir = campo.repetir || 1

    if is_list(valor) and length(valor) == repetir do
      escribir_repeticiones(campo, valor, contexto)
    else
      {:error,
       [
         diagnostico(campo, contexto,
           esperado: "una lista de #{repetir} mapas, una por repetición del grupo",
           recibido: describir(valor),
           causa_probable:
             "el ancho del grupo es parte del formato: ni una repetición más ni una menos"
         )
       ]}
    end
  end

  def escribir(%Campo{tipo: :variante} = campo, valor, registro, contexto) do
    with {:ok, campos} <- variante_para(campo, Map.get(registro, campo.segun), contexto),
         {:ok, mapa} <- mapa_de_variante(campo, valor, contexto),
         {:ok, texto, advertencias} <-
           escribir_campos(campos, mapa, Atom.to_string(campo.nombre), contexto) do
      {:ok, texto <> String.duplicate(" ", campo.largo - ancho_de(campos)), advertencias}
    end
  end

  defp escribir_repeticiones(%Campo{} = campo, mapas, contexto) do
    mapas
    |> Enum.with_index(1)
    |> Enum.reduce({[], [], []}, fn {mapa, i}, {textos, advertencias, errores} ->
      case escribir_campos(campo.campos, mapa, "#{campo.nombre}[#{i}]", contexto) do
        {:ok, texto, nuevas} -> {[texto | textos], advertencias ++ nuevas, errores}
        {:error, nuevos} -> {textos, advertencias, errores ++ nuevos}
      end
    end)
    |> case do
      {textos, advertencias, []} ->
        {:ok, textos |> Enum.reverse() |> IO.iodata_to_binary(), advertencias}

      {_textos, _advertencias, errores} ->
        {:error, errores}
    end
  end

  defp mapa_de_variante(_campo, mapa, _contexto) when is_map(mapa), do: {:ok, mapa}

  defp mapa_de_variante(campo, otro, contexto) do
    {:error,
     [
       diagnostico(campo, contexto,
         esperado: "un mapa con los campos de la variante",
         recibido: describir(otro),
         causa_probable: "la variante se escribe desde un mapa, como el que devuelve parsear/3"
       )
     ]}
  end

  # Los campos internos se escriben como `Escritor.escribir_linea/4` escribe
  # los de un layout: cada uno en su posición relativa, huecos en blanco.
  defp escribir_campos(campos, mapa, ruta, contexto) do
    {segmentos, cursor, advertencias, errores} =
      Enum.reduce(campos, {[], 1, [], []}, fn sub, {segmentos, cursor, advertencias, errores} ->
        hueco = String.duplicate(" ", sub.posicion - cursor)

        case Campo.formatear(sub, Map.get(mapa, sub.nombre), contexto) do
          {:ok, texto, nuevas} ->
            {[texto, hueco | segmentos], Campo.fin(sub) + 1, advertencias ++ con_ruta(nuevas, ruta),
             errores}

          {:error, diagnostico} ->
            {segmentos, Campo.fin(sub) + 1, advertencias, errores ++ con_ruta([diagnostico], ruta)}
        end
      end)

    case errores do
      [] ->
        relleno_final = String.duplicate(" ", ancho_de(campos) + 1 - cursor)
        {:ok, IO.iodata_to_binary(Enum.reverse([relleno_final | segmentos])), advertencias}

      errores ->
        {:error, errores}
    end
  end

  # ------------------------------------------------------------- comunes

  @doc false
  # El ancho de una lista de campos internos posicionados desde 1.
  @spec ancho_de([Campo.t()]) :: non_neg_integer()
  def ancho_de([]), do: 0
  def ancho_de(campos), do: campos |> Enum.map(&Campo.fin/1) |> Enum.max()

  @doc false
  # El campo interno con su posición absoluta en la línea.
  @spec absoluto(Campo.t(), pos_integer()) :: Campo.t()
  def absoluto(%Campo{} = sub, base), do: %Campo{sub | posicion: base + sub.posicion - 1}

  # La ruta del campo interno en el diagnóstico: `totales[2].importe`,
  # `destino.cuenta`. Un diagnóstico de un campo ya anidado se encadena.
  defp con_ruta(diagnosticos, ruta) do
    Enum.map(diagnosticos, fn %Diagnostico{campo: nombre} = d ->
      %Diagnostico{d | campo: "#{ruta}.#{nombre}"}
    end)
  end

  defp diagnostico(%Campo{} = campo, contexto, atributos) do
    atributos
    |> Keyword.put_new(:tipo, :campo_invalido)
    |> Keyword.merge(
      campo: campo.nombre,
      posicion: Campo.rango(campo),
      linea: Map.get(contexto, :linea)
    )
    |> Diagnostico.nuevo()
  end

  defp describir(valor) when is_list(valor), do: "una lista de #{length(valor)} elementos"
  defp describir(valor), do: AnchoFijo.Entrada.describir(valor)
end
