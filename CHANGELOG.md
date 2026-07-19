# Changelog

## v5.0.0 - 2026-07-19

- ***BREAKING CHANGE***: The compiled OTP application is now named `:ex_aws_sqs` again (it was
  `:beamlab_ex_aws_sqs` in v4.x). The Hex package name is unchanged (`beamlab_ex_aws_sqs`), but
  consumers must now depend on it with `{:ex_aws_sqs, "~> 5.0", hex: :beamlab_ex_aws_sqs}` instead
  of `{:beamlab_ex_aws_sqs, "~> 4.0"}`. This makes the package a proper drop-in for anything that
  declares a dependency on `:ex_aws_sqs` directly (e.g. `broadway_sqs`), which was impossible under
  the v4.x app name. [Fixes #1](https://github.com/BeamLabEU/beamlab_ex_aws_sqs/issues/1)

## v4.1.0 - 2026-07-17

- Added `:message_system_attributes` support to `send_message/3` and
  `send_message_batch/2` entries — currently used for the `AWSTraceHeader` X-Ray
  trace header (accepts the atom `:aws_trace_header` or the literal string).
- Added `stream_queues/2` and `stream_dead_letter_source_queues/3`: lazy,
  `NextToken`-paginated streams, with an optional trailing argument passed through
  as `ExAws.request/2` config overrides (e.g. `:region`, `:http_client`).
  `list_message_move_tasks/2` has no stream counterpart (AWS supports no
  pagination there).
- `send_message_batch/2`, `delete_message_batch/2`, and
  `change_message_visibility_batch/2` now raise `ArgumentError` for empty or
  oversized (>10) batches instead of round-tripping an invalid request to AWS.
- Documented that `add_permission/2`'s default empty `permissions` map is
  rejected by AWS (at least one account/action pair is required).
- Fixed `sqs_queue_attribute_name` typespec: added `:kms_master_key_id` and
  `:kms_data_key_reuse_period_seconds` (both valid for `get_queue_attributes/2`).
- Enabled doctests for `ExAws.SQS` and corrected the inspected map key order in
  doc examples so they now run as tests.
- Added golden tests pinning the exact AWS field name for every queue attribute
  and message system attribute atom (documents the `SqsManagedSseEnabled`
  model-vs-docs casing decision).
- CI: cache `_build` (incl. dialyzer PLTs) alongside `deps`, and added
  `mix deps.unlock --check-unused` + `mix docs --warnings-as-errors` gates.
- Added a `mix quality` alias running the CI gates locally (compile with
  warnings-as-errors, format check, credo strict, dialyzer, tests).
- README: documented request-endpoint vs `QueueUrl` routing semantics.
  CONTRIBUTING: how to run the integration tests locally.
- Tidied `.gitignore` (package tarball pattern), dropped a non-existent
  `test/support` entry from `elixirc_paths`, and removed the inert
  `start_permanent` mix option; tightened a few typespecs.

## v4.0.0 - 2026-07-12

First release of this fork ([BeamLabEU/beamlab_ex_aws_sqs](https://github.com/BeamLabEU/beamlab_ex_aws_sqs)),
based on [ex-aws/ex_aws_sqs](https://github.com/ex-aws/ex_aws_sqs) v3.4.0. Published to Hex as
`beamlab_ex_aws_sqs` (the original `ex_aws_sqs` name is already taken).

- ***BREAKING CHANGE***: All operations now use the AWS SQS **JSON protocol**
  (`AmazonSQS.<Action>` / `application/x-amz-json-1.0`) instead of the legacy Query/XML protocol.
  [Fixes ex-aws/ex_aws_sqs#34](https://github.com/ex-aws/ex_aws_sqs/issues/34). Successful
  responses are now the raw JSON body AWS returns (e.g. `%{"MessageId" => ...}`) instead of a
  hand-parsed, snake_cased map — see the README's migration guide.
- ***BREAKING CHANGE***: Removed `ExAws.SQS.SaxyParser` and `ExAws.SQS.SweetXmlParser`, and the
  `:saxy`/`:sweet_xml` optional dependencies along with them — there's no more XML to parse.
- Documented `send_message_batch/2` with a runnable example.
  [Fixes ex-aws/ex_aws_sqs#35](https://github.com/ex-aws/ex_aws_sqs/issues/35)
- Relaxed the `:hackney` dependency constraint (it's only used by this library's own test suite)
  so it no longer conflicts with apps on hackney 4.x.
  [Fixes ex-aws/ex_aws_sqs#36](https://github.com/ex-aws/ex_aws_sqs/issues/36)
- Added `start_message_move_task/2`, `cancel_message_move_task/1`, and
  `list_message_move_tasks/2` (DLQ redrive tasks, added to the AWS API after upstream's last
  release).
- Added pagination options (`:max_results`, `:next_token`) to `list_queues/1` and
  `list_dead_letter_source_queues/2`.
- `receive_message/2`'s `:attribute_names` option now sends the modern `MessageSystemAttributeNames`
  field instead of the deprecated `AttributeNames` field.
- Fixed binary message attribute handling for the JSON protocol: `BinaryValue` is now correctly
  base64-encoded so that the configured JSON codec's `encode!/1` (and the wire request) succeeds.
  Callers still pass the raw binary as `:value`.
- `send_message_batch/2` (and related batch helpers) now consistently accept both keyword lists
  and maps for entries (previously only keyword lists worked for entries containing message
  attributes).
- Bumped minimum Elixir version to `~> 1.18`, `ex_aws` to `~> 2.7`. Dropped the direct dependency
  on Jason in favor of Elixir's built-in `JSON` module (available since 1.18) — set
  `config :ex_aws, json_codec: JSON`.

---

Changelog entries below this point are from the original `ex-aws/ex_aws_sqs` project.

## v3.4.0

- fix `sqs_message_attribute` typing
- fix: update to Config module import
- refactor: catch sweetxml parsing error / handle non-xml error body
- Add dialyzer, credo, CI workflow alignment
- Bump minimum Elixir version to 1.10

## v3.3.1 - 2021-03-29

- [Fix Issue #24](https://github.com/ex-aws/ex_aws_sqs/issues/24) Always parse MessageGroupId as a string

## v3.3.0 - 2021-03-28

- Updated min elixir version to 1.7
- Updated ex_aws dependency from "~> 2.0" -> "~> 2.1"
- documentation and formating updates

## v3.2.1 - 2020-04-14

- Updated mix deps for `:saxy` & `:sweet_xml` to be marked optional

## v3.2.0 - 2020-04-13

- Added optional support for [saxy](https://hex.pm/packages/saxy) XML parser
- Saxy parser set as default parser if both `:saxy` and `:sweet_xml` loaded.

## v3.1.0 - 2020-01-22

- Added support for Queue Tags

## v3.0.2 - 2019-11-21

- Improved docs

## v3.0.1 - 2019-11-21

- Updated `sqs_message_attribute_name` typespec for `SQS.receive_message` to match AWS support attributes.

## v3.0.0 - 2019-08-17

- ***BREAKING CHANGE***: Changed queue specific functions to take the QueueUrl instead of the QueueName. Previously the name was used to build the path for the request. This is an anti-pattern according to aws docs and prevents this library from being used with alternative SQS compatible services, like localstack.

## v2.0.1 - 2019-04-11

- Relaxed `:ex_aws` version constraint from `v2.0.0` to `v2.0`

## v2.0.0 - 2017-11-10

- Major Project Split. Please see the main ExAws repository for previous changelogs.
