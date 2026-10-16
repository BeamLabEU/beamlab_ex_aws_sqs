# AGENTS.md

`beamlab_ex_aws_sqs` — fork of the archived `ex-aws/ex_aws_sqs`. Same public API (`ExAws.SQS`), but
every operation uses the SQS **JSON protocol** and responses are the raw decoded JSON body. A
standalone library: no `phoenix_kit` dependency.

## Names that differ

| What | Value |
|---|---|
| Directory / GitHub repo | `beamlab_ex_aws_sqs` |
| Hex package | `beamlab_ex_aws_sqs` |
| OTP app | `:ex_aws_sqs` (so it drops in for `broadway_sqs` etc.) |

Consumers depend on it as `{:ex_aws_sqs, "~> 5.0", hex: :beamlab_ex_aws_sqs}`.

## Layout

- `lib/ex_aws/sqs.ex` — all 23 operations, the `stream_*` pagination helpers, request building
- `lib/ex_aws/sqs/pagination_error.ex` — raised by the stream helpers
- `test/lib/sqs_test.exs` — unit tests (request shape, casing, validation) and doctests
- `test/lib/sqs/stream_test.exs` — pagination via a stub `:http_client`, no network
- `test/lib/sqs/integration_test.exs` — `:external`, needs elasticmq (see `CONTRIBUTING.md`)

## Commands

```bash
mix deps.get
mix test                      # unit tests + doctests
mix test --include external   # plus integration tests (elasticmq on localhost:9324)
mix quality                   # compile --warnings-as-errors, format, credo --strict, dialyzer, test
mix docs --warnings-as-errors
```

There is no CI workflow (removed deliberately) — `mix quality` is the gate.

## Conventions

- Dependencies are Hex packages only. `hackney` is `only: :test`; the HTTP client is the
  consuming app's choice via `ex_aws`.
- Wire casing follows the botocore model (`service-2.json`), not the AWS HTML docs — e.g.
  `SqsManagedSseEnabled`. Golden tests pin every attribute name; don't "fix" them.
- Public functions return `ExAws.Operation.JSON` structs; nothing here performs requests.

## Releasing

Tags use a `v` prefix (`v5.1.0`). Follow the `hex-publish` skill: bump `@version` in `mix.exs`,
CHANGELOG entry, `mix quality`, commit, push and verify, `mix hex.publish --yes`, then tag.
