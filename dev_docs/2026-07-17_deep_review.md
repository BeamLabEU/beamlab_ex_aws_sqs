# Deep Review — beamlab_ex_aws_sqs (2026-07-17)

Scope: full package review of the `ExAws.SQS` fork (v4.0.0, commit `14755a4`).
Method: read all source/tests/config/CI, ran the whole toolchain locally, and
cross-checked every wire detail against the authoritative AWS service model
(`botocore/data/sqs/2012-11-05/service-2.json`, protocol `json 1.0`).

> **Status update (same day):** Batch 1 (F1, F2, F4–F6), Batch 2 (F7–F10) and
> Batch 3 (F11–F14) are **done** — see "Progress log" at the bottom. All 14
> findings are resolved, including F3: **v4.1.0 published to Hex**, tags
> `v4.0.0` (retroactive) and `v4.1.0` created and pushed.

## Verdict

The package is in **good shape**. All quality gates pass, the JSON-protocol
rewrite is wire-correct, and API coverage against AWS is complete. The findings
below are mostly polish, test-hardening, and one missing AWS feature. No
runtime bug affecting normal use was found.

### Verified green (evidence)

| Check | Result |
|---|---|
| `mix test` | 45 tests + 6 doctests, 0 failures (29 external excluded) |
| `mix credo --strict` | no issues (64 checks, 5 files) |
| `mix format --check-formatted` | clean |
| `mix dialyzer` | passed successfully |
| `mix docs` | builds, no warnings |
| AWS operation coverage | all 23 SQS actions implemented (full parity) |
| Wire format | `x-amz-target: AmazonSQS.<Action>`, `application/x-amz-json-1.0`, requestUri `/` — matches botocore model |
| Field casings | `tags` (lowercase) on CreateQueue, `queueUrls` (lowercase) response quirk, `AWSTraceHeader`, `QueueOwnerAWSAccountId` special cases — all match the model |
| Deps | `ex_aws` 2.7.0 locked = latest on Hex; package published on Hex as 4.0.0 |

Notably, `sqs_managed_sse_enabled` camelizes to `SqsManagedSseEnabled`, which
**matches the botocore model exactly** (AWS's HTML docs say `SqsManagedSSEEnabled`
— a known AWS docs/model discrepancy, not a bug here). Worth pinning with a test
(see F6) so nobody "fixes" it into a real bug.

---

## Findings

### P1 — Correctness / hygiene (small, uncontroversial)

- **F1 — Typespec gap: `sqs_queue_attribute_name` is missing KMS attributes.**
  `lib/ex_aws/sqs.ex:46-65` omits `:kms_master_key_id` and
  `:kms_data_key_reuse_period_seconds`, both valid per the AWS
  `QueueAttributeName` enum for `get_queue_attributes/2`. Users passing them get
  a dialyzer warning for a legitimate call.

- **F2 — Doctests are written but never run; they would fail if enabled.**
  The `iex>` examples in `create_queue/3`, `send_message/3`, and
  `send_message_batch/2` show map keys in documentation order, but
  `IO.inspect` (used by doctest comparison) emits keys sorted
  (`"Attributes"` before `"QueueName"`, etc.). Verified:
  `create_queue("my-queue", [visibility_timeout: 60], %{"team" => "platform"}).data`
  inspects as `%{"Attributes" => ..., "QueueName" => ..., "tags" => ...}`.
  Fix = reorder expected output in the examples + add `doctest ExAws.SQS` to
  `test/lib/sqs_test.exs` → free test coverage and docs that can't drift.

- **F3 — No git tag for v4.0.0, but `mix.exs` sets `source_ref: "v4.0.0"`. ✅ DONE**
  Resolved at the v4.1.0 release: `v4.0.0` tagged retroactively on `ca7a8ba`
  (the actual publish commit) and `v4.1.0` on the release commit; both pushed.

- **F4 — Stale `.gitignore` entry.** `ex_aws_sqs-*.tar` should be
  `beamlab_ex_aws_sqs-*.tar` (hex tarballs are named after `:app`).

- **F5 — Dead `elixirc_paths` entry.** `mix.exs:25` adds `test/support` for the
  test env; that directory doesn't exist. Harmless but confusing.

- **F6 — Pin the `SqsManagedSseEnabled` casing (and friends) with a golden test.**
  Casing correctness currently rests on `ExAws.Utils.camelize/1` plus two
  special cases. A test that maps every attribute/option atom in the typespecs
  to its exact AWS field name guards against regressions and documents the
  model-vs-docs discrepancy decision.

### P2 — Feature gaps vs the AWS API

- **F7 — `MessageSystemAttributes` on sends (the one real API gap). ✅ DONE**
  `SendMessage` and `SendMessageBatch` accept `MessageSystemAttributes`
  (currently only `AWSTraceHeader`) for X-Ray trace propagation.
  Implemented: `:message_system_attributes` option on `send_message/3` and on
  `send_message_batch/2` entries, same attr-map shape as `:message_attributes`;
  atom names go through the camelizing rules (`:aws_trace_header` →
  `"AWSTraceHeader"`), strings pass through verbatim. New type
  `sqs_message_system_attribute`; unit tests + doctest example.
  (No integration test — elasticmq's support for system attributes is
  unverified; not worth gambling CI.)

