# ExAws.SQS

[![Module Version](https://img.shields.io/badge/version-4.0.0-blue.svg)](https://github.com/BeamLabEU/beamlab_ex_aws_sqs)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](./LICENSE)

Service module for [`ex_aws`](https://github.com/ex-aws/ex_aws).

This is a **modernized fork** of the archived
[`ex-aws/ex_aws_sqs`](https://github.com/ex-aws/ex_aws_sqs) (last released in Jan 2023). It exists
because the upstream project stopped receiving updates while its open issues stayed unresolved.
This fork:

* Switches every operation from the legacy Query/XML protocol to the **SQS JSON protocol**
  ([ex-aws/ex_aws_sqs#34](https://github.com/ex-aws/ex_aws_sqs/issues/34)), which AWS recommends
  going forward for lower latency and less client-side overhead. This also drops the `:saxy` /
  `:sweet_xml` dependency entirely — one less thing to configure or upgrade.
* Documents `send_message_batch/2` with a runnable example
  ([ex-aws/ex_aws_sqs#35](https://github.com/ex-aws/ex_aws_sqs/issues/35)).
* Relaxes the `:hackney` version constraint so it no longer collides with apps that have moved to
  hackney 4.x ([ex-aws/ex_aws_sqs#36](https://github.com/ex-aws/ex_aws_sqs/issues/36)). `hackney`
  is only used to run this library's own test suite — request execution always goes through
  whatever HTTP adapter your app configures for `ex_aws`.
* Adds the message-move-task operations (`start_message_move_task/2`,
  `cancel_message_move_task/1`, `list_message_move_tasks/2`) and `ListQueues`/
  `ListDeadLetterSourceQueues` pagination options, none of which existed yet when upstream went
  quiet.
* Refreshes `mix.exs`/CI to current Elixir/OTP versions.

## Installation

Not (yet) published to Hex — pull it straight from GitHub:

```elixir
def deps do
  [
    {:ex_aws, "~> 2.5"},
    {:ex_aws_sqs, github: "BeamLabEU/beamlab_ex_aws_sqs"},
    {:jason, "~> 1.4"},
    {:hackney, "~> 1.20"} # or any HTTP client ex_aws supports
  ]
end
```

## Migrating from `ex-aws/ex_aws_sqs`

The public function names and options are unchanged — swapping the dependency source is enough to
compile. What *does* change is the shape of a successful response, because there's no more
XML-to-map parsing layer standing between you and AWS:

```elixir
# before (ex-aws/ex_aws_sqs, XML/Query protocol)
{:ok, %{body: %{messages: [%{message_id: id, body: body} | _]}}} =
  ExAws.SQS.receive_message(queue_url) |> ExAws.request()

# after (this fork, JSON protocol)
{:ok, %{"Messages" => [%{"MessageId" => id, "Body" => body} | _]}} =
  ExAws.SQS.receive_message(queue_url) |> ExAws.request()
```

In short: response bodies are now the raw JSON payload AWS returns, decoded by your configured
`:json_codec` (`Jason` by default) — keyed exactly as the
[AWS API Reference](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/APIReference/Welcome.html)
documents for each action, with no snake_case/atom conversion. A couple of operations use
unusual casing straight from AWS (e.g. `list_dead_letter_source_queues/1` returns a lowercase
`"queueUrls"` key) — that's an AWS quirk carried through as-is, not a bug here.

You'll also want to drop `:saxy` and `:sweet_xml` from your deps if you added them for the old
parser, and can drop any `config :ex_aws_sqs, parser: ...` config — there's no parser to select
anymore.

## `send_message_batch/2`

Each entry is a keyword list (or map) with at least `:id` and `:message_body`:

```elixir
ExAws.SQS.send_message_batch(queue_url, [
  [id: "a1", message_body: "payload1"],
  [id: "a2", message_body: "payload2", delay_seconds: 10]
])
|> ExAws.request()

# {:ok, %{
#    "Successful" => [%{"Id" => "a1", "MessageId" => "...", "MD5OfMessageBody" => "..."}, ...],
#    "Failed" => []
#  }}
```

`:id` only needs to be unique within the batch — it's how you match each entry to its result in
`"Successful"`/`"Failed"`.

## Copyright and License

The MIT License (MIT)

Copyright (c) 2014 CargoSense, Inc.
Copyright (c) 2026 BeamLab EU

See [LICENSE](./LICENSE) for the full text.
