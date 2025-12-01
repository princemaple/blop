defmodule Blop.Mixfile do
  use Mix.Project

  @version "0.1.5"

  @source_url "https://github.com/princemaple/blop"

  def project do
    [
      app: :blop,
      version: @version,
      elixir: "~> 1.14",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      package: package(),
      deps: deps(),
      description: "A simple library to interact with an IMAP server",

      # Docs
      name: "Blop",
      source_url: @source_url,
      homepage_url: @source_url,
      docs: docs()
    ]
  end

  defp package do
    [
      name: "blop",
      files: ["lib", "priv", "mix.exs", "README*", "LICENSE*"],
      maintainers: ["Po Chen <chenpaul914@gmail.com>"],
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end

  def application do
    [extra_applications: [:logger, :ssl]]
  end

  defp deps do
    [
      {:mail, "~> 0.5"},
      {:castore, "~> 1.0"},
      {:abnf_parsec, "~> 2.0", runtime: false},
      {:ex_doc, ">= 0.0.0", only: [:dev, :docs], runtime: false}
    ]
  end

  defp docs do
    [main: "readme", extras: ["README.md"]]
  end
end
