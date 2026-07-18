defmodule ExAws.SQS.StubHttpClient do
  @moduledoc false
  # Test double for the ExAws.Request.HttpClient behaviour: serves canned SQS
  # JSON pages keyed on the request body's NextToken, so pagination can be
  # exercised without network access. Sends {:page_fetched, token | :first} to
  # the pid in http_opts[:notify] (if any) so tests can observe laziness.
  @behaviour ExAws.Request.HttpClient

  @impl true
  def request(_method, _url, req_body, _headers, http_opts) do
    body = JSON.decode!(req_body)

    case http_opts[:notify] do
      nil -> :ok
      pid -> send(pid, {:page_fetched, Map.get(body, "NextToken", :first)})
    end

    case body do
      %{"QueueNamePrefix" => "boom"} ->
        error(400, "InvalidParameterValue", "boom")

      %{"NextToken" => "page2"} ->
        ok(%{"QueueUrls" => ["q3"], "NextToken" => "page3"})

      %{"NextToken" => "page3"} ->
        ok(%{"QueueUrls" => ["q4"]})

      %{"NextToken" => "dlq2"} ->
        ok(%{"queueUrls" => ["d2"]})

      %{"QueueUrl" => _} ->
        ok(%{"queueUrls" => ["d1"], "NextToken" => "dlq2"})

      %{} ->
        ok(%{"QueueUrls" => ["q1", "q2"], "NextToken" => "page2"})
    end
  end

  defp ok(map), do: {:ok, %{status_code: 200, headers: [], body: JSON.encode!(map)}}

  defp error(status, type, message) do
    {:ok,
     %{
       status_code: status,
       headers: [],
       body: JSON.encode!(%{"__type" => type, "message" => message})
     }}
  end
end

defmodule ExAws.SQSStreamTest do
  use ExUnit.Case, async: true
  alias ExAws.SQS

  @stub [http_client: ExAws.SQS.StubHttpClient]

  test "stream_queues/2 follows NextToken until the last page" do
    # The stub only serves "q3"/"q4" when the right tokens come back, so this
    # also proves the token is threaded into each subsequent request.
    assert SQS.stream_queues([], @stub) |> Enum.to_list() == ["q1", "q2", "q3", "q4"]
  end

  test "stream_queues/2 fetches pages lazily" do
    stream = SQS.stream_queues([], @stub ++ [http_opts: [notify: self()]])

    assert Enum.take(stream, 2) == ["q1", "q2"]
    assert_received {:page_fetched, :first}
    refute_received {:page_fetched, _}

    assert Enum.to_list(stream) == ["q1", "q2", "q3", "q4"]
    assert_received {:page_fetched, "page2"}
    assert_received {:page_fetched, "page3"}
  end

  test "stream_queues/2 passes list options through to the request" do
    # "boom" makes the stub answer with an AWS-shaped 400 error.
    assert_raise RuntimeError, ~r/SQS pagination failed/, fn ->
      SQS.stream_queues([queue_name_prefix: "boom"], @stub) |> Enum.to_list()
    end
  end

  test "stream_dead_letter_source_queues/3 reads the lowercase queueUrls field" do
    assert SQS.stream_dead_letter_source_queues("https://queue.url/dlq", [], @stub)
           |> Enum.to_list() == ["d1", "d2"]
  end
end
