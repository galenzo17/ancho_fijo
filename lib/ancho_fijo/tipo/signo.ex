defmodule AnchoFijo.Tipo.Signo do
  @moduledoc false
  # El signo de los tipos numéricos, compartido por :entero y :decimal.
  # Separa el signo de los dígitos según dónde lo declara el layout y, cuando
  # está donde no debería, dice por qué: ahí el dato no es ilegible, es de
  # otro formato, y el diagnóstico tiene que decirlo en vez de reportar
  # "caracteres no numéricos".

  alias AnchoFijo.Campo
  alias AnchoFijo.Tipo

  @valores [:inicial, :final]

  @spec valores() :: [atom()]
  def valores, do: @valores

  @spec validar(Campo.t()) :: [AnchoFijo.Diagnostico.t()]
  def validar(%Campo{signo: signo}) when signo in @valores, do: []

  def validar(%Campo{signo: signo} = campo) do
    [Tipo.falla(campo, ":signo en #{inspect(@valores)}", signo, nil)]
  end

  @spec separar(String.t(), Campo.t()) :: {:ok, 1 | -1, String.t()} | {:error, String.t()}
  def separar(texto, %Campo{signo: :inicial}) do
    {signo, resto} =
      case texto do
        "-" <> resto -> {-1, resto}
        "+" <> resto -> {1, resto}
        resto -> {1, resto}
      end

    if al_final?(resto) do
      {:error,
       "el signo viene al final del campo; si el formato es heredado de mainframe, " <>
         "declare signo: :final"}
    else
      {:ok, signo, resto}
    end
  end

  # Los formatos de mainframe escriben `0125000-` para -1.250,00 y `0125000 `
  # para el positivo: el espacio ya se lo llevó el recorte, así que un campo
  # sin signo es positivo. El `+` explícito también se acepta porque algunos
  # emisores lo mandan y rechazarlo no protege de nada.
  def separar(texto, %Campo{signo: :final}) do
    {signo, resto} = quitar_final(texto)

    case causa_final(texto, resto) do
      nil -> {:ok, signo, resto}
      causa -> {:error, causa}
    end
  end

  defp quitar_final(texto) do
    case String.last(texto) do
      "-" -> {-1, String.slice(texto, 0..-2//1)}
      "+" -> {1, String.slice(texto, 0..-2//1)}
      _digito -> {1, texto}
    end
  end

  defp causa_final(texto, resto) do
    cond do
      resto == "" ->
        "el campo trae solo el signo, sin dígitos"

      String.starts_with?(resto, ["-", "+"]) and al_final?(texto) ->
        "hay un signo en cada extremo del campo; el archivo no respeta el formato declarado"

      String.starts_with?(resto, ["-", "+"]) ->
        "el signo viene antes de los dígitos; si el formato no es heredado de mainframe, " <>
          "declare signo: :inicial"

      al_final?(resto) ->
        "el signo viene duplicado al final del campo"

      true ->
        nil
    end
  end

  defp al_final?(texto), do: String.ends_with?(texto, ["-", "+"])

  @spec error(Campo.t(), String.t(), String.t(), Campo.contexto()) :: AnchoFijo.Diagnostico.t()
  def error(%Campo{} = campo, texto, causa, contexto) do
    Tipo.diagnostico(campo, contexto,
      esperado: descripcion(campo.signo),
      recibido: inspect(texto),
      causa_probable: causa
    )
  end

  defp descripcion(:inicial), do: "el signo antes de los dígitos, como -1250"
  defp descripcion(:final), do: "el signo después de los dígitos, como 1250-"
end
