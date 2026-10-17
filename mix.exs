defmodule ExAws.SQS.Mixfile do
  use Mix.Project

  @version "5.1.0"
  @url_docs "https://hexdocs.pm/beamlab_ex_aws_sqs"
  @url_github "https://github.com/BeamLabEU/beamlab_ex_aws_sqs"

  # Function groups for the generated docs (sidebar sections).
  @queue_functions ~w(create_queue delete_queue get_queue_url get_queue_attributes
                      set_queue_attributes list_queues list_dead_letter_source_queues
                      purge_queue)a
  @message_functions ~w(send_message send_message_batch receive_message delete_message
                        delete_message_batch change_message_visibility
                        change_message_visibility_batch)a
  @access_functions ~w(add_permission remove_permission tag_queue untag_queue
                       list_queue_tags)a
  @move_task_functions ~w(start_message_move_task cancel_message_move_task
                          list_message_move_tasks)a
  @stream_functions ~w(stream_queues stream_dead_letter_source_queues)a

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

  # `mix quality` runs the release gates locally (integration tests excluded —
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

  # Run the quality gates in the test env (MIX_ENV=test);
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
      # Test-only: `only: :test` keeps hackney out of the published package's
      # requirements entirely, so it can never constrain a consuming app's hackney
      # version. Requests go through whichever HTTP client the app configures for
      # ex_aws, which declares its own (optional) hackney/req constraints.
      # https://github.com/ex-aws/ex_aws_sqs/issues/36
      {:hackney, "~> 4.0", only: :test},
      {:ex_aws, "~> 2.7"}
    ]
  end

  defp docs do
    [
      main: "readme",
      # The OTP app (:ex_aws_sqs) differs from the Hex package name, so pin the canonical URL
      # to the real package instead of the one ExDoc would derive from the app name.
      canonical: @url_docs,
      source_url: @url_github,
      source_ref: "v#{@version}",
      formatters: ["html"],
      # Two modules; the README is the landing page, so the generated index is just noise.
      api_reference: false,
      extras: [
        "README.md": [title: "Overview"],
        "CHANGELOG.md": [title: "Changelog"],
        LICENSE: [title: "License"]
      ],
      groups_for_modules: [
        Exceptions: [ExAws.SQS.PaginationError]
      ],
      groups_for_docs: [
        Queues: &(&1[:name] in @queue_functions),
        Messages: &(&1[:name] in @message_functions),
        "Permissions & tags": &(&1[:name] in @access_functions),
        "Message move tasks (DLQ redrive)": &(&1[:name] in @move_task_functions),
        Streaming: &(&1[:name] in @stream_functions)
      ]
    ]
  end
end
