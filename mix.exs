defmodule ExAws.SQS.Mixfile do
  use Mix.Project

  @version "4.0.0"
  @url_docs "https://hexdocs.pm/beamlab_ex_aws_sqs"
  @url_github "https://github.com/BeamLabEU/beamlab_ex_aws_sqs"

  def project do
    [
      app: :beamlab_ex_aws_sqs,
      name: "ExAws.SQS",
      version: @version,
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      package: package(),
      dialyzer: [
        plt_add_apps: [:ex_unit]
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: extra_applications(Mix.env())
    ]
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
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      # Only used to exercise the test suite; the actual HTTP client is
      # supplied by whichever adapter the consuming app configures for ex_aws.
      # Not pinned to a hackney major version: beamlab_ex_aws_sqs never calls hackney
      # directly, so any version ex_aws itself supports works here too.
      # https://github.com/ex-aws/ex_aws_sqs/issues/36
      {:hackney, ">= 1.9.0", optional: true},
      {:jason, "~> 1.4", optional: true},
      ex_aws()
    ]
  end

  defp docs do
    [
      extras: ["CHANGELOG.md", "README.md"],
      main: "readme",
      source_url: @url_github,
      source_ref: "v#{@version}",
      formatters: ["html"]
    ]
  end

  defp ex_aws() do
    case System.get_env("AWS") do
      "LOCAL" -> {:ex_aws, path: "../ex_aws"}
      _ -> {:ex_aws, "~> 2.5"}
    end
  end
end
