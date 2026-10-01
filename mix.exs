defmodule AnchoFijo.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/galenzo17/ancho_fijo"

  def project do
    [
      app: :ancho_fijo,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      dialyzer: dialyzer()
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
      {:stream_data, "~> 1.1", only: [:dev, :test]},
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
        "Definición del formato": [AnchoFijo.Layout, AnchoFijo.Campo, AnchoFijo.Rut],
        Diagnóstico: [AnchoFijo.Detector, AnchoFijo.Diagnostico],
        Lectura: [AnchoFijo.Parser, AnchoFijo.Transcodificacion]
      ]
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
