defmodule ExAws.SQS.PaginationError do
  @moduledoc """
  Raised by `ExAws.SQS.stream_queues/2` and `ExAws.SQS.stream_dead_letter_source_queues/3`
  when fetching a page fails.

    * `:reason` - the term `ExAws.request/2` returned in `{:error, reason}`, so callers can
      pattern-match on it (e.g. `{"InvalidParameterValue", "message"}` for an AWS error response).
    * `:items_key` - the response field the stream was reading (`"QueueUrls"` or `"queueUrls"`).
  """

  defexception [:items_key, :reason]

  @type t :: %__MODULE__{items_key: String.t(), reason: term}

  @impl true
  def message(%__MODULE__{items_key: items_key, reason: reason}) do
    "SQS pagination failed while fetching #{items_key}: #{inspect(reason)}"
  end
end
