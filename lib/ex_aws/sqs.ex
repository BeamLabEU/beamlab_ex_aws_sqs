defmodule ExAws.SQS do
  @moduledoc """
  Operations on AWS SQS.

  This is a modernized fork of the archived
  [`ex-aws/ex_aws_sqs`](https://github.com/ex-aws/ex_aws_sqs). The biggest change is that every
  operation now speaks the SQS **JSON protocol** (`AmazonSQS.<Action>` over
  `application/x-amz-json-1.0`) instead of the legacy Query/XML protocol. See the `README` for
  the full list of changes and a migration guide.

  ## Responses

  Because requests are built with `ExAws.Operation.JSON`, a successful `ExAws.request/1` call
  returns `{:ok, response}` where `response` is the JSON response body decoded as-is by your
  configured `:json_codec` (Elixir's built-in `JSON` module since 1.18, or Jason, etc.) — a map with the exact field names AWS documents,
  e.g. `%{"MessageId" => "...", "MD5OfMessageBody" => "..."}` for `send_message/3`. There is no
  extra normalization layer: whatever the
  [AWS API Reference](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/APIReference/Welcome.html)
  says a call returns is what you get back, keyed exactly as documented (a handful of AWS
  operations use unusual casing, e.g. `list_dead_letter_source_queues/1` returns `"queueUrls"`
  with a lowercase `q` — that's an AWS quirk, not a bug here).
  """

  alias ExAws.Operation.JSON

  @type sqs_permission ::
          :send_message
          | :receive_message
          | :delete_message
          | :change_message_visibility
          | :get_queue_attributes
  @type sqs_acl :: %{binary => :all | [sqs_permission, ...]}

  # https://github.com/boto/botocore/blob/develop/botocore/data/sqs/2012-11-05/service-2.json
  @type sqs_message_attribute_name ::
          :sender_id
          | :sent_timestamp
          | :approximate_receive_count
          | :approximate_first_receive_timestamp
          | :sequence_number
          | :message_deduplication_id
          | :message_group_id
          | :aws_trace_header
          | :dead_letter_queue_source_arn

  @type sqs_queue_attribute_name ::
          :policy
          | :visibility_timeout
          | :maximum_message_size
          | :message_retention_period
          | :approximate_number_of_messages
          | :approximate_number_of_messages_not_visible
          | :created_timestamp
          | :last_modified_timestamp
          | :queue_arn
          | :approximate_number_of_messages_delayed
          | :delay_seconds
          | :receive_message_wait_time_seconds
          | :redrive_policy
          | :redrive_allow_policy
          | :fifo_queue
          | :content_based_deduplication
          | :kms_master_key_id
          | :kms_data_key_reuse_period_seconds
          | :deduplication_scope
          | :fifo_throughput_limit
          | :sqs_managed_sse_enabled
  @type visibility_timeout :: 0..43_200
  @type queue_attributes :: [
          {:policy, binary}
          | {:visibility_timeout, visibility_timeout}
          | {:maximum_message_size, 1024..262_144}
          | {:message_retention_period, 60..1_209_600}
          | {:approximate_number_of_messages, binary}
          | {:approximate_number_of_messages_not_visible, binary}
          | {:created_timestamp, binary}
          | {:last_modified_timestamp, binary}
          | {:queue_arn, binary}
          | {:approximate_number_of_messages_delayed, binary}
          | {:delay_seconds, 0..900}
          | {:receive_message_wait_time_seconds, 0..20}
          | {:redrive_policy, binary}
          | {:redrive_allow_policy, binary}
          | {:fifo_queue, boolean}
          | {:content_based_deduplication, boolean}
          | {:kms_master_key_id, binary}
          | {:kms_data_key_reuse_period_seconds, 60..86_400}
          | {:deduplication_scope, binary}
          | {:fifo_throughput_limit, binary}
          | {:sqs_managed_sse_enabled, boolean}
        ]
  @type sqs_message_attribute :: %{
          :name => binary,
          :data_type => :string | :binary | :number,
          optional(:custom_type) => binary,
          :value => binary | number
        }

  @type sqs_message_system_attribute :: %{
          :name => :aws_trace_header | binary,
          :data_type => :string | :binary | :number,
          optional(:custom_type) => binary,
          :value => binary | number
        }

  @doc """
  Adds a permission with the provided label to the Queue
  for a specific action for a specific account.

  Note: AWS requires at least one account/action pair. Calling `add_permission/2`
  (which defaults `permissions` to `%{}`) sends empty `AWSAccountIds`/`Actions`
  lists and is rejected by AWS — pass a non-empty map.

  [AWS API Docs](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/APIReference/API_AddPermission.html)
  """
  @spec add_permission(queue_url :: binary, label :: binary, permissions :: sqs_acl) :: JSON.t()
  def add_permission(queue_url, label, permissions \\ %{}) do
    {account_ids, actions} =
      permissions
      |> expand_permissions()
      |> Enum.unzip()

    request(queue_url, :add_permission, %{
      "Label" => label,
      "AWSAccountIds" => account_ids,
      "Actions" => Enum.map(actions, &format_param_key/1)
    })
  end

  @doc """
  Extends the read lock timeout for the specified message from
  the specified queue to the specified value.

  [AWS API Docs](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/APIReference/API_ChangeMessageVisibility.html)
  """
  @spec change_message_visibility(
          queue_url :: binary,
          receipt_handle :: binary,
          visibility_timeout :: visibility_timeout
        ) :: JSON.t()
  def change_message_visibility(queue_url, receipt_handle, visibility_timeout) do
    request(queue_url, :change_message_visibility, %{
      "ReceiptHandle" => receipt_handle,
      "VisibilityTimeout" => visibility_timeout
    })
  end

  @doc """
  Extends the read lock timeout for a batch of 1..10 messages.

  Raises `ArgumentError` if the batch is empty or larger than 10 entries
  (AWS rejects both, so we fail before the request round-trip).

  [AWS API Docs](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/APIReference/API_ChangeMessageVisibilityBatch.html)
  """
  @type message_visibility_batch_item :: %{
          :id => binary,
          :receipt_handle => binary,
          :visibility_timeout => visibility_timeout
        }
  @spec change_message_visibility_batch(
          queue_url :: binary,
          opts :: [message_visibility_batch_item, ...]
        ) :: JSON.t()
  def change_message_visibility_batch(queue_url, messages) do
    request(queue_url, :change_message_visibility_batch, %{
      "Entries" => messages |> validate_batch_size!() |> Enum.map(&format_regular_opts/1)
    })
  end

  @doc """
  Create queue.

  [AWS API Docs](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/APIReference/API_CreateQueue.html)

  ## Attributes

    * `:delay_seconds` - The length of time, in seconds, for which the delivery of all messages in the queue is delayed. Valid values: An integer from 0 to 900 seconds (15 minutes). Default: 0.

    * `:maximum_message_size` - The limit of how many bytes a message can contain before Amazon SQS rejects it. Valid values: An integer from 1,024 bytes (1 KiB) to 262,144 bytes (256 KiB). Default: 262,144 (256 KiB).

    * `:message_retention_period` - The length of time, in seconds, for which Amazon SQS retains a message. Valid values: An integer from 60 seconds (1 minute) to 1,209,600 seconds (14 days). Default: 345,600 (4 days).

    * `:policy` - The queue's policy. A valid AWS policy. For more information about policy structure, see [Overview of AWS IAM Policies](https://docs.aws.amazon.com/IAM/latest/UserGuide/PoliciesOverview.html) in the Amazon IAM User Guide.

    * `:receive_message_wait_time_seconds` - The length of time, in seconds, for which a [ReceiveMessage](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/APIReference/API_ReceiveMessage.html) action waits for a message to arrive. Valid values: An integer from 0 to 20 (seconds). Default: 0.

    * `:redrive_policy` - The string that includes the parameters for the dead-letter queue functionality of the source queue as a JSON object. For more information about the redrive policy and dead-letter queues, see [Using Amazon SQS Dead-Letter Queues](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-dead-letter-queues.html) in the Amazon Simple Queue Service Developer Guide.
      * `deadLetterTargetArn` – The Amazon Resource Name (ARN) of the dead-letter queue to which Amazon SQS moves messages after the value of maxReceiveCount is exceeded.

      * `maxReceiveCount` – The number of times a message is delivered to the source queue before being moved to the dead-letter queue. When the ReceiveCount for a message exceeds the maxReceiveCount for a queue, Amazon SQS moves the message to the dead-letter-queue.

      *Note*

      The dead-letter queue of a FIFO queue must also be a FIFO queue. Similarly, the dead-letter queue of a standard queue must also be a standard queue.

    * `:visibility_timeout` - The visibility timeout for the queue, in seconds. Valid values: An integer from 0 to 43,200 (12 hours). Default: 30. For more information about the visibility timeout, see [Visibility Timeout](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-visibility-timeout.html) in the Amazon Simple Queue Service Developer Guide.

    * `:fifo_queue` - Designates a queue as FIFO. Valid values: true, false. If you don't specify the FifoQueue attribute, Amazon SQS creates a standard queue. You can provide this attribute only during queue creation. You can't change it for an existing queue. When you set this attribute, you must also provide the MessageGroupId for your messages explicitly.
      For more information, see [FIFO Queue Logic](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/FIFO-queues.html#FIFO-queues-understanding-logic) in the Amazon Simple Queue Service Developer Guide.

    * `:content_based_deduplication` - Enables content-based deduplication. Valid values: true, false. For more information, see [Exactly-Once Processing](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/FIFO-queues.html#FIFO-queues-exactly-once-processing) in the Amazon Simple Queue Service Developer Guide.

    * `:kms_master_key_id` - The ID of an AWS-managed customer master key (CMK) for Amazon SQS or a custom CMK. For more information, see [Key Terms](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-server-side-encryption.html#sqs-sse-key-terms). While the alias of the AWS-managed CMK for Amazon SQS is always alias/aws/sqs, the alias of a custom CMK can, for example, be alias/MyAlias . For more examples, see [KeyId](https://docs.aws.amazon.com/kms/latest/APIReference/API_DescribeKey.html#API_DescribeKey_RequestParameters) in the AWS Key Management Service API Reference.

    * `:kms_data_key_reuse_period_seconds` - The length of time, in seconds, for which Amazon SQS can reuse a [data key](https://docs.aws.amazon.com/kms/latest/developerguide/concepts.html#data-keys) to encrypt or decrypt messages before calling AWS KMS again. An integer representing seconds, between 60 seconds (1 minute) and 86,400 seconds (24 hours). Default: 300 (5 minutes).

    * `:sqs_managed_sse_enabled` - Enables server-side queue encryption using SQS owned encryption keys. Valid values: true, false.

  ## Examples

      iex> ExAws.SQS.create_queue("my-queue", [visibility_timeout: 60], %{"team" => "platform"}).data
      %{
        "Attributes" => %{"VisibilityTimeout" => "60"},
        "QueueName" => "my-queue",
        "tags" => %{"team" => "platform"}
      }
  """
  @spec create_queue(queue_name :: binary) :: JSON.t()
  @spec create_queue(queue_name :: binary, queue_attributes :: queue_attributes) :: JSON.t()
  @spec create_queue(queue_name :: binary, queue_attributes :: queue_attributes, tags :: map) ::
          JSON.t()
  def create_queue(queue_name, attributes \\ [], tags \\ %{}) do
    data =
      %{"QueueName" => queue_name}
      |> maybe_put("Attributes", build_attribute_map(attributes))
      # `tags` (lowercase) is the literal field name AWS's CreateQueue JSON model uses.
      |> maybe_put("tags", stringify_tags(tags))

    request(nil, :create_queue, data)
  end

  @doc """
  Delete a message from a SQS Queue

  [AWS API Docs](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/APIReference/API_DeleteMessage.html)
  """
  @spec delete_message(queue_url :: binary, receipt_handle :: binary) :: JSON.t()
  def delete_message(queue_url, receipt_handle) do
    request(queue_url, :delete_message, %{"ReceiptHandle" => receipt_handle})
  end

  @doc """
  Deletes a list of messages from a SQS Queue in a single request

  Accepts 1..10 entries; raises `ArgumentError` otherwise (AWS rejects both
  empty and oversized batches, so we fail before the request round-trip).

  [AWS API Docs](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/APIReference/API_DeleteMessageBatch.html)
  """
  @type delete_message_batch_item :: %{
          :id => binary,
          :receipt_handle => binary
        }
  @spec delete_message_batch(
          queue_url :: binary,
          message_receipts :: [delete_message_batch_item, ...]
        ) :: JSON.t()
  def delete_message_batch(queue_url, messages) do
    request(queue_url, :delete_message_batch, %{
      "Entries" => messages |> validate_batch_size!() |> Enum.map(&format_regular_opts/1)
    })
  end

  @doc """
  Delete a queue

  [AWS API Docs](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/APIReference/API_DeleteQueue.html)
  """
  @spec delete_queue(queue_url :: binary) :: JSON.t()
  def delete_queue(queue_url) do
    request(queue_url, :delete_queue, %{})
  end

  @doc """
  Gets attributes of a SQS Queue

  [AWS API Docs](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/APIReference/API_GetQueueAttributes.html)
  """
  @spec get_queue_attributes(queue_url :: binary) :: JSON.t()
  @spec get_queue_attributes(
          queue_url :: binary,
          attribute_names :: :all | [sqs_queue_attribute_name, ...]
        ) :: JSON.t()
  def get_queue_attributes(queue_url, attributes \\ :all) do
    data = maybe_put(%{}, "AttributeNames", format_attribute_names(attributes))
    request(queue_url, :get_queue_attributes, data)
  end

  @doc """
  Get queue URL

  [AWS API Docs](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/APIReference/API_GetQueueUrl.html)

  ## Options

    * `:queue_owner_aws_account_id` -  The AWS account ID of the account that created the queue.
  """
  @spec get_queue_url(queue_name :: binary) :: JSON.t()
  @spec get_queue_url(queue_name :: binary, opts :: [queue_owner_aws_account_id: binary]) ::
          JSON.t()
  def get_queue_url(queue_name, opts \\ []) do
    data =
      opts
      |> format_regular_opts()
      |> Map.put("QueueName", queue_name)

    request(nil, :get_queue_url, data)
  end

  @doc """
  Retrieves the dead letter source queues for a given SQS Queue

  [AWS API Docs](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/APIReference/API_ListDeadLetterSourceQueues.html)

  ## Options

    * `:max_results` - Maximum number of results to include in the response.
    * `:next_token` - Pagination token from a previous call, used to retrieve the next page of results.
  """
  @spec list_dead_letter_source_queues(queue_url :: binary) :: JSON.t()
  @spec list_dead_letter_source_queues(
          queue_url :: binary,
          opts :: [max_results: pos_integer, next_token: binary]
        ) :: JSON.t()
  def list_dead_letter_source_queues(queue_url, opts \\ []) do
    request(queue_url, :list_dead_letter_source_queues, format_regular_opts(opts))
  end

  @doc """
  Retrieves a list of all the SQS Queues

  [AWS API Docs](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/APIReference/API_ListQueues.html)

  ## Options

    * `:queue_name_prefix` - A string to use for filtering the list results. Only those queues whose name begins with the specified string are returned.
      Queue URLs and names are case-sensitive.
    * `:max_results` - Maximum number of results to include in the response.
    * `:next_token` - Pagination token from a previous call, used to retrieve the next page of results.
  """
  @spec list_queues() :: JSON.t()
  @spec list_queues(
          opts :: [
            queue_name_prefix: binary,
            max_results: pos_integer,
            next_token: binary
          ]
        ) :: JSON.t()
  def list_queues(opts \\ []) do
    request(nil, :list_queues, format_regular_opts(opts))
  end

  @doc """
  Purge all messages in a SQS Queue

  [AWS API Docs](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/APIReference/API_PurgeQueue.html)
  """
  @spec purge_queue(queue_url :: binary) :: JSON.t()
  def purge_queue(queue_url) do
    request(queue_url, :purge_queue, %{})
  end

  @type receive_message_opts :: [
          {:attribute_names, :all | [sqs_message_attribute_name, ...]}
          | {:message_attribute_names, :all | [String.Chars.t(), ...]}
          | {:max_number_of_messages, 1..10}
          | {:visibility_timeout, visibility_timeout}
          | {:wait_time_seconds, 0..20}
          | {:receive_request_attempt_id, String.t()}
        ]

  @doc """
  Read messages from a SQS Queue

  [AWS API Docs](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/APIReference/API_ReceiveMessage.html)

  ## Options

    * `:attribute_names` - `:all` or a list of message system attributes to include in the response (sent as the modern `MessageSystemAttributeNames` field). Valid attributes are:
    [:sender_id, :sent_timestamp, :approximate_receive_count, :approximate_first_receive_timestamp, :sequence_number, :message_deduplication_id, :message_group_id, :aws_trace_header, :dead_letter_queue_source_arn]

    * `:message_attribute_names` - `:all` or a list of message attributes to include.

      * The name can contain alphanumeric characters and the underscore (_), hyphen (-), and period (.).

      * The name is case-sensitive and must be unique among all attribute names for the message.

      * The name must not start with AWS-reserved prefixes such as AWS. or Amazon. (or any casing variants).

      * The name must not start or end with a period (.), and it should not have periods in succession (..).

      * The name can be up to 256 characters long.

    * `:max_number_of_messages` - The maximum number of messages to return. Amazon SQS never returns more messages than this value (however, fewer messages might be returned). Valid values: 1 to 10. Default: 1.

    * `:visibility_timeout` - The duration (in seconds) that the received messages are hidden from subsequent retrieve requests after being retrieved by a ReceiveMessage request.

    * `:wait_time_seconds` - The duration (in seconds) for which the call waits for a message to arrive in the queue before returning.

    * `:receive_request_attempt_id` - This parameter applies only to FIFO (first-in-first-out) queues. The token used for deduplication of ReceiveMessage calls.
  """
  @spec receive_message(queue_url :: binary) :: JSON.t()
  @spec receive_message(queue_url :: binary, opts :: receive_message_opts) :: JSON.t()
  def receive_message(queue_url, opts \\ []) do
    {attrs, opts} = Keyword.pop(opts, :attribute_names, [])
    {message_attrs, opts} = Keyword.pop(opts, :message_attribute_names, [])

    data =
      opts
      |> format_regular_opts()
      |> maybe_put("MessageSystemAttributeNames", format_attribute_names(attrs))
      |> maybe_put("MessageAttributeNames", format_message_attribute_names(message_attrs))

    request(queue_url, :receive_message, data)
  end

  @doc """
  Removes permission with the given label from the Queue

  [AWS API Docs](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/APIReference/API_RemovePermission.html)
  """
  @spec remove_permission(queue_url :: binary, label :: binary) :: JSON.t()
  def remove_permission(queue_url, label) do
    request(queue_url, :remove_permission, %{"Label" => label})
  end

  @type sqs_message_opts :: [
          {:delay_seconds, 0..900}
          | {:message_attributes, sqs_message_attribute | [sqs_message_attribute, ...]}
          | {:message_system_attributes,
             sqs_message_system_attribute | [sqs_message_system_attribute, ...]}
          | {:message_deduplication_id, binary}
          | {:message_group_id, binary}
        ]

  @doc """
  Send a message to a SQS Queue

  [AWS API Docs](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/APIReference/API_SendMessage.html)

  ## Options

    * `:delay_seconds` - The length of time, in seconds, for which to delay a specific message. Valid values: 0 to 900.

    * `:message_attributes` - Each message attribute consists of a `:name`, `:data_type`, and `:value`. For binary attributes (`data_type: :binary`), pass the raw binary in `:value`; the library base64-encodes it for the JSON protocol. See [Amazon SQS Message Attributes](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-message-attributes.html).

    * `:message_system_attributes` - Same shape as `:message_attributes`, but for AWS-controlled
      system attributes. Currently the only supported one is `:aws_trace_header` (sent as
      `AWSTraceHeader`): an X-Ray trace header string (`data_type: :string`) that propagates
      tracing context through the queue. Its size doesn't count towards the total message size.

    * `:message_deduplication_id` - This parameter applies only to FIFO (first-in-first-out) queues.

    * `:message_group_id` - This parameter applies only to FIFO (first-in-first-out) queues.

  ## Examples

      iex> ExAws.SQS.send_message("https://queue.url", "Hello!").data
      %{"MessageBody" => "Hello!", "QueueUrl" => "https://queue.url"}

      iex> ExAws.SQS.send_message("https://queue.url", "Hello!",
      ...>   message_attributes: [%{name: "priority", data_type: :number, value: 1}]
      ...> ).data
      %{
        "MessageAttributes" => %{
          "priority" => %{"DataType" => "Number", "StringValue" => "1"}
        },
        "MessageBody" => "Hello!",
        "QueueUrl" => "https://queue.url"
      }

      iex> ExAws.SQS.send_message("https://queue.url", "Hello!",
      ...>   message_system_attributes: [
      ...>     %{name: :aws_trace_header, data_type: :string, value: "Root=1-abc"}
      ...>   ]
      ...> ).data
      %{
        "MessageBody" => "Hello!",
        "MessageSystemAttributes" => %{
          "AWSTraceHeader" => %{"DataType" => "String", "StringValue" => "Root=1-abc"}
        },
        "QueueUrl" => "https://queue.url"
      }
  """
  @spec send_message(queue_url :: binary, message_body :: binary) :: JSON.t()
  @spec send_message(queue_url :: binary, message_body :: binary, opts :: sqs_message_opts) ::
          JSON.t()
  def send_message(queue_url, message, opts \\ []) do
    {attrs, opts} = Keyword.pop(opts, :message_attributes, [])
    {system_attrs, opts} = Keyword.pop(opts, :message_system_attributes, [])

    data =
      opts
      |> format_regular_opts()
      |> maybe_put("MessageAttributes", build_message_attribute_map(attrs))
      |> maybe_put(
        "MessageSystemAttributes",
        build_message_attribute_map(system_attrs, &format_system_attribute_name/1)
      )
      |> Map.put("MessageBody", message)

    request(queue_url, :send_message, data)
  end

  @type sqs_batch_message ::
          map()
          | [
              {:id, binary}
              | {:message_body, binary}
              | {:delay_seconds, 0..900}
              | {:message_attributes, sqs_message_attribute | [sqs_message_attribute, ...]}
              | {:message_system_attributes,
                 sqs_message_system_attribute | [sqs_message_system_attribute, ...]}
              | {:message_deduplication_id, binary}
              | {:message_group_id, binary}
            ]

  @doc """
  Send 1..10 messages to a SQS Queue in a single request.

  Raises `ArgumentError` if the batch is empty or larger than 10 entries
  (AWS rejects both, so we fail before the request round-trip).

  Each entry needs at least an `:id` (unique within the batch, used to match up the
  `"Successful"`/`"Failed"` results in the response) and a `:message_body`.
  Entries may be keyword lists or maps, and otherwise accept the same options as
  `send_message/3` (`:delay_seconds`, `:message_attributes`, `:message_system_attributes`,
  `:message_deduplication_id`, `:message_group_id`).

  [AWS API Docs](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/APIReference/API_SendMessageBatch.html)

  ## Examples

      iex> ExAws.SQS.send_message_batch("https://queue.url", [
      ...>   [id: "a1", message_body: "payload1"],
      ...>   [id: "a2", message_body: "payload2", delay_seconds: 10]
      ...> ]).data
      %{
        "Entries" => [
          %{"Id" => "a1", "MessageBody" => "payload1"},
          %{"DelaySeconds" => 10, "Id" => "a2", "MessageBody" => "payload2"}
        ],
        "QueueUrl" => "https://queue.url"
      }

  A successful call returns a body shaped like:

      %{
        "Successful" => [%{"Id" => "a1", "MessageId" => "...", "MD5OfMessageBody" => "..."}, ...],
        "Failed" => [%{"Id" => "a2", "Code" => "...", "Message" => "...", "SenderFault" => true}, ...]
      }
  """
  @spec send_message_batch(queue_url :: binary, messages :: [sqs_batch_message, ...]) :: JSON.t()
  def send_message_batch(queue_url, messages) do
    request(queue_url, :send_message_batch, %{
      "Entries" => messages |> validate_batch_size!() |> Enum.map(&format_batch_message_entry/1)
    })
  end

  @doc """
  Set attributes of a SQS Queue.

  [AWS API Docs](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/APIReference/API_SetQueueAttributes.html)
  """
  @spec set_queue_attributes(queue_url :: binary, attributes :: queue_attributes) :: JSON.t()
  def set_queue_attributes(queue_url, attributes \\ []) do
    request(queue_url, :set_queue_attributes, %{
      "Attributes" => build_attribute_map(attributes)
    })
  end

  @doc """
  List tags of a SQS Queue.

  [AWS API Docs](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/APIReference/API_ListQueueTags.html)
  """
  @spec list_queue_tags(queue_url :: binary) :: JSON.t()
  def list_queue_tags(queue_url) do
    request(queue_url, :list_queue_tags, %{})
  end

  @doc """
  Apply tags to a SQS Queue.

  [AWS API Docs](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/APIReference/API_TagQueue.html)
  """
  @spec tag_queue(queue_url :: binary, tags :: map) :: JSON.t()
  def tag_queue(queue_url, tags) do
    request(queue_url, :tag_queue, %{"Tags" => stringify_tags(tags)})
  end

  @doc """
  Remove tags from a SQS Queue.

  [AWS API Docs](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/APIReference/API_UntagQueue.html)
  """
  @spec untag_queue(queue_url :: binary, tag_keys :: [String.Chars.t(), ...]) :: JSON.t()
  def untag_queue(queue_url, tag_keys) do
    request(queue_url, :untag_queue, %{"TagKeys" => Enum.map(tag_keys, &to_string/1)})
  end

  @doc """
  Starts an asynchronous task to move messages from a specified source queue to a specified
  destination queue.

  [AWS API Docs](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/APIReference/API_StartMessageMoveTask.html)

  ## Options

    * `:destination_arn` - The ARN of the queue that receives the moved messages. Defaults to the dead-letter queue's redrive policy source queue.
    * `:max_number_of_messages_per_second` - Throughput cap for the move, from 1 to 500 messages per second.

  ## Examples

      iex> ExAws.SQS.start_message_move_task("arn:aws:sqs:us-east-1:123:MyDLQ").data
      %{"SourceArn" => "arn:aws:sqs:us-east-1:123:MyDLQ"}
  """
  @spec start_message_move_task(source_arn :: binary) :: JSON.t()
  @spec start_message_move_task(
          source_arn :: binary,
          opts :: [destination_arn: binary, max_number_of_messages_per_second: pos_integer]
        ) :: JSON.t()
  def start_message_move_task(source_arn, opts \\ []) do
    data =
      opts
      |> format_regular_opts()
      |> Map.put("SourceArn", source_arn)

    request(nil, :start_message_move_task, data)
  end

  @doc """
  Cancels a specified message movement task.

  [AWS API Docs](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/APIReference/API_CancelMessageMoveTask.html)
  """
  @spec cancel_message_move_task(task_handle :: binary) :: JSON.t()
  def cancel_message_move_task(task_handle) do
    request(nil, :cancel_message_move_task, %{"TaskHandle" => task_handle})
  end

  @doc """
  Gets the most recent message movement tasks (up to the last 31 days) for a specified
  source queue ARN.

  [AWS API Docs](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/APIReference/API_ListMessageMoveTasks.html)

  ## Options

    * `:max_results` - Maximum number of results to include in the response, from 1 to 10. Default 1.
  """
  @spec list_message_move_tasks(source_arn :: binary) :: JSON.t()
  @spec list_message_move_tasks(source_arn :: binary, opts :: [max_results: 1..10]) :: JSON.t()
  def list_message_move_tasks(source_arn, opts \\ []) do
    data =
      opts
      |> format_regular_opts()
      |> Map.put("SourceArn", source_arn)

    request(nil, :list_message_move_tasks, data)
  end

  ## Streaming
  ###

  @doc """
  Returns a lazy stream of queue URLs, transparently fetching additional pages with
  `list_queues/1` (`NextToken`) as the stream is consumed.

  Takes the same options as `list_queues/1` (`:queue_name_prefix`, `:max_results`), plus an
  optional list of `ExAws.request/2` config overrides (e.g. a different `:region`, or an
  alternative `:http_client`).

  Each page is fetched with `ExAws.request/2`; the stream raises a `RuntimeError` if a page
  request fails.

      ExAws.SQS.stream_queues(queue_name_prefix: "prod-") |> Enum.to_list()
      # => ["https://sqs.us-east-1.amazonaws.com/123/prod-a", ...]
  """
  @spec stream_queues(
          opts :: [queue_name_prefix: binary, max_results: pos_integer],
          request_opts :: keyword
        ) :: Enumerable.t(binary)
  def stream_queues(opts \\ [], request_opts \\ []) do
    paginate(&list_queues/1, opts, request_opts, "QueueUrls")
  end

  @doc """
  Returns a lazy stream of dead-letter source queue URLs for `queue_url`, transparently
  fetching additional pages with `list_dead_letter_source_queues/2` (`NextToken`) as the
  stream is consumed.

  Like `stream_queues/2`: takes `:max_results` plus optional `ExAws.request/2` config
  overrides, and raises a `RuntimeError` if a page request fails.

  (`list_message_move_tasks/2` has no stream counterpart — the AWS operation returns a
  bounded list of recent tasks and supports no `NextToken` pagination.)
  """
  @spec stream_dead_letter_source_queues(
          queue_url :: binary,
          opts :: [max_results: pos_integer],
          request_opts :: keyword
        ) :: Enumerable.t(binary)
  def stream_dead_letter_source_queues(queue_url, opts \\ [], request_opts \\ []) do
    paginate(&list_dead_letter_source_queues(queue_url, &1), opts, request_opts, "queueUrls")
  end

  # Lazily pages through a list operation. `fun` builds an ExAws.Operation from opts with
  # :next_token injected per page; `items_key` is the response field holding the page items
  # (note the AWS quirk: ListQueues returns "QueueUrls" while ListDeadLetterSourceQueues
  # returns lowercase "queueUrls").
  defp paginate(fun, opts, request_opts, items_key) do
    Stream.resource(
      fn -> :first_page end,
      fn
        :done ->
          {:halt, :done}

        token ->
          opts = if token == :first_page, do: opts, else: Keyword.put(opts, :next_token, token)

          case fun.(opts) |> ExAws.request(request_opts) do
            {:ok, response} ->
              next_token = Map.get(response, "NextToken")

              {Map.get(response, items_key, []),
               if(next_token in [nil, ""], do: :done, else: next_token)}

            {:error, reason} ->
              raise "SQS pagination failed while fetching #{items_key}: #{inspect(reason)}"
          end
      end,
      fn _acc -> :ok end
    )
  end

  ## Request building
  ###

  # Build an ExAws.Operation.JSON for the SQS JSON protocol.
  defp build_op(data, action) do
    action_name = action |> Atom.to_string() |> Macro.camelize()

    JSON.new(:sqs, %{
      data: data,
      headers: [
        {"x-amz-target", "AmazonSQS.#{action_name}"},
        {"content-type", "application/x-amz-json-1.0"}
      ]
    })
  end

  # QueueUrl is required for most operations; a few (create/get queue, move tasks, list) pass nil.
  defp build_op(data, action, nil), do: build_op(data, action)

  defp build_op(data, action, queue_url),
    do: build_op(Map.put(data, "QueueUrl", queue_url), action)

  # Internal entry points. All call sites in this module use the 3-argument form
  # (first arg is either a queue_url or nil for queue-less actions).
  defp request(queue_url_or_nil, action, data) do
    build_op(data, action, queue_url_or_nil)
  end

  ## Helpers
  ###

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, []), do: map
  defp maybe_put(map, _key, v) when is_map(v) and map_size(v) == 0, do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  # AWS bounds every batch operation to 1..10 entries; fail locally instead of
  # round-tripping an invalid request.
  defp validate_batch_size!(messages) when is_list(messages) do
    size = length(messages)

    if size < 1 or size > 10 do
      raise ArgumentError, "expected between 1 and 10 batch entries, got: #{size}"
    end

    messages
  end

  defp expand_permissions(%{} = permissions) do
    permissions
    |> Enum.flat_map(&expand_permission/1)
  end

  defp expand_permission({account_id, :all}), do: [{account_id, "*"}]

  defp expand_permission({account_id, permissions}) do
    Enum.map(permissions, &{account_id, &1})
  end

  defp format_regular_opts(opts) do
    opts
    |> Enum.into(%{}, fn {k, v} -> {format_param_key(k), v} end)
  end

  # A handful of SQS fields don't follow the generic camelizing rule below because AWS
  # preserves acronyms in full caps.
  defp format_param_key("*"), do: "*"
  defp format_param_key(:aws_trace_header), do: "AWSTraceHeader"
  defp format_param_key(:queue_owner_aws_account_id), do: "QueueOwnerAWSAccountId"

  defp format_param_key(key) do
    key
    |> Atom.to_string()
    |> ExAws.Utils.camelize()
  end

  defp format_attribute_names(:all), do: ["All"]
  defp format_attribute_names([]), do: nil
  defp format_attribute_names(names), do: Enum.map(names, &format_param_key/1)

  defp format_message_attribute_names(:all), do: ["All"]
  defp format_message_attribute_names([]), do: nil
  defp format_message_attribute_names(names), do: Enum.map(names, &to_string/1)

  defp build_attribute_map(attributes) do
    attributes
    |> Enum.into(%{}, fn {name, value} -> {format_param_key(name), stringify(value)} end)
  end

  defp stringify_tags(tags) do
    tags
    |> Enum.into(%{}, fn {k, v} -> {to_string(k), to_string(v)} end)
  end

  defp stringify(value) when is_binary(value), do: value
  defp stringify(value), do: to_string(value)

  defp format_batch_message_entry(message) do
    # Accept both keyword lists and maps for batch entries (other batch helpers
    # already tolerate both via format_regular_opts).
    message =
      if is_map(message) and not is_struct(message), do: Map.to_list(message), else: message

    {attrs, opts} = Keyword.pop(message, :message_attributes, [])
    {system_attrs, opts} = Keyword.pop(opts, :message_system_attributes, [])

    opts
    |> format_regular_opts()
    |> maybe_put("MessageAttributes", build_message_attribute_map(attrs))
    |> maybe_put(
      "MessageSystemAttributes",
      build_message_attribute_map(system_attrs, &format_system_attribute_name/1)
    )
  end

  defp build_message_attribute_map(attr, name_fun \\ &to_string/1)

  defp build_message_attribute_map(%{} = attr, name_fun),
    do: build_message_attribute_map([attr], name_fun)

  defp build_message_attribute_map(attrs, name_fun) do
    attrs
    |> Enum.into(%{}, fn attr -> {name_fun.(attr.name), message_attribute_value(attr)} end)
  end

  # Message system attribute names come from a small AWS-controlled enum (currently only
  # AWSTraceHeader), so atoms go through the camelizing rules; strings pass through verbatim.
  defp format_system_attribute_name(name) when is_atom(name), do: format_param_key(name)
  defp format_system_attribute_name(name) when is_binary(name), do: name

  defp message_attribute_value(%{value: value, data_type: :binary} = attr) do
    # For the JSON protocol, blob fields must be base64-encoded strings in the
    # request payload. (Raw binaries will fail to JSON-encode.)
    %{"DataType" => message_data_type(attr), "BinaryValue" => Base.encode64(value)}
  end

  defp message_attribute_value(%{value: value} = attr) do
    %{"DataType" => message_data_type(attr), "StringValue" => to_string(value)}
  end

  defp message_data_type(%{data_type: data_type, custom_type: custom_type}) do
    format_param_key(data_type) <> "." <> custom_type
  end

  defp message_data_type(%{data_type: data_type}) do
    format_param_key(data_type)
  end
end
