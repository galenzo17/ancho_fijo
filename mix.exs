defmodule AnchoFijo.MixProject do
  use Mix.Project

  @version "0.2.0"
  @source_url "https://github.com/galenzo17/ancho_fijo"

  def project do
    [
      app: :ancho_fijo,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      # Los .exs de test/fixtures son scripts, no tests (Elixir 1.20 avisa).
      test_ignore_filters: [~r"^test/fixtures/"],
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      dialyzer: dialyzer(),
      test_coverage: test_coverage()
    ]
  end

  def cli do
    [preferred_envs: [credo: :test, dialyzer: :dev]]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      # Opcional: solo para AnchoFijo.Monto.a_decimal/1.
      {:decimal, "~> 2.0", optional: true},
      # Opcional: sin ella no se emite nada y el paquete sigue sin
      # dependencias de runtime. Ver AnchoFijo.Telemetria.
      {:telemetry, "~> 1.3", optional: true},
      {:stream_data, "~> 1.1", only: [:dev, :test]},
      {:benchee, "~> 1.3", only: :dev, runtime: false},
      # Solo para validar la salida --json de la tarea con un decoder real.
      {:jason, "~> 1.4", only: [:dev, :test]},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp description do
    "Fixed-width file reader with upfront format detection and diagnostic errors " <>
      "that name the line, the expectation and the probable cause."
  end

  defp package do
    [
      name: "ancho_fijo",
      licenses: ["MIT"],
      maintainers: ["Agustin Bereciartua"],
      files: ~w(lib mix.exs README.md CHANGELOG.md LICENSE .formatter.exs),
      # La verificación de prompts/ es del repositorio, no del paquete.
      exclude_patterns: [~r"lib/mix/tasks/prompts\."],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"
      }
    ]
  end

  defp docs do
    [
      main: "AnchoFijo",
      source_url: @source_url,
      source_ref: "v#{@version}",
      extras: ["README.md", "CHANGELOG.md", "LICENSE"],
      groups_for_modules: [
        "Definición del formato": [
          AnchoFijo.Layout,
          AnchoFijo.Campo,
          AnchoFijo.Rut,
          AnchoFijo.Monto,
          AnchoFijo.Multiregistro
        ],
        Diagnóstico: [AnchoFijo.Detector, AnchoFijo.Diagnostico, AnchoFijo.Error],
        Lectura: [
          AnchoFijo.Parser,
          AnchoFijo.Transcodificacion,
          AnchoFijo.Traza,
          AnchoFijo.Identidad
        ],
        Escritura: [AnchoFijo.Escritor],
        Observabilidad: [AnchoFijo.Telemetria],
        Terminal: [Mix.Tasks.AnchoFijo.Detectar],
        "Formatos incluidos": [AnchoFijo.Formatos, AnchoFijo.Formatos.Nacha]
      ]
    ]
  end

  # Sin servicio externo ni badge: el número se mide en CI y falla si cae del
  # umbral, nada más. Un badge de cobertura invita a escribir tests para el
  # número. Los módulos de test/support no son código del paquete.
  defp test_coverage do
    [
      summary: [threshold: 90],
      ignore_modules: [AnchoFijo.Fixtures, AnchoFijo.Generadores]
    ]
  end

  defp dialyzer do
    [
      plt_add_apps: [:mix, :ex_unit],
      plt_local_path: "priv/plts",
      plt_core_path: "priv/plts",
      flags: [:error_handling, :extra_return, :missing_return, :unmatched_returns]
    ]
  end
end
