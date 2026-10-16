defmodule Mix.Tasks.Prompts.Verificar do
  @shortdoc "Verifica que prompts/ sea un registro auditable contra git"

  @moduledoc """
  Verifica que el directorio `prompts/` cumpla su convención y que lo que
  cada archivo declara concuerde con lo que git registró.

      $ mix prompts.verificar
      10 prompts verificados contra git: numeración, frontmatter, fechas, autores, secciones e índice

  Lo que revisa, en orden:

    * la numeración es correlativa desde `0001`, sin saltos ni repetidos, y
      el campo `prompt:` del frontmatter coincide con el nombre del archivo;
    * el frontmatter existe y trae `prompt`, `fecha`, `autor` y `modelo`;
    * `fecha` es el instante del commit que agregó el archivo (`AuthorDate`),
      y el email de `autor` es el del autor de ese commit;
    * las secciones `## Prompt`, `## Resultado` y `## Decisiones tomadas`
      existen;
    * el índice de `prompts/README.md` lista exactamente los archivos que hay,
      en orden.

  Cualquier discrepancia es una falla con código de salida `1`, no una
  advertencia: un registro de auditoría que se contradice a sí mismo es peor
  que no tenerlo. Un archivo que todavía no tiene commit también falla, porque
  no hay nada contra qué verificarlo.

  ## Opciones

    * `--corregir` — reescribe `fecha` y `autor` de cada archivo con los
      valores del commit que lo agregó, y lo informa. Es el paso dos del flujo
      normal: se escribe el prompt, se commitea, se corrige el frontmatter con
      lo que git registró y se commitea la corrección. La fecha verificada es
      la del primer commit; la corrección no la mueve.
    * `--directorio RUTA` — otro directorio en vez de `prompts/`. Existe para
      los tests, que trabajan sobre un repo temporal.

  ## Alcance de la garantía

  Lo que esta tarea prueba es que el frontmatter no contradice a git. Lo que
  git prueba depende de cómo se hicieron los commits: `git commit --date`
  escribe la fecha que uno quiera, y un commit sin firma lleva el nombre y el
  email que uno quiera. La verificación acredita disciplina y buena fe, no
  imposibilidad de falsificación. Ver `prompts/README.md`.
  """

  use Mix.Task

  @directorio_default "prompts"
  @claves_obligatorias ~w(prompt fecha autor modelo)
  @secciones_obligatorias ["## Prompt", "## Resultado", "## Decisiones tomadas"]
  @patron_archivo ~r/^(\d{4})-[a-z0-9-]+\.md$/
  @patron_fila_indice ~r/^\| \[(\d{4})\]\(([^)]+)\) \|/

  @impl Mix.Task
  def run(args) do
    {opts, []} = OptionParser.parse!(args, strict: [directorio: :string, corregir: :boolean])
    directorio = Keyword.get(opts, :directorio, @directorio_default)
    corregir? = Keyword.get(opts, :corregir, false)

    archivos = listar(directorio)

    problemas =
      Enum.concat([
        verificar_numeracion(archivos),
        Enum.flat_map(archivos, &verificar_archivo(directorio, &1, corregir?)),
        verificar_indice(directorio, archivos)
      ])

    informar(problemas, length(archivos))
  end

  defp listar(directorio) do
    directorio
    |> File.ls!()
    |> Enum.filter(&Regex.match?(@patron_archivo, &1))
    |> Enum.sort()
  end

  # ---------------------------------------------------------------- numeración

  defp verificar_numeracion(archivos) do
    numeros = Enum.map(archivos, &numero/1)

    numeros
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {numero, esperado} ->
      if numero == esperado,
        do: [],
        else: ["numeración: se esperaba #{relleno(esperado)}, hay #{relleno(numero)}"]
    end)
    |> Enum.take(1)
    |> Enum.concat(repetidos(numeros))
  end

  defp repetidos(numeros) do
    numeros
    |> Enum.frequencies()
    |> Enum.filter(fn {_numero, veces} -> veces > 1 end)
    |> Enum.map(fn {numero, veces} -> "numeración: #{relleno(numero)} aparece #{veces} veces" end)
  end

  defp numero(archivo) do
    [_todo, digitos] = Regex.run(@patron_archivo, archivo)
    String.to_integer(digitos)
  end

  defp relleno(numero), do: numero |> Integer.to_string() |> String.pad_leading(4, "0")

  # ------------------------------------------------------------------ archivo

  defp verificar_archivo(directorio, archivo, corregir?) do
    ruta = Path.join(directorio, archivo)
    contenido = File.read!(ruta)

    case frontmatter(contenido) do
      {:ok, campos, cuerpo} ->
        Enum.concat([
          verificar_claves(archivo, campos),
          verificar_numero_declarado(archivo, campos),
          verificar_contra_git(directorio, archivo, campos, corregir?),
          verificar_secciones(archivo, cuerpo)
        ])

      :sin_frontmatter ->
        ["#{archivo}: no tiene frontmatter (el bloque entre --- al principio)"]
    end
  end

  defp frontmatter("---\n" <> resto) do
    case String.split(resto, "\n---\n", parts: 2) do
      [bloque, cuerpo] -> {:ok, campos(bloque), cuerpo}
      _otro -> :sin_frontmatter
    end
  end

  defp frontmatter(_contenido), do: :sin_frontmatter

  defp campos(bloque) do
    bloque
    |> String.split("\n", trim: true)
    |> Enum.flat_map(fn linea ->
      case String.split(linea, ": ", parts: 2) do
        [clave, valor] -> [{String.trim(clave), String.trim(valor)}]
        _otro -> []
      end
    end)
    |> Map.new()
  end

  defp verificar_claves(archivo, campos) do
    @claves_obligatorias
    |> Enum.reject(&Map.has_key?(campos, &1))
    |> Enum.map(&"#{archivo}: falta #{&1}: en el frontmatter")
  end

  defp verificar_numero_declarado(archivo, %{"prompt" => declarado}) do
    if declarado == relleno(numero(archivo)),
      do: [],
      else: [
        "#{archivo}: el frontmatter dice prompt: #{declarado} y el archivo es #{relleno(numero(archivo))}"
      ]
  end

  defp verificar_numero_declarado(_archivo, _campos), do: []

  defp verificar_secciones(archivo, cuerpo) do
    lineas = String.split(cuerpo, "\n")

    @secciones_obligatorias
    |> Enum.reject(&(&1 in lineas))
    |> Enum.map(&"#{archivo}: falta la sección #{&1}")
  end

  # ---------------------------------------------------------------------- git

  defp verificar_contra_git(directorio, archivo, campos, corregir?) do
    case commit_que_agrego(directorio, archivo) do
      {:ok, commit} ->
        problemas =
          verificar_fecha(archivo, campos, commit) ++ verificar_autor(archivo, campos, commit)

        if corregir? and problemas != [], do: corregir(directorio, archivo, commit), else: problemas

      :sin_commit ->
        ["#{archivo}: no tiene commit todavía; la fecha y el autor no se pueden verificar"]
    end
  end

  # `--diff-filter=A` lista los commits que agregaron el archivo, del más nuevo
  # al más viejo; si alguna vez se borró y se volvió a agregar, el que vale es
  # el primero de la historia, o sea el último de la lista. `%aI` es la fecha
  # de autoría, que un merge o un rebase conservan; la de commit no.
  defp commit_que_agrego(directorio, archivo) do
    args = [
      "-C",
      directorio,
      "log",
      "--diff-filter=A",
      "--format=%H%x1f%aI%x1f%an%x1f%ae",
      "--",
      archivo
    ]

    case System.cmd("git", args, stderr_to_stdout: true) do
      {salida, 0} ->
        salida
        |> String.split("\n", trim: true)
        |> List.last()
        |> case do
          nil ->
            :sin_commit

          linea ->
            [hash, fecha, nombre, email] = String.split(linea, <<0x1F>>)
            {:ok, %{hash: String.slice(hash, 0, 7), fecha: fecha, nombre: nombre, email: email}}
        end

      {salida, _codigo} ->
        Mix.raise("no se pudo consultar git en #{directorio}: " <> String.trim(salida))
    end
  end

  # Se comparan instantes, no textos: `2026-08-06T17:42:34-04:00` y su
  # equivalente en otro huso son la misma fecha. El huso es presentación.
  defp verificar_fecha(archivo, %{"fecha" => declarada}, commit) do
    with {:ok, instante_declarado, _offset} <- DateTime.from_iso8601(declarada),
         {:ok, instante_commit, _offset} <- DateTime.from_iso8601(commit.fecha),
         :eq <- DateTime.compare(instante_declarado, instante_commit) do
      []
    else
      {:error, _motivo} ->
        ["#{archivo}: fecha: #{declarada} no es una fecha ISO 8601 con huso horario"]

      _distinta ->
        [
          "#{archivo}: fecha: #{declarada} no coincide con el commit #{commit.hash} (#{commit.fecha})"
        ]
    end
  end

  defp verificar_fecha(_archivo, _campos, _commit), do: []

  # El email es lo verificable; el nombre es presentación y puede llevar o no
  # tildes según cómo estuviera configurado git ese día.
  defp verificar_autor(archivo, %{"autor" => declarado}, commit) do
    case Regex.run(~r/<([^>]+)>\s*$/, declarado) do
      [_todo, email] ->
        if String.downcase(email) == String.downcase(commit.email),
          do: [],
          else: [
            "#{archivo}: autor: #{email} no es el autor del commit #{commit.hash} (#{commit.email})"
          ]

      nil ->
        ["#{archivo}: autor: #{declarado} no tiene la forma Nombre <email>"]
    end
  end

  defp verificar_autor(_archivo, _campos, _commit), do: []

  defp corregir(directorio, archivo, commit) do
    ruta = Path.join(directorio, archivo)

    corregido =
      ruta
      |> File.read!()
      |> String.replace(~r/^fecha: .*$/m, "fecha: #{commit.fecha}", global: false)
      |> String.replace(~r/^autor: .*$/m, "autor: #{commit.nombre} <#{commit.email}>",
        global: false
      )

    File.write!(ruta, corregido)
    Mix.shell().info("#{archivo}: fecha y autor corregidos con el commit #{commit.hash}")
    []
  end

  # ------------------------------------------------------------------- índice

  defp verificar_indice(directorio, archivos) do
    readme = Path.join(directorio, "README.md")
    esperadas = Enum.map(archivos, &{relleno(numero(&1)), &1})

    case filas_del_indice(readme) do
      :sin_readme -> ["README.md: no existe; el índice de prompts vive ahí"]
      ^esperadas -> []
      filas -> diferencias_de_indice(filas, esperadas)
    end
  end

  defp filas_del_indice(readme) do
    if File.exists?(readme) do
      readme |> File.read!() |> String.split("\n") |> Enum.flat_map(&fila_del_indice/1)
    else
      :sin_readme
    end
  end

  defp fila_del_indice(linea) do
    case Regex.run(@patron_fila_indice, linea) do
      [_todo, numero, enlace] -> [{numero, enlace}]
      nil -> []
    end
  end

  defp diferencias_de_indice(filas, esperadas) do
    faltan = esperadas -- filas
    sobran = filas -- esperadas

    Enum.map(faltan, fn {_numero, archivo} -> "README.md: el índice no lista #{archivo}" end) ++
      Enum.map(sobran, fn {numero, enlace} ->
        "README.md: el índice lista #{numero} -> #{enlace}, que no corresponde a ningún archivo"
      end) ++
      if faltan == [] and sobran == [],
        do: ["README.md: el índice no está en el orden de los archivos"],
        else: []
  end

  # ------------------------------------------------------------------ informe

  defp informar([], cuantos) do
    Mix.shell().info(
      "#{cuantos} prompts verificados contra git: numeración, frontmatter, fechas, autores, " <>
        "secciones e índice"
    )
  end

  defp informar(problemas, _cuantos) do
    Enum.each(problemas, &Mix.shell().error("  - " <> &1))
    fallar("#{length(problemas)} problema(s) en prompts/")
  end

  @spec fallar(String.t()) :: no_return()
  defp fallar(mensaje) do
    Mix.shell().error(mensaje)
    exit({:shutdown, 1})
  end
end
