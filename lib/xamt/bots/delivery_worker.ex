defmodule Xamt.Bots.DeliveryWorker do
  @moduledoc """
  Delivers a single `bot_events` row to the bot webhook over HTTPS.

  Jobs are inserted in the same DB transaction as the outbox row (see
  `Xamt.Bots.Dispatcher`). Retries and backoff are handled by Oban; the
  event row mirrors status for the admin UI.
  """

  use Oban.Worker,
    queue: :bot_webhook_delivery,
    max_attempts: 5,
    unique: [
      period: :infinity,
      keys: [:event_id],
      states: [:available, :scheduled, :executing, :retryable]
    ]

  require Logger
  import Ecto.Query
  alias Xamt.Repo
  alias Xamt.Bots.BotEvent

  @doc """
  Builds an Oban job changeset for a pending bot event.
  """
  def enqueue_changeset(event_id, opts \\ []) when is_binary(event_id) do
    max_attempts =
      Keyword.get_lazy(opts, :max_attempts, fn ->
        Keyword.get(worker_config(), :max_attempts, 5)
      end)

    %{"event_id" => event_id}
    |> new(max_attempts: max_attempts)
  end

  @doc """
  Inserts (or re-inserts) a delivery job for a bot event.
  """
  def enqueue(event_id, opts \\ []) when is_binary(event_id) do
    event_id
    |> enqueue_changeset(opts)
    |> Oban.insert()
  end

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) do
    trunc(:math.pow(2, attempt - 1) * 15)
  end

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"event_id" => event_id},
        attempt: attempt,
        max_attempts: max_attempts
      }) do
    if Application.get_env(:xamt, :bot_webhook_delivery_enabled, true) do
      deliver_event(event_id, attempt, max_attempts)
    else
      {:cancel, :webhook_delivery_disabled}
    end
  end

  defp deliver_event(event_id, attempt, max_attempts) do
    now = DateTime.utc_now()

    case Repo.get(BotEvent, event_id) |> maybe_preload_bot() do
      nil ->
        {:cancel, :event_not_found}

      %BotEvent{status: "delivered"} ->
        :ok

      %BotEvent{bot: nil} ->
        mark_dead(event_id, %{"error" => "bot_missing"}, now)
        {:cancel, :bot_missing}

      %BotEvent{bot: bot} = event ->
        mark_processing(event_id, attempt, now)

        start_time = System.monotonic_time(:millisecond)

        with :ok <- validate_ssrf_safe_url(bot.webhook_url),
             {:ok, status_code, resp_body} <- send_signed_webhook(bot, event),
             true <- status_code in 200..299 do
          duration = System.monotonic_time(:millisecond) - start_time

          from(e in BotEvent, where: e.id == ^event.id)
          |> Repo.update_all(
            set: [
              status: "delivered",
              delivered_at: DateTime.utc_now(),
              retry_count: attempt - 1,
              execution_result: %{
                "http_status" => status_code,
                "duration_ms" => duration,
                "response_snippet" => String.slice(resp_body, 0, 200)
              },
              updated_at: DateTime.utc_now()
            ]
          )

          :ok
        else
          error_reason ->
            handle_delivery_failure(event, attempt, max_attempts, error_reason)
        end
    end
  end

  defp maybe_preload_bot(nil), do: nil
  defp maybe_preload_bot(event), do: Repo.preload(event, :bot)

  defp mark_processing(event_id, attempt, now) do
    from(e in BotEvent, where: e.id == ^event_id)
    |> Repo.update_all(
      set: [
        status: "processing",
        retry_count: max(attempt - 1, 0),
        updated_at: now
      ]
    )
  end

  defp send_signed_webhook(bot, event) do
    timestamp = DateTime.utc_now() |> DateTime.to_unix() |> Integer.to_string()
    body_json = Jason.encode!(event.payload)
    timeout_ms = Keyword.get(worker_config(), :timeout_ms, 5_000)

    mac =
      :crypto.mac(:hmac, :sha256, bot.signing_secret, "#{timestamp}.#{body_json}")
      |> Base.encode16(case: :lower)

    req_opts =
      Keyword.merge(
        [
          body: body_json,
          headers: [
            {"content-type", "application/json"},
            {"user-agent", "Xamt-Bot-Webhook/1.0"},
            {"x-xamt-event", event.event_type},
            {"x-xamt-delivery", event.id},
            {"x-xamt-timestamp", timestamp},
            {"x-xamt-signature-256", "sha256=" <> mac}
          ],
          receive_timeout: timeout_ms,
          connect_options: [timeout: 3_000],
          redirect: false
        ],
        Keyword.get(worker_config(), :req_options, [])
      )

    case Req.post(bot.webhook_url, req_opts) do
      {:ok, %Req.Response{status: status_code, body: resp_body}} ->
        {:ok, status_code, response_body_to_string(resp_body)}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  defp response_body_to_string(body) when is_binary(body), do: body
  defp response_body_to_string(body), do: inspect(body)

  defp handle_delivery_failure(event, attempt, max_attempts, reason) do
    now = DateTime.utc_now()
    event_max = event.max_retries || max_attempts
    exhausted? = attempt >= max_attempts or attempt >= event_max

    error_detail =
      case reason do
        {:ok, code, body} -> %{"http_status" => code, "error" => String.slice(body, 0, 200)}
        {:error, err} -> %{"error" => to_string(err)}
        other -> %{"error" => inspect(other)}
      end

    if exhausted? do
      mark_dead(event.id, error_detail, now)
    else
      backoff_seconds = trunc(:math.pow(2, attempt - 1) * 15)

      from(e in BotEvent, where: e.id == ^event.id)
      |> Repo.update_all(
        set: [
          status: "failed",
          retry_count: attempt,
          next_attempt_at: DateTime.add(now, backoff_seconds, :second),
          execution_result: error_detail,
          updated_at: now
        ]
      )
    end

    {:error, error_detail}
  end

  defp mark_dead(event_id, error_detail, now) do
    from(e in BotEvent, where: e.id == ^event_id)
    |> Repo.update_all(
      set: [
        status: "dead",
        next_attempt_at: now,
        execution_result: error_detail,
        updated_at: now
      ]
    )
  end

  defp validate_ssrf_safe_url(url_str) do
    uri = URI.parse(url_str)

    with true <- uri.scheme in ["http", "https"],
         host when is_binary(host) <- uri.host,
         {:ok, ips} <- :inet.getaddrs(String.to_charlist(host), :inet) do
      cond do
        allow_private_hosts?() ->
          :ok

        Enum.any?(ips, &private_ip?/1) ->
          {:error, :ssrf_blocked_private_ip}

        true ->
          :ok
      end
    else
      _ -> {:error, :invalid_webhook_host}
    end
  end

  defp private_ip?({127, _, _, _}), do: true
  defp private_ip?({10, _, _, _}), do: true
  defp private_ip?({172, b, _, _}) when b in 16..31, do: true
  defp private_ip?({192, 168, _, _}), do: true
  defp private_ip?({169, 254, _, _}), do: true
  defp private_ip?({0, 0, 0, 0}), do: true
  defp private_ip?(_), do: false

  # Local Echo Bot / tunnel-less development only. Keep false in production.
  defp allow_private_hosts? do
    Keyword.get(worker_config(), :allow_private_hosts, false) == true
  end

  defp worker_config, do: Application.get_env(:xamt, __MODULE__, [])
end
