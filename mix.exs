defmodule Statex.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/PragTob/statex"

  def project do
    [
      app: :statex,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      name: "Statex"
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp description do
    """
    Finite state machines as plain data.
    """
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  defp docs do
    [
      main: "Statex",
      source_url: @source_url,
      source_ref: @version,
      extras: ["README.md"],
      groups_for_modules: [
        Definition: [Statex.Definition, Statex.Definition.Builder],
        Runtime: [Statex.Instance],
        Introspection: [Statex.Introspection],
        Data: [Statex.State, Statex.Transition],
        Errors: [Statex.CompileError, Statex.TransitionError]
      ]
    ]
  end
end