- **F8 — No pagination helpers. ✅ DONE (with a correction)**
  Correction to the original finding: `list_message_move_tasks/2` has **no**
  `NextToken` in either request or response (verified against the botocore
  model) — it returns a bounded list of recent tasks, so it got **no** stream
  helper. Implemented for the two genuinely paginated ops:
  `stream_queues/2` and `stream_dead_letter_source_queues/3` — lazy
  `Stream.resource`-based streams following `NextToken`, raising
  `RuntimeError` on page failure, with an optional trailing argument of
  `ExAws.request/2` config overrides (also the test seam: tests inject a stub
  `:http_client` per call — no global config mutation, tests stay `async`).
  Tested end-to-end through `ExAws.request` with a canned-page stub
  (`test/lib/sqs/stream_test.exs`), including laziness and the lowercase
  `"queueUrls"` response quirk.

- **F9 — Docs: endpoint/`QueueUrl` semantics are undocumented. ✅ DONE**
  README migration guide now states that `QueueUrl` travels in the request
  body and routing comes from `config :ex_aws, :sqs` (unlike 3.x, which
  derived the request path from the URL) — matching official SDK behavior.

- **F10 — CONTRIBUTING doesn't say how to run integration tests. ✅ DONE**
  CONTRIBUTING.md now documents the elasticmq docker one-liner and
  `mix test --include external`, mirroring CI.

### P3 — Optional hardening (discuss before doing)

- **F11 — No client-side validation. ✅ DONE (batch sizes only)**
  Per the original "lean" recommendation: `send_message_batch/2`,
  `delete_message_batch/2`, and `change_message_visibility_batch/2` now raise
  `ArgumentError` for empty or >10 batches via a private
  `validate_batch_size!/1` (lib/ex_aws/sqs.ex) — AWS's hard bound, unlikely to
  drift. No range policing of timeouts/labels (documented in typespecs; AWS
  can shift those, and server errors are clear enough). Tests cover 0, 11,
  and exactly-10 entries; one existing test that probed headers with an
  `[]` batch was updated to a valid 1-entry batch.

- **F12 — `add_permission/2` with the default `%{}` sends empty
  `AWSAccountIds`/`Actions` arrays. ✅ DONE (documented)**
  Kept the default (dropping it would be breaking); the `@doc` now states AWS
  requires at least one account/action pair and rejects the empty form.

- **F13 — CI speed: no `_build`/PLT caching. ✅ DONE**
  `.github/workflows/on-push.yml` now caches `deps` + `_build` (PLTs live in
  `_build`) keyed on os/OTP/Elixir/mix.lock with a restore-keys fallback, and
  gained `mix deps.unlock --check-unused` and `mix docs --warnings-as-errors`
  gates (both verified passing locally).

- **F14 — Cosmetic typespecs. ✅ DONE**
  `untag_queue/2` is now `tag_keys :: [String.Chars.t(), ...]`;
  `receive_message_opts[:visibility_timeout]` reuses the `visibility_timeout`
  alias; the inert `start_permanent` was dropped from mix.exs.

---

## Proposed work plan

- ~~**Batch 1 (P1, this review's quick wins):** F1, F2, F4, F5, F6 +
  CHANGELOG "Unreleased" section.~~ ✅ DONE
- ~~**Batch 2 (P2 features):** F7 (MessageSystemAttributes), F8 (pagination
  streams), F9/F10 doc lines.~~ ✅ DONE
- ~~**Batch 3 (P3):** F11–F14.~~ ✅ DONE
- ~~**Release chore:** git tags + publish.~~ ✅ DONE — **v4.1.0 is live on
  Hex** (package + docs), `v4.0.0`/`v4.1.0` tags pushed. Nothing left from
  this review.

## Progress log

- **2026-07-17 Batch 1:** typespec gap fixed, doctests enabled (examples
  corrected to inspected key order), golden casing tests added, `.gitignore` /
  `elixirc_paths` tidied, `erl_crash.dump` deleted. Gates: 38 tests + 5
  doctests green.
- **2026-07-17 Batch 2:** F7 `:message_system_attributes` on
  `send_message/3` + batch entries; F8 `stream_queues/2` +
  `stream_dead_letter_source_queues/3` (stub-http-client tests, no network);
  F9/F10 docs; CHANGELOG updated. Gates: 45 tests + 6 doctests, credo strict,
  dialyzer, format, docs — all clean.
- **2026-07-17 Batch 3:** F11 batch-size validation (0/11 raise, 10 ok); F12
  `add_permission` doc note; F13 CI `_build`/PLT caching + `check-unused` +
  docs gates; F14 typespec cosmetics, `start_permanent` dropped. Gates: 46
  tests + 6 doctests, credo strict, dialyzer, format,
  `docs --warnings-as-errors` — all clean.
- **2026-07-17 tooling:** added a `mix quality` alias (compile
  `--warnings-as-errors` → format check → credo strict → dialyzer → test),
  with `preferred_envs: [quality: :test]` so `mix test` accepts running from
  the alias (CI runs everything in `MIX_ENV=test` too). Full run: green, no
  warnings to fix. First run built the test-env PLT (~2 min, now cached in
  `_build/test`).
- **2026-07-17 release v4.1.0:** version bumped, changelog dated, `mix
  quality` green, `hex.publish --dry-run` verified (package contains only
  lib/mix.exs/CHANGELOG/README/LICENSE). Published to Hex as
  `beamlab_ex_aws_sqs` 4.1.0 (package + docs). Tagged `v4.0.0` retroactively
  on `ca7a8ba` and `v4.1.0` on the release commit; pushed `main` + tags.
  This closes F3 and the whole review.

*Environment note: integration tests (`:external`) were not run locally — this
container has no docker daemon for elasticmq. CI covers them.*
