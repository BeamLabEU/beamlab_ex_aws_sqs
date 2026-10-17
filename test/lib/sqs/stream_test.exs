defmodule ExAws.SQS.StubHttpClient do
  @moduledoc false
  # Test double for the ExAws.Request.HttpClient behaviour: serves canned SQS
  # JSON pages keyed on the request body's NextToken, so pagination can be
  # exercised without network access. Sends {:page_fetched, body} to
  # the pid in http_opts[:notify] (if any) so tests can observe laziness.
  @behaviour ExAws.Request.HttpClient

  @impl true
  def request(_method, _url, req_body, _headers, http_opts) do
    body = JSON.decode!(req_body)

    case http_opts[:notify] do
      nil -> :ok
      pid -> send(pid, {:page_fetched, body})
    end

    respond = http_opts[:respond] || (&respond/1)
    respond.(body)
  end

  defp respond(body) do
    case body do
      %{"QueueNamePrefix" => "boom"} ->
        error(400, "InvalidParameterValue", "boom")

      # Like AWS, return no continuation token unless MaxResults was supplied.
      body when not is_map_key(body, "MaxResults") ->
        ok(%{if(is_map_key(body, "QueueUrl"), do: "queueUrls", else: "QueueUrls") => []})

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
    refute_received {:page_fetched, _}

    assert Enum.take(stream, 2) == ["q1", "q2"]
    assert_received {:page_fetched, %{"MaxResults" => 1000} = body}
    refute Map.has_key?(body, "NextToken")
    refute_received {:page_fetched, _}

    assert Enum.to_list(stream) == ["q1", "q2", "q3", "q4"]
    assert_received {:page_fetched, %{"NextToken" => "page2", "MaxResults" => 1000}}
    assert_received {:page_fetched, %{"NextToken" => "page3", "MaxResults" => 1000}}
  end

  test "stream_queues/2 passes list options through to the request" do
    # "boom" makes the stub answer with an AWS-shaped 400 error.
    assert_raise SQS.PaginationError, ~r/SQS pagination failed/, fn ->
      SQS.stream_queues([queue_name_prefix: "boom"], @stub) |> Enum.to_list()
    end
  end

  test "a failed page raises PaginationError carrying the original error" do
    error =
      assert_raise SQS.PaginationError, fn ->
        SQS.stream_queues([queue_name_prefix: "boom"], @stub) |> Enum.to_list()
      end

    assert %SQS.PaginationError{items_key: "QueueUrls", reason: {"InvalidParameterValue", "boom"}} =
             error
  end

  test "stream_dead_letter_source_queues/3 reads the lowercase queueUrls field" do
    assert SQS.stream_dead_letter_source_queues("https://queue.url/dlq", [], @stub)
           |> Enum.to_list() == ["d1", "d2"]
  end

  test "streams preserve page size, initial token and operation options on every page" do
    respond = fn body ->
      key = if Map.has_key?(body, "QueueUrl"), do: "queueUrls", else: "QueueUrls"
      token = body["NextToken"]
      ok(%{key => [token], "NextToken" => if(token == "page2", do: "page3", else: "")})
    end

    request_opts = @stub ++ [http_opts: [notify: self(), respond: respond]]

    for {stream, _key} <- streams([max_results: 5, next_token: "page2"], request_opts) do
      assert Enum.to_list(stream) == ["page2", "page3"]

      for token <- ["page2", "page3"] do
        assert_received {:page_fetched, %{"MaxResults" => 5, "NextToken" => ^token} = body}

        assert body["QueueNamePrefix"] == "prod-" or body["QueueUrl"] == "https://queue.url/dlq"
      end
    end
  end

  test "streams continue through an empty page with a continuation token" do
    for key <- ["QueueUrls", "queueUrls"] do
      respond = fn
        %{"NextToken" => "after-empty"} -> ok(%{key => ["last"]})
        %{} -> ok(%{"NextToken" => "after-empty"})
      end

      request_opts = @stub ++ [http_opts: [respond: respond]]
      {stream, ^key} = Enum.find(streams([], request_opts), &(elem(&1, 1) == key))
      assert Enum.to_list(stream) == ["last"]
    end
  end

  test "streams stop on absent, null or empty continuation tokens" do
    for token <- [:absent, nil, ""], empty? <- [false, true] do
      respond = fn body ->
        refute Map.has_key?(body, "NextToken")
        key = if Map.has_key?(body, "QueueUrl"), do: "queueUrls", else: "QueueUrls"
        response = if empty?, do: %{}, else: %{key => ["last"]}
        ok(if token == :absent, do: response, else: Map.put(response, "NextToken", token))
      end

      for {stream, _key} <- streams([], @stub ++ [http_opts: [respond: respond]]) do
        assert Enum.to_list(stream) == if(empty?, do: [], else: ["last"])
      end
    end
  end

  test "a later page failure preserves items already emitted and the original error" do
    respond = fn body ->
      case body do
        %{"NextToken" => "failure"} ->
          {:ok,
           %{
             status_code: 400,
             headers: [],
             body: JSON.encode!(%{"__type" => "InvalidParameterValue", "message" => "later"})
           }}

        %{} ->
          key = if Map.has_key?(body, "QueueUrl"), do: "queueUrls", else: "QueueUrls"
          ok(%{key => ["first"], "NextToken" => "failure"})
      end
    end

    request_opts = @stub ++ [http_opts: [respond: respond]]

    for {stream, key} <- streams([], request_opts) do
      assert Enum.take(stream, 1) == ["first"]

      error =
        assert_raise SQS.PaginationError, fn ->
          Enum.each(stream, &send(self(), {:item, &1}))
        end

      assert_received {:item, "first"}
      assert error.items_key == key
      assert error.reason == {"InvalidParameterValue", "later"}

      assert Exception.message(error) ==
               "SQS pagination failed while fetching #{key}: #{inspect(error.reason)}"
    end
  end

  defp streams(opts, request_opts) do
    [
      {SQS.stream_queues([queue_name_prefix: "prod-"] ++ opts, request_opts), "QueueUrls"},
      {SQS.stream_dead_letter_source_queues("https://queue.url/dlq", opts, request_opts),
       "queueUrls"}
    ]
  end

  defp ok(map), do: {:ok, %{status_code: 200, headers: [], body: JSON.encode!(map)}}
end
