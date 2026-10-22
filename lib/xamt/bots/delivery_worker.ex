defmodule Xamt.Bots.DeliveryWorker do
  @moduledoc false

  use GenServer
  require Logger
  import Ecto.Query
  alias Xamt.Repo
  alias Xamt.Bots.BotEvent

  @poll_interval_ms 2_000
  @batch_size 20
  @http_timeout_ms 5_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "当有新事件入队时，可主动唤醒 Worker 立即投递。"
  def trigger_sweep do
    if Process.whereis(__MODULE__) do
      send(__MODULE__, :sweep)
    end
  end

  @impl true
  def init(_opts) do
    schedule_sweep()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:sweep, state) do
    claim_and_dispatch_events()
    schedule_sweep()
    {:noreply, state}
  end

  defp schedule_sweep do
    Process.send_after(self(), :sweep, @poll_interval_ms)
  end

  defp claim_and_dispatch_events do
    now = DateTime.utc_now()

    events =
      case Repo.transact(fn ->
             ids =
               from(e in BotEvent,
                 where: e.status in ["pending", "failed"] and e.next_attempt_at <= ^now,
                 order_by: [asc: e.next_attempt_at],
                 limit: @batch_size,
                 lock: "FOR UPDATE SKIP LOCKED",
                 select: e.id
               )
               |> Repo.all()

             events =
               if ids == [] do
                 []
               else
                 from(e in BotEvent, where: e.id in ^ids)
                 |> Repo.update_all(set: [status: "processing", updated_at: now])

                 from(e in BotEvent, where: e.id in ^ids, preload: [:bot])
                 |> Repo.all()
               end

             {:ok, events}
           end) do
        {:ok, list} -> list
        _ -> []
      end

    Enum.each(events, fn event ->
      Task.Supervisor.start_child(Xamt.TaskSupervisor, fn ->
        deliver_single_event(event)
      end)
    end)
  end

  defp deliver_single_event(%BotEvent{bot: bot} = event) do
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
          execution_result: %{
            "http_status" => status_code,
            "duration_ms" => duration,
            "response_snippet" => String.slice(resp_body, 0, 200)
          },
          updated_at: DateTime.utc_now()
        ]
      )
    else
      error_reason ->
        handle_delivery_failure(event, error_reason)
    end
  end

  defp send_signed_webhook(bot, event) do
    timestamp = DateTime.utc_now() |> DateTime.to_unix() |> Integer.to_string()
    body_json = Jason.encode!(event.payload)

    mac =
      :crypto.mac(:hmac, :sha256, bot.signing_secret, "#{timestamp}.#{body_json}")
      |> Base.encode16(case: :lower)

    case Req.post(bot.webhook_url,
           body: body_json,
           headers: [
             {"content-type", "application/json"},
             {"user-agent", "Xamt-Bot-Webhook/1.0"},
             {"x-xamt-event", event.event_type},
             {"x-xamt-delivery", event.id},
             {"x-xamt-timestamp", timestamp},
             {"x-xamt-signature-256", "sha256=" <> mac}
           ],
           receive_timeout: @http_timeout_ms,
           connect_options: [timeout: 3_000],
           redirect: false
         ) do
      {:ok, %Req.Response{status: status_code, body: resp_body}} ->
        {:ok, status_code, response_body_to_string(resp_body)}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  defp response_body_to_string(body) when is_binary(body), do: body
  defp response_body_to_string(body), do: inspect(body)

  defp handle_delivery_failure(event, reason) do
    new_retry = event.retry_count + 1
    now = DateTime.utc_now()

    {new_status, next_attempt} =
      if new_retry >= event.max_retries do
        {"dead", now}
      else
        backoff_seconds = Integer.pow(2, new_retry - 1) * 15
        {"failed", DateTime.add(now, backoff_seconds, :second)}
      end

    error_detail =
      case reason do
        {:ok, code, body} -> %{"http_status" => code, "error" => String.slice(body, 0, 200)}
        {:error, err} -> %{"error" => to_string(err)}
        other -> %{"error" => inspect(other)}
      end

    from(e in BotEvent, where: e.id == ^event.id)
    |> Repo.update_all(
      set: [
        status: new_status,
        retry_count: new_retry,
        next_attempt_at: next_attempt,
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
      if Enum.any?(ips, &private_ip?/1) do
        {:error, :ssrf_blocked_private_ip}
      else
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
end
