defmodule Mix.Tasks.Prompts.VerificarTest do
  # No es async: `Mix.shell/1` es global.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  @tarea "prompts.verificar"
  @autor {"Ana Prueba", "ana@example.com"}

  setup do
    shell = Mix.shell()
    Mix.shell(Mix.Shell.IO)
    on_exit(fn -> Mix.shell(shell) end)

    repo = Path.join(System.tmp_dir!(), "prompts_repo_#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(repo, "prompts"))
    git!(repo, ["init", "-q", "-b", "main"])
    on_exit(fn -> File.rm_rf!(repo) end)

    {:ok, repo: repo, prompts: Path.join(repo, "prompts")}
  end

  # ------------------------------------------------------------------ helpers

  defp git!(repo, args, env \\ []) do
    base = [
      "-C",
      repo,
      "-c",
      "commit.gpgsign=false",
      "-c",
      "user.name=Git Config",
      "-c",
      "user.email=config@example.com"
    ]

    {salida, 0} = System.cmd("git", base ++ args, env: env, stderr_to_stdout: true)
    salida
  end

  # Escribe un prompt con frontmatter y las secciones obligatorias. La fecha
  # del frontmatter es la que después se usa como fecha de autoría del commit,
  # así que por default concuerdan.
  defp escribir_prompt(prompts, numero, opts \\ []) do
    {nombre, email} = Keyword.get(opts, :autor, @autor)
    fecha = Keyword.get(opts, :fecha, "2026-01-0#{numero}T10:00:00-03:00")
    archivo = "000#{numero}-prompt-#{numero}.md"

    frontmatter =
      if Keyword.get(opts, :frontmatter, true) do
        campos =
          [prompt: "000#{numero}", fecha: fecha, autor: "#{nombre} <#{email}>", modelo: "modelo-x"]
          |> Keyword.drop(Keyword.get(opts, :sin, []))
          |> Enum.map_join("\n", fn {clave, valor} -> "#{clave}: #{valor}" end)

        "---\n#{campos}\n---\n\n"
      else
        ""
      end

    secciones =
      ["## Prompt\n\n> algo\n", "## Resultado\n\n- algo\n", "## Decisiones tomadas\n\n1. algo\n"]
      |> Enum.reject(&String.starts_with?(&1, Keyword.get(opts, :sin_seccion, "\0")))
      |> Enum.join("\n")

    File.write!(
      Path.join(prompts, archivo),
      frontmatter <> "# 000#{numero} — Prompt #{numero}\n\n" <> secciones
    )

    archivo
  end

  defp escribir_indice(prompts, archivos) do
    filas =
      Enum.map_join(archivos, "\n", fn archivo ->
        "| [#{String.slice(archivo, 0, 4)}](#{archivo}) | x | y |"
      end)

    File.write!(
      Path.join(prompts, "README.md"),
      "# Prompts\n\n| # | Prompt | Resultado |\n| --- | --- | --- |\n#{filas}\n"
    )
  end

  defp commitear(repo, mensaje, opts \\ []) do
    {nombre, email} = Keyword.get(opts, :autor, @autor)
    fecha = Keyword.get(opts, :fecha, "2026-01-01T10:00:00-03:00")
    git!(repo, ["add", "-A"])

    git!(repo, ["commit", "-q", "-m", mensaje], [
      {"GIT_AUTHOR_NAME", nombre},
      {"GIT_AUTHOR_DATE", fecha},
      {"GIT_AUTHOR_EMAIL", email}
    ])
  end

  # Un repo con dos prompts correctos, cada uno en su commit con su fecha.
  defp repo_sano(%{repo: repo, prompts: prompts}) do
    a1 = escribir_prompt(prompts, 1)
    escribir_indice(prompts, [a1])
    commitear(repo, "prompt 1", fecha: "2026-01-01T10:00:00-03:00")
    a2 = escribir_prompt(prompts, 2)
    escribir_indice(prompts, [a1, a2])
    commitear(repo, "prompt 2", fecha: "2026-01-02T10:00:00-03:00")
    [a1, a2]
  end

  defp correr(prompts, extra \\ []) do
    padre = self()

    salida =
      capture_io(fn ->
        errores =
          capture_io(:stderr, fn ->
            codigo =
              try do
                Mix.Task.rerun(@tarea, ["--directorio", prompts | extra])
                0
              catch
                :exit, {:shutdown, codigo} -> codigo
              end

            send(padre, {:codigo, codigo})
          end)

        send(padre, {:stderr, errores})
      end)

    assert_received {:codigo, codigo}
    assert_received {:stderr, errores}
    {codigo, salida, errores}
  end

  # -------------------------------------------------------------------- tests

  test "un directorio sano pasa con código 0", ctx do
    repo_sano(ctx)

    assert {0, salida, ""} = correr(ctx.prompts)
    assert salida =~ "2 prompts verificados contra git"
  end

  test "dos prompts en el mismo commit son válidos: comparten fecha", %{
    repo: repo,
    prompts: prompts
  } do
    a1 = escribir_prompt(prompts, 1, fecha: "2026-03-03T09:00:00+00:00")
    a2 = escribir_prompt(prompts, 2, fecha: "2026-03-03T09:00:00+00:00")
    escribir_indice(prompts, [a1, a2])
    commitear(repo, "dos prompts", fecha: "2026-03-03T09:00:00+00:00")

    assert {0, _salida, ""} = correr(prompts)
  end

  test "la fecha se compara como instante: otro huso horario del mismo momento pasa", ctx do
    [a1 | _] = repo_sano(ctx)
    reescribir_campo(ctx.prompts, a1, "fecha", "2026-01-01T13:00:00+00:00")
    commitear(ctx.repo, "mismo instante, otro huso")

    assert {0, _salida, ""} = correr(ctx.prompts)
  end

  test "editar la fecha a mano falla y nombra el commit", ctx do
    [a1 | _] = repo_sano(ctx)
    reescribir_campo(ctx.prompts, a1, "fecha", "2026-01-01T11:00:00-03:00")
    commitear(ctx.repo, "fecha editada")

    assert {1, "", errores} = correr(ctx.prompts)
    assert errores =~ "#{a1}: fecha: 2026-01-01T11:00:00-03:00 no coincide con el commit"
    assert errores =~ "(2026-01-01T10:00:00-03:00)"
    assert errores =~ "1 problema(s) en prompts/"
  end

  test "editar el autor a mano falla; el nombre es libre, el email no", ctx do
    [a1, a2] = repo_sano(ctx)
    reescribir_campo(ctx.prompts, a1, "autor", "Otro Nombre <ana@example.com>")
    reescribir_campo(ctx.prompts, a2, "autor", "Ana Prueba <otra@example.com>")
    commitear(ctx.repo, "autores editados")

    assert {1, "", errores} = correr(ctx.prompts)
    refute errores =~ a1
    assert errores =~ "#{a2}: autor: otra@example.com no es el autor del commit"
  end

  test "un prompt sin commit todavía falla", ctx do
    [a1, a2] = repo_sano(ctx)
    a3 = escribir_prompt(ctx.prompts, 3)
    escribir_indice(ctx.prompts, [a1, a2, a3])

    assert {1, "", errores} = correr(ctx.prompts)
    assert errores =~ "#{a3}: no tiene commit todavía"
  end

  test "un número salteado o repetido falla", ctx do
    [a1, a2] = repo_sano(ctx)
    a4 = escribir_prompt(ctx.prompts, 4)
    escribir_indice(ctx.prompts, [a1, a2, a4])
    commitear(ctx.repo, "salto")

    assert {1, "", errores} = correr(ctx.prompts)
    assert errores =~ "numeración: se esperaba 0003, hay 0004"

    File.write!(
      Path.join(ctx.prompts, "0002-otro-prompt-2.md"),
      File.read!(Path.join(ctx.prompts, a2))
    )

    escribir_indice(ctx.prompts, [a1, a2, "0002-otro-prompt-2.md", a4])
    commitear(ctx.repo, "repetido")

    assert {1, "", errores} = correr(ctx.prompts)
    assert errores =~ "numeración: 0002 aparece 2 veces"
  end

  test "un índice desincronizado falla: falta, sobra o está desordenado", ctx do
    [a1, a2] = repo_sano(ctx)

    escribir_indice(ctx.prompts, [a1])
    assert {1, "", errores} = correr(ctx.prompts)
    assert errores =~ "README.md: el índice no lista #{a2}"

    escribir_indice(ctx.prompts, [a1, a2, "0003-fantasma.md"])
    assert {1, "", errores} = correr(ctx.prompts)
    assert errores =~ "README.md: el índice lista 0003 -> 0003-fantasma.md, que no corresponde"

    escribir_indice(ctx.prompts, [a2, a1])
    assert {1, "", errores} = correr(ctx.prompts)
    assert errores =~ "README.md: el índice no está en el orden de los archivos"
  end

  test "frontmatter ausente, incompleto o con otro número falla", ctx do
    [a1, a2] = repo_sano(ctx)
    a3 = escribir_prompt(ctx.prompts, 3, frontmatter: false)
    a4 = escribir_prompt(ctx.prompts, 4, sin: [:modelo, :autor])
    a5 = escribir_prompt(ctx.prompts, 5)
    reescribir_campo(ctx.prompts, a5, "prompt", "0009")
    escribir_indice(ctx.prompts, [a1, a2, a3, a4, a5])
    commitear(ctx.repo, "varios")

    assert {1, "", errores} = correr(ctx.prompts)
    assert errores =~ "#{a3}: no tiene frontmatter"
    assert errores =~ "#{a4}: falta autor: en el frontmatter"
    assert errores =~ "#{a4}: falta modelo: en el frontmatter"
    assert errores =~ "#{a5}: el frontmatter dice prompt: 0009 y el archivo es 0005"
  end

  test "una sección obligatoria ausente falla", ctx do
    [a1, a2] = repo_sano(ctx)
    a3 = escribir_prompt(ctx.prompts, 3, sin_seccion: "## Decisiones tomadas")
    escribir_indice(ctx.prompts, [a1, a2, a3])
    commitear(ctx.repo, "sin decisiones")

    assert {1, "", errores} = correr(ctx.prompts)
    assert errores =~ "#{a3}: falta la sección ## Decisiones tomadas"
  end

  test "--corregir reescribe fecha y autor con lo que git registró", ctx do
    [a1, _a2] = repo_sano(ctx)
    reescribir_campo(ctx.prompts, a1, "fecha", "2000-01-01T00:00:00Z")
    reescribir_campo(ctx.prompts, a1, "autor", "Nadie <nadie@example.com>")
    commitear(ctx.repo, "frontmatter roto")

    assert {0, salida, ""} = correr(ctx.prompts, ["--corregir"])
    assert salida =~ "#{a1}: fecha y autor corregidos con el commit"

    contenido = File.read!(Path.join(ctx.prompts, a1))
    assert contenido =~ "fecha: 2026-01-01T10:00:00-03:00"
    assert contenido =~ "autor: Ana Prueba <ana@example.com>"

    assert {0, _salida, ""} = correr(ctx.prompts)
  end

  test "aparece en mix help con su shortdoc" do
    assert Mix.Task.shortdoc(Mix.Tasks.Prompts.Verificar) ==
             "Verifica que prompts/ sea un registro auditable contra git"
  end

  defp reescribir_campo(prompts, archivo, campo, valor) do
    ruta = Path.join(prompts, archivo)

    File.write!(
      ruta,
      String.replace(File.read!(ruta), ~r/^#{campo}: .*$/m, "#{campo}: #{valor}", global: false)
    )
  end
end
