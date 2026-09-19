defmodule Xamt.Notifications.WebPush do
  @moduledoc """
  Sends Web Push notifications when a user is @mentioned.

  Encryption and VAPID signing are done by `web_push_ex`; the HTTP POST uses
  Req. Work runs under `Xamt.TaskSupervisor` so `create_message/3` is not
  blocked by slow push services.
  """

  use Gettext, backend: XamtWeb.Gettext
  use XamtWeb, :verified_routes

  require Logger

  alias Xamt.Messages
  alias Xamt.Messages.Message
  alias Xamt.Notifications
  alias Xamt.Repo

  @doc """
  Pushes to every newly mentioned user except the author.
  """
  def notify_mentions(message, opts \\ [])

  def notify_mentions(%Message{} = message, opts) do
    if enabled?() do
      except = MapSet.new(Keyword.get(opts, :except, []))
      author_id = message.user_id

      message.mentioned_user_ids
      |> List.wrap()
      |> Enum.uniq()
      |> Enum.reject(&(&1 == author_id))
      |> Enum.reject(&MapSet.member?(except, &1))
      |> Enum.each(&send_mention_notification(&1, message))
    else
      :ok
    end
  end

  def notify_mentions(_, _), do: :ok

  @doc """
  Puts a mention push on the background supervisor.
  """
  def send_mention_notification(mentioned_user, message) do
    user_id = user_id(mentioned_user)

    run(fn -> deliver_mention(user_id, message) end)
  end

  defp deliver_mention(user_id, message) do
    subs = Notifications.list_user_subscriptions(user_id)

    if subs == [] do
      :ok
    else
      message = Repo.preload(message, [:user, channel: :server])
      payload = mention_payload(message)

      Enum.each(subs, &push_or_prune(&1, payload))
    end
  rescue
    error ->
      Logger.warning("web push failed: #{Exception.message(error)}")
      :ok
  end

  defp mention_payload(%Message{} = message) do
    username =
      case message.user do
        %{username: name} when is_binary(name) and name != "" -> name
        _ -> gettext("Someone")
      end

    Jason.encode!(%{
      title: gettext("Xamt: you were mentioned"),
      body: "#{username}: #{Messages.excerpt(message, 40)}",
      url: mention_url(message)
    })
  end

  defp mention_url(%{channel: %{slug: channel_slug, server: %{slug: server_slug}}})
       when is_binary(channel_slug) and is_binary(server_slug) do
    ~p"/servers/#{server_slug}/#{channel_slug}"
  end

  defp mention_url(_), do: ~p"/"

  defp push_or_prune(sub, payload) do
    sub_info = %{
      endpoint: sub.endpoint,
      keys: %{p256dh: sub.p256dh, auth: sub.auth}
    }

    case send_push(payload, sub_info) do
      {:ok, _} ->
        :ok

      {:error, %{status_code: status}} when status in [404, 410] ->
        Notifications.delete_subscription(sub.id)

      _error ->
        :ok
    end
  end

  defp send_push(payload, sub_info) do
    sender().(payload, sub_info)
  end

  defp sender do
    Keyword.get(config(), :sender, &default_send/2)
  end

  defp default_send(payload, %{endpoint: endpoint, keys: keys}) do
    subscription = %WebPushEx.Subscription{
      endpoint: URI.parse(endpoint),
      keys: %{
        p256dh: keys[:p256dh] || keys["p256dh"],
        auth: keys[:auth] || keys["auth"]
      }
    }

    request = WebPushEx.request(subscription, payload)

    case Req.post(
           URI.to_string(request.endpoint),
           Keyword.merge(
             [body: request.body, headers: request.headers, retry: false],
             req_options()
           )
         ) do
      {:ok, %{status: status}} when status in 200..299 ->
        {:ok, %{status_code: status}}

      {:ok, %{status: status}} ->
        {:error, %{status_code: status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp user_id(%{id: id}) when is_binary(id), do: id
  defp user_id(id) when is_binary(id), do: id

  defp run(fun) do
    if async?() do
      Task.Supervisor.start_child(Xamt.TaskSupervisor, fun)
    else
      fun.()
    end
  end

  defp enabled?, do: Keyword.get(config(), :enabled, true)
  defp async?, do: Keyword.get(config(), :async, true)
  defp req_options, do: Keyword.get(config(), :req_options, [])
  defp config, do: Application.get_env(:xamt, __MODULE__, [])
end
