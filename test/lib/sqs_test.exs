defmodule ExAws.SQSTest do
  use ExUnit.Case, async: true
  alias ExAws.SQS

  defp headers(op), do: op.headers
  defp target(op), do: op.headers |> List.keyfind("x-amz-target", 0) |> elem(1)

  test "requests carry the JSON protocol headers and target the right action" do
    op = SQS.delete_queue("982071696186/test_queue")

    assert headers(op) == [
             {"x-amz-target", "AmazonSQS.DeleteQueue"},
             {"content-type", "application/x-amz-json-1.0"}
           ]

    assert target(SQS.send_message_batch("q", [])) == "AmazonSQS.SendMessageBatch"
    assert op.service == :sqs
    assert op.path == "/"
  end

  test "#create_queue" do
    expected = %{
      "QueueName" => "test_queue",
      "Attributes" => %{"VisibilityTimeout" => "10"}
    }

    assert expected == SQS.create_queue("test_queue", visibility_timeout: 10).data
  end

  test "#create_queue with tags" do
    expected = %{
      "QueueName" => "test_queue",
      "Attributes" => %{"FifoQueue" => "true"},
      "tags" => %{"team" => "platform"}
    }

    assert expected ==
             SQS.create_queue("test_queue", [fifo_queue: true], %{"team" => "platform"}).data
  end

  test "#create_queue with no attributes or tags" do
    assert %{"QueueName" => "test_queue"} == SQS.create_queue("test_queue").data
  end

  test "#delete_queue" do
    expected = %{"QueueUrl" => "982071696186/test_queue"}
    assert expected == SQS.delete_queue("982071696186/test_queue").data
  end

  test "#list_queues" do
    assert %{} == SQS.list_queues().data
  end

  test "#list_queues with options" do
    expected = %{"QueueNamePrefix" => "prefix", "MaxResults" => 5, "NextToken" => "abc"}

    assert expected ==
             SQS.list_queues(queue_name_prefix: "prefix", max_results: 5, next_token: "abc").data
  end

  test "#get_queue_attributes" do
    expected = %{
      "QueueUrl" => "982071696186/test_queue",
      "AttributeNames" => ["All"]
    }

    assert expected == SQS.get_queue_attributes("982071696186/test_queue").data

    expected = %{
      "QueueUrl" => "982071696186/test_queue",
      "AttributeNames" => ["VisibilityTimeout", "MessageRetentionPeriod"]
    }

    assert expected ==
             SQS.get_queue_attributes("982071696186/test_queue", [
               :visibility_timeout,
               :message_retention_period
             ]).data
  end

  test "#set_queue_attributes" do
    expected = %{
      "QueueUrl" => "982071696186/test_queue",
      "Attributes" => %{"VisibilityTimeout" => "10"}
    }

    assert expected ==
             SQS.set_queue_attributes("982071696186/test_queue", visibility_timeout: 10).data
  end

  test "#set_queue_attributes with no attributes" do
    expected = %{"QueueUrl" => "982071696186/test_queue", "Attributes" => %{}}
    assert expected == SQS.set_queue_attributes("982071696186/test_queue").data
  end

  test "#purge_queue" do
    expected = %{"QueueUrl" => "982071696186/test_queue"}
    assert expected == SQS.purge_queue("982071696186/test_queue").data
  end

  test "#list_dead_letter_source_queues" do
    expected = %{"QueueUrl" => "982071696186/test_queue"}
    assert expected == SQS.list_dead_letter_source_queues("982071696186/test_queue").data
  end

  test "#list_dead_letter_source_queues with pagination options" do
    expected = %{"QueueUrl" => "q", "MaxResults" => 10, "NextToken" => "tok"}

    assert expected ==
             SQS.list_dead_letter_source_queues("q", max_results: 10, next_token: "tok").data
  end

  test "#get_queue_url" do
    assert %{"QueueName" => "test_queue"} == SQS.get_queue_url("test_queue").data

    expected = %{"QueueName" => "test_queue", "QueueOwnerAWSAccountId" => "foo"}

    assert expected ==
             SQS.get_queue_url("test_queue", queue_owner_aws_account_id: "foo").data
  end

  test "#add_permission" do
    data =
      SQS.add_permission("982071696186/test_queue", "TestAddPermission", %{
        "681962096817" => :all,
        "071669896281" => [:send_message, :receive_message]
      }).data

    assert data["QueueUrl"] == "982071696186/test_queue"
    assert data["Label"] == "TestAddPermission"

    # AWSAccountIds and Actions are parallel arrays paired by index — order between
    # accounts isn't guaranteed (it follows Erlang's internal map iteration order), so
    # compare the zipped pairs as a set instead of asserting a specific order.
    assert MapSet.new(Enum.zip(data["AWSAccountIds"], data["Actions"])) ==
             MapSet.new([
               {"681962096817", "*"},
               {"071669896281", "SendMessage"},
               {"071669896281", "ReceiveMessage"}
             ])
  end

  test "#remove_permission" do
    expected = %{
      "QueueUrl" => "982071696186/test_queue",
      "Label" => "TestAddPermission"
    }

    assert expected ==
             SQS.remove_permission("982071696186/test_queue", "TestAddPermission").data
  end

  test "#send_message" do
    expected = %{
      "QueueUrl" => "982071696186/test_queue",
      "MessageBody" => "This is the message body.",
      "DelaySeconds" => 30,
      "MessageAttributes" => %{
        "TestStringAttribute" => %{"DataType" => "String", "StringValue" => "testing!"},
        "TestBinaryAttribute" => %{
          "DataType" => "Binary",
          "BinaryValue" => Base.encode64(:zlib.gzip("testing!"))
        },
        "TestNumberAttribute" => %{"DataType" => "Number", "StringValue" => "42"},
        "TestCustomNumberAttribute" => %{"DataType" => "Number.Prime", "StringValue" => "7"}
      }
    }

    assert expected ==
             SQS.send_message(
               "982071696186/test_queue",
               "This is the message body.",
               delay_seconds: 30,
               message_attributes: [
                 %{name: "TestStringAttribute", data_type: :string, value: "testing!"},
                 %{
                   name: "TestBinaryAttribute",
                   data_type: :binary,
                   value: :zlib.gzip("testing!")
                 },
                 %{name: "TestNumberAttribute", data_type: :number, value: 42},
                 %{
                   name: "TestCustomNumberAttribute",
                   data_type: :number,
                   custom_type: "Prime",
                   value: 7
                 }
               ]
             ).data
  end

  test "#send_message with a single message attribute map (not wrapped in a list)" do
    expected = %{
      "QueueUrl" => "q",
      "MessageBody" => "body",
      "MessageAttributes" => %{
        "Foo" => %{"DataType" => "String", "StringValue" => "bar"}
      }
    }

    assert expected ==
             SQS.send_message("q", "body",
               message_attributes: %{name: "Foo", data_type: :string, value: "bar"}
             ).data
  end

  test "#send_message for FIFO queue" do
    expected = %{
      "QueueUrl" => "982071696186/test_queue.fifo",
      "MessageBody" => "This is the message body.",
      "MessageGroupId" => "TestGroupId",
      "MessageDeduplicationId" => "TestDedupId"
    }

    assert expected ==
             SQS.send_message(
               "982071696186/test_queue.fifo",
               "This is the message body.",
               message_group_id: "TestGroupId",
               message_deduplication_id: "TestDedupId"
             ).data
  end

  test "#send_message_batch" do
    expected = %{
      "QueueUrl" => "982071696186/test_queue",
      "Entries" => [
        %{
          "Id" => "test_message_1",
          "MessageBody" => "This is the message body.",
          "DelaySeconds" => 30,
          "MessageAttributes" => %{
            "TestStringAttribute" => %{"DataType" => "String", "StringValue" => "testing!"}
          }
        },
        %{
          "Id" => "test_message_2",
          "MessageBody" => "This is the second message body."
        }
      ]
    }

    assert expected ==
             SQS.send_message_batch(
               "982071696186/test_queue",
               [
                 [
                   id: "test_message_1",
                   message_body: "This is the message body.",
                   delay_seconds: 30,
                   message_attributes: [
                     %{name: "TestStringAttribute", data_type: :string, value: "testing!"}
                   ]
                 ],
                 [id: "test_message_2", message_body: "This is the second message body."]
               ]
             ).data
  end

  test "#send_message_batch accepts map entries (not only keyword lists)" do
    data =
      SQS.send_message_batch("q", [
        %{
          id: "m1",
          message_body: "hi",
          message_attributes: %{name: "k", data_type: :string, value: "v"}
        }
      ]).data

    assert data["Entries"] == [
             %{
               "Id" => "m1",
               "MessageBody" => "hi",
               "MessageAttributes" => %{"k" => %{"DataType" => "String", "StringValue" => "v"}}
             }
           ]
  end

  test "#send_message_batch binary attribute produces base64 and is JSON encodable" do
    bin = <<1, 2, 3, 4>>

    data =
      SQS.send_message_batch("q", [
        [
          id: "b1",
          message_body: "x",
          message_attributes: [%{name: "b", data_type: :binary, value: bin}]
        ]
      ]).data

    entry = hd(data["Entries"])
    assert entry["MessageAttributes"]["b"]["BinaryValue"] == Base.encode64(bin)
    assert entry["MessageAttributes"]["b"]["DataType"] == "Binary"

    # The whole data must be serializable by the configured json_codec (Elixir's built-in JSON).
    assert is_binary(JSON.encode!(data))
  end

  test "#receive_message" do
    assert %{"QueueUrl" => "982071696186/test_queue"} ==
             SQS.receive_message("982071696186/test_queue").data

    expected = %{
      "QueueUrl" => "982071696186/test_queue",
      "MessageSystemAttributeNames" => ["All"],
      "MaxNumberOfMessages" => 5
    }

    assert expected ==
             SQS.receive_message("982071696186/test_queue",
               attribute_names: :all,
               max_number_of_messages: 5
             ).data

    expected = %{
      "QueueUrl" => "982071696186/test_queue",
      "MessageSystemAttributeNames" => [
        "SenderId",
        "ApproximateReceiveCount",
        "MessageDeduplicationId",
        "MessageGroupId",
        "AWSTraceHeader"
      ],
      "VisibilityTimeout" => 1000,
      "WaitTimeSeconds" => 20
    }

    assert expected ==
             SQS.receive_message("982071696186/test_queue",
               attribute_names: [
                 :sender_id,
                 :approximate_receive_count,
                 :message_deduplication_id,
                 :message_group_id,
                 :aws_trace_header
               ],
               visibility_timeout: 1000,
               wait_time_seconds: 20
             ).data
  end

  test "#receive_message can set the message attributes to all" do
    expected = %{"QueueUrl" => "12345/test_queue", "MessageAttributeNames" => ["All"]}

    assert expected ==
             SQS.receive_message("12345/test_queue", message_attribute_names: :all).data
  end

  test "#receive_message can specify message attributes" do
    expected = %{
      "QueueUrl" => "12345/test_queue",
      "MessageAttributeNames" => ["FooAttr", "BarAttr", "BazAttr"]
    }

    assert expected ==
             SQS.receive_message("12345/test_queue",
               message_attribute_names: ["FooAttr", "BarAttr", "BazAttr"]
             ).data
  end

  test "#receive_message can set atom message attributes" do
    expected = %{
      "QueueUrl" => "12345/test_queue",
      "MessageAttributeNames" => ["FooAttr", "BarAttr", "BazAttr"]
    }

    assert expected ==
             SQS.receive_message("12345/test_queue",
               message_attribute_names: [:FooAttr, :BarAttr, :BazAttr]
             ).data
  end

  test "#delete_message" do
    expected = %{"QueueUrl" => "982071696186/test_queue", "ReceiptHandle" => "handle"}
    assert expected == SQS.delete_message("982071696186/test_queue", "handle").data
  end

  test "#delete_message_batch" do
    expected = %{
      "QueueUrl" => "982071696186/test_queue",
      "Entries" => [
        %{"Id" => "message_1", "ReceiptHandle" => "handle_1"},
        %{"Id" => "message_2", "ReceiptHandle" => "handle_2"}
      ]
    }

    assert expected ==
             SQS.delete_message_batch("982071696186/test_queue", [
               %{id: "message_1", receipt_handle: "handle_1"},
               %{id: "message_2", receipt_handle: "handle_2"}
             ]).data
  end

  test "#change_message_visibility" do
    expected = %{
      "QueueUrl" => "982071696186/test_queue",
      "ReceiptHandle" => "handle",
      "VisibilityTimeout" => 300
    }

    assert expected ==
             SQS.change_message_visibility("982071696186/test_queue", "handle", 300).data
  end

  test "#change_message_visibility_batch" do
    expected = %{
      "QueueUrl" => "982071696186/test_queue",
      "Entries" => [
        %{"Id" => "message_1", "ReceiptHandle" => "handle_1", "VisibilityTimeout" => 300},
        %{"Id" => "message_2", "ReceiptHandle" => "handle_2", "VisibilityTimeout" => 600}
      ]
    }

    assert expected ==
             SQS.change_message_visibility_batch("982071696186/test_queue", [
               %{id: "message_1", receipt_handle: "handle_1", visibility_timeout: 300},
               %{id: "message_2", receipt_handle: "handle_2", visibility_timeout: 600}
             ]).data
  end

  test "#list_queue_tags" do
    assert %{"QueueUrl" => "q"} == SQS.list_queue_tags("q").data
  end

  test "#tag_queue" do
    expected = %{"QueueUrl" => "q", "Tags" => %{"env" => "prod", "team" => "platform"}}

    assert expected == SQS.tag_queue("q", %{"env" => "prod", "team" => "platform"}).data
  end

  test "#untag_queue" do
    expected = %{"QueueUrl" => "q", "TagKeys" => ["env", "team"]}
    assert expected == SQS.untag_queue("q", [:env, "team"]).data
  end

  test "#start_message_move_task" do
    assert %{"SourceArn" => "arn:aws:sqs:...:dlq"} ==
             SQS.start_message_move_task("arn:aws:sqs:...:dlq").data

    expected = %{
      "SourceArn" => "arn:aws:sqs:...:dlq",
      "DestinationArn" => "arn:aws:sqs:...:dest",
      "MaxNumberOfMessagesPerSecond" => 50
    }

    assert expected ==
             SQS.start_message_move_task("arn:aws:sqs:...:dlq",
               destination_arn: "arn:aws:sqs:...:dest",
               max_number_of_messages_per_second: 50
             ).data

    assert target(SQS.start_message_move_task("arn")) == "AmazonSQS.StartMessageMoveTask"
  end

  test "#cancel_message_move_task" do
    assert %{"TaskHandle" => "th"} == SQS.cancel_message_move_task("th").data
  end

  test "#list_message_move_tasks" do
    assert %{"SourceArn" => "arn"} == SQS.list_message_move_tasks("arn").data

    assert %{"SourceArn" => "arn", "MaxResults" => 3} ==
             SQS.list_message_move_tasks("arn", max_results: 3).data
  end
end
