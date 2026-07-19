defmodule ExAws.SQS.Mixfile do
  use Mix.Project

  @version "5.0.0"
  @url_docs "https://hexdocs.pm/beamlab_ex_aws_sqs"
  @url_github "https://github.com/BeamLabEU/beamlab_ex_aws_sqs"

  def project do
    [
      app: :ex_aws_sqs,
      name: "ExAws.SQS",
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      aliases: aliases(),
      docs: docs(),
      package: package(),
      dialyzer: [
        plt_add_apps: [:ex_unit]
      ]
    ]
  end

  defp elixirc_paths(_), do: ["lib"]

  # `mix quality` runs the same local gates as CI (integration tests excluded —
  # those need elasticmq, see CONTRIBUTING.md).
  defp aliases do
    [
      quality: [
        "compile --warnings-as-errors",
        "format --check-formatted",
        "credo --strict",
        "dialyzer",
        "test"
      ]
    ]
  end

  def application do
    [
      extra_applications: extra_applications(Mix.env())
    ]
  end

  # Run the quality gates in the test env, like CI does (MIX_ENV=test);
  # `mix test` refuses to run from :dev inside an alias otherwise.
  def cli do
    [preferred_envs: [quality: :test]]
  end

  defp extra_applications(:test), do: [:logger, :hackney]
  defp extra_applications(_), do: [:logger]

  defp package do
    [
      name: "beamlab_ex_aws_sqs",
      description:
        "ExAws.SQS service package (published as beamlab_ex_aws_sqs on Hex). " <>
          "Modernized fork of the archived ex-aws/ex_aws_sqs, using the AWS SQS JSON protocol.",
      maintainers: ["BeamLab EU"],
      files: ["lib", "mix.exs", "CHANGELOG.md", "README.md", "LICENSE"],
      licenses: ["MIT"],
      links: %{
        "Changelog" => "#{@url_docs}/changelog.html",
        "GitHub" => @url_github,
        "Original project" => "https://github.com/ex-aws/ex_aws_sqs"
      }
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      # Only used to exercise the test suite; the actual HTTP client is
      # supplied by whichever adapter the consuming app configures for ex_aws.
      # Not pinned to a hackney major version: beamlab_ex_aws_sqs never calls hackney
      # directly, so any version ex_aws itself supports works here too.
      # https://github.com/ex-aws/ex_aws_sqs/issues/36
      {:hackney, ">= 1.9.0", only: :test, optional: true},
      ex_aws()
    ]
  end

  defp docs do
    [
      extras: ["CHANGELOG.md", "README.md", "LICENSE"],
      main: "readme",
      source_url: @url_github,
      source_ref: "v#{@version}",
      formatters: ["html"]
    ]
  end

  defp ex_aws() do
    case System.get_env("AWS") do
      "LOCAL" -> {:ex_aws, path: "../ex_aws"}
      _ -> {:ex_aws, "~> 2.7"}
    end
  end
end
