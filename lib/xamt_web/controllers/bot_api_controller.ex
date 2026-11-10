defmodule XamtWeb.BotApiController do
  use XamtWeb, :controller

  import Phoenix.HTML, only: [html_escape: 1]

  alias Xamt.Accounts.Scope
  alias Xamt.{Bots, Channels, Messages}
  alias Xamt.Messages.RateLimiter

  plug :require_bot_token when action != :health

  def me(conn, _params) do
    json(conn, %{ok: true, data: Bots.me_payload(conn.assigns.bot_token)})
  end

  def list_channels(conn, _params) do
    token = conn.assigns.bot_token
    channels = Bots.list_authorized_channels(token)

    json(conn, %{
      ok: true,
      data:
        Enum.map(channels, fn ch ->
          %{
            id: ch.id,
            name: ch.name,
            slug: ch.slug,
            server_id: ch.server_id
          }
        end)
    })
  end

  def show_channel(conn, %{"channel_id" => channel_id}) do
    token = conn.assigns.bot_token

    case Bots.get_authorized_channel(token, channel_id) do
      {:ok, ch} ->
        json(conn, %{
          ok: true,
          data: %{id: ch.id, name: ch.name, slug: ch.slug, server_id: ch.server_id}
        })

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{ok: false, error: "channel_not_found"})

      {:error, _} ->
        conn |> put_status(:forbidden) |> json(%{ok: false, error: "channel_not_authorized"})
    end
  end

  def list_messages(conn, %{"channel_id" => channel_id} = params) do
    token = conn.assigns.bot_token

    with {:ok, channel} <- Bots.get_authorized_channel(token, channel_id),
         :ok <- Bots.authorize_channel_action(token, channel, "channel.messages.read") do
      opts =
        []
        |> maybe_put_opt(:limit, parse_limit(params["limit"]))
        |> maybe_put_opt(:before_id, params["before_id"])

      messages = Messages.list_messages(channel_id, opts)

      json(conn, %{
        ok: true,
        data: Enum.map(messages, &serialize_message/1)
      })
    else
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{ok: false, error: "channel_not_found"})

      {:error, :insufficient_scope} ->
        conn
        |> put_status(:forbidden)
        |> json(%{ok: false, error: "missing_scope_channel_messages_read"})

      {:error, _} ->
        conn |> put_status(:forbidden) |> json(%{ok: false, error: "channel_not_authorized"})
    end
  end

  @doc """
  POST /api/v1/bot/channels/:channel_id/messages

  Authorization: Bearer xamt_bot_xxxx
  Body: `{"body": "...", "reply_to_id": "...", "nonce": "..."}`
  """
  def create_message(conn, %{"channel_id" => channel_id} = params) do
    token = conn.assigns.bot_token
    nonce = blank_to_nil(Map.get(params, "nonce"))

    case maybe_existing_nonce(token, nonce) do
      {:replay, message} ->
        json(conn, %{ok: true, data: serialize_message(message), replayed: true})

      :continue ->
        do_create_message(conn, token, channel_id, params, nonce)
    end
  end

  defp do_create_message(conn, token, channel_id, params, nonce) do
    with channel when not is_nil(channel) <- Channels.get_channel(channel_id),
         :ok <- Bots.authorize_channel_action(token, channel, "channel.messages.send"),
         :ok <- RateLimiter.check_rate(token.bot.bot_user_id),
         {:ok, message} <-
           Messages.create_message(
             Scope.for_user(token.bot.bot_user),
             channel_id,
             bot_message_attrs(params)
           ),
         :ok <- persist_nonce(token, nonce, message) do
      _ = Bots.log_message_action(token, "message.sent", message, %{"nonce" => nonce})

      conn
      |> put_status(:created)
      |> json(%{ok: true, data: serialize_message(message)})
    else
      {:error, :insufficient_scope} ->
        conn
        |> put_status(:forbidden)
        |> json(%{ok: false, error: "missing_scope_channel_messages_send"})

      {:error, :channel_not_authorized} ->
        conn
        |> put_status(:forbidden)
        |> json(%{ok: false, error: "channel_not_in_installation_scope"})

      {:error, :server_mismatch} ->
        conn
        |> put_status(:forbidden)
        |> json(%{ok: false, error: "channel_not_in_installation_scope"})

      {:error, :rate_limited} ->
        conn |> put_status(:too_many_requests) |> json(%{ok: false, error: "rate_limited"})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: "validation_failed", details: translate_errors(changeset)})

      {:error, _} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: "validation_failed"})

      nil ->
        conn |> put_status(:not_found) |> json(%{ok: false, error: "channel_not_found"})
    end
  end

  def update_message(conn, %{"message_id" => message_id} = params) do
    token = conn.assigns.bot_token

    with {:ok, message} <- fetch_own_bot_message(token, message_id),
         channel when not is_nil(channel) <- Channels.get_channel(message.channel_id),
         :ok <- Bots.authorize_channel_action(token, channel, "channel.messages.send"),
         {:ok, updated} <-
           Messages.update_message(
             Scope.for_user(token.bot.bot_user),
             message_id,
             bot_message_attrs(params)
           ) do
      _ = Bots.log_message_action(token, "message.updated", updated)
      json(conn, %{ok: true, data: serialize_message(updated)})
    else
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{ok: false, error: "message_not_found"})

      {:error, :forbidden} ->
        conn |> put_status(:forbidden) |> json(%{ok: false, error: "not_message_author"})

      {:error, :insufficient_scope} ->
        conn |> put_status(:forbidden) |> json(%{ok: false, error: "missing_scope"})

      {:error, :channel_not_authorized} ->
        conn |> put_status(:forbidden) |> json(%{ok: false, error: "channel_not_authorized"})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: "validation_failed", details: translate_errors(changeset)})

      {:error, _} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: "validation_failed"})

      nil ->
        conn |> put_status(:not_found) |> json(%{ok: false, error: "channel_not_found"})
    end
  end

  def delete_message(conn, %{"message_id" => message_id}) do
    token = conn.assigns.bot_token

    with {:ok, message} <- fetch_bot_deletable_message(token, message_id),
         channel when not is_nil(channel) <- Channels.get_channel(message.channel_id),
         :ok <- authorize_bot_delete(token, channel, message),
         {:ok, deleted} <-
           Messages.delete_message(Scope.for_user(token.bot.bot_user), message_id) do
      _ = Bots.log_message_action(token, "message.deleted", deleted)
      json(conn, %{ok: true, data: serialize_message(deleted)})
    else
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{ok: false, error: "message_not_found"})

      {:error, :forbidden} ->
        conn |> put_status(:forbidden) |> json(%{ok: false, error: "not_allowed"})

      {:error, :insufficient_scope} ->
        conn |> put_status(:forbidden) |> json(%{ok: false, error: "missing_scope"})

      {:error, _} ->
        conn |> put_status(:forbidden) |> json(%{ok: false, error: "not_allowed"})

      nil ->
        conn |> put_status(:not_found) |> json(%{ok: false, error: "channel_not_found"})
    end
  end

  def list_event_subscriptions(conn, _params) do
    subs = Bots.list_event_subscriptions(conn.assigns.bot_token)

    json(conn, %{
      ok: true,
      data:
        Enum.map(subs, fn s ->
          %{
            id: s.id,
            event_type: s.event_type,
            channel_id: s.channel_id,
            is_enabled: s.is_enabled
          }
        end)
    })
  end

  def create_interaction(conn, params) do
    case Bots.create_interaction(conn.assigns.bot_token, params) do
      {:ok, interaction} ->
        conn
        |> put_status(:created)
        |> json(%{
          ok: true,
          data: %{
            id: interaction.id,
            action_key: interaction.action_key,
            expires_at: interaction.expires_at,
            status: interaction.status
          }
        })

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{ok: false, error: "channel_not_found"})

      {:error, :insufficient_scope} ->
        conn |> put_status(:forbidden) |> json(%{ok: false, error: "missing_scope"})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: "validation_failed", details: translate_errors(changeset)})

      {:error, _} ->
        conn |> put_status(:forbidden) |> json(%{ok: false, error: "not_allowed"})
    end
  end

  def respond_interaction(conn, params) do
    interaction_id =
      Map.get(params, "interaction_id") || Map.get(params, "id")

    payload = Map.get(params, "response") || Map.get(params, "payload") || %{}

    if is_nil(interaction_id) do
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{ok: false, error: "missing_interaction_id"})
    else
      case Bots.respond_to_interaction(interaction_id, conn.assigns.bot_token, payload) do
        {:ok, interaction} ->
          json(conn, %{
            ok: true,
            data: %{
              id: interaction.id,
              status: interaction.status,
              responded_at: interaction.responded_at
            }
          })

        {:error, :not_found} ->
          conn |> put_status(:not_found) |> json(%{ok: false, error: "interaction_not_found"})

        {:error, :expired} ->
          conn |> put_status(:gone) |> json(%{ok: false, error: "interaction_expired"})

        {:error, :already_responded} ->
          conn |> put_status(:conflict) |> json(%{ok: false, error: "already_responded"})

        {:error, :forbidden} ->
          conn |> put_status(:forbidden) |> json(%{ok: false, error: "forbidden"})

        {:error, _} ->
          conn |> put_status(:unprocessable_entity) |> json(%{ok: false, error: "invalid_status"})
      end
    end
  end

  defp require_bot_token(conn, _opts) do
    with {:ok, raw_token} <- extract_bearer_token(conn),
         {:ok, bot_token} <- Bots.authenticate_token(raw_token) do
      assign(conn, :bot_token, bot_token)
    else
      {:error, :bot_api_disabled} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{ok: false, error: "bot_api_disabled"})
        |> halt()

      {:error, :invalid_token} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{ok: false, error: "invalid_or_revoked_token"})
        |> halt()
    end
  end

  defp maybe_existing_nonce(_token, nil), do: :continue

  defp maybe_existing_nonce(token, nonce) do
    case Bots.find_message_by_nonce(token.bot_installation_id, nonce) do
      %{message: message} when not is_nil(message) -> {:replay, message}
      _ -> :continue
    end
  end

  defp persist_nonce(_token, nil, _message), do: :ok

  defp persist_nonce(token, nonce, message) do
    case Bots.remember_nonce(token.bot_installation_id, nonce, message.id) do
      {:ok, _} -> :ok
      {:error, _} -> :ok
    end
  end

  defp fetch_own_bot_message(token, message_id) do
    case Messages.get_message_for_user(Scope.for_user(token.bot.bot_user), message_id) do
      {:ok, message} ->
        if message.user_id == token.bot.bot_user_id do
          {:ok, message}
        else
          {:error, :forbidden}
        end

      error ->
        error
    end
  end

  defp fetch_bot_deletable_message(token, message_id) do
    case Messages.get_message_for_user(Scope.for_user(token.bot.bot_user), message_id) do
      {:ok, message} -> {:ok, message}
      error -> error
    end
  end

  defp authorize_bot_delete(token, channel, message) do
    cond do
      message.user_id == token.bot.bot_user_id ->
        Bots.authorize_channel_action(token, channel, "channel.messages.send")

      true ->
        Bots.authorize_channel_action(token, channel, "channel.messages.manage")
    end
  end

  defp bot_message_attrs(params) do
    body = Map.get(params, "body") || Map.get(params, "content") || ""
    body = to_string(body)
    escaped = body |> html_escape() |> Phoenix.HTML.safe_to_string()
    content_html = if String.trim(body) == "", do: "", else: "<p>#{escaped}</p>"

    %{
      "content_html" => content_html,
      "reply_to_id" => Map.get(params, "reply_to_id")
    }
  end

  defp serialize_message(message) do
    %{
      id: message.id,
      channel_id: message.channel_id,
      body: Messages.plain_text(message),
      author_id: message.user_id,
      author_type: if(match?(%{user: %{is_bot: true}}, message), do: "bot", else: "user"),
      deleted_at: message.deleted_at,
      inserted_at: message.inserted_at,
      updated_at: message.updated_at
    }
  end

  defp translate_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  defp extract_bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> {:ok, String.trim(token)}
      _ -> {:error, :invalid_token}
    end
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value) when is_binary(value), do: value
  defp blank_to_nil(_), do: nil

  defp parse_limit(nil), do: nil

  defp parse_limit(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, _} when n > 0 and n <= 100 -> n
      _ -> nil
    end
  end

  defp parse_limit(value) when is_integer(value) and value > 0 and value <= 100, do: value
  defp parse_limit(_), do: nil

  defp maybe_put_opt(opts, _key, nil), do: opts
  defp maybe_put_opt(opts, key, value), do: Keyword.put(opts, key, value)
end
