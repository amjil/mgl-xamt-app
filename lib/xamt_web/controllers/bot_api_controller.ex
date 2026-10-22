defmodule XamtWeb.BotApiController do
  use XamtWeb, :controller

  import Phoenix.HTML, only: [html_escape: 1]

  alias Xamt.Accounts.Scope
  alias Xamt.{Bots, Channels, Messages}
  alias Xamt.Messages.RateLimiter

  @doc """
  POST /api/v1/bot/channels/:channel_id/messages

  Authorization: Bearer xamt_bot_xxxx
  Body: `{"body": "...", "reply_to_id": "..."}`
  """
  def create_message(conn, %{"channel_id" => channel_id} = params) do
    with {:ok, raw_token} <- extract_bearer_token(conn),
         {:ok, bot_token} <- Bots.authenticate_token(raw_token),
         channel when not is_nil(channel) <- Channels.get_channel(channel_id),
         :ok <- Bots.authorize_channel_action(bot_token, channel, "channel.messages.send"),
         :ok <- RateLimiter.check_rate(bot_token.bot.bot_user_id),
         {:ok, message} <-
           Messages.create_message(
             Scope.for_user(bot_token.bot.bot_user),
             channel_id,
             bot_message_attrs(params)
           ) do
      conn
      |> put_status(:created)
      |> json(%{
        ok: true,
        data: %{
          id: message.id,
          channel_id: message.channel_id,
          body: Messages.plain_text(message),
          inserted_at: message.inserted_at
        }
      })
    else
      {:error, :invalid_token} ->
        conn |> put_status(:unauthorized) |> json(%{ok: false, error: "invalid_or_revoked_token"})

      {:error, :insufficient_scope} ->
        conn
        |> put_status(:forbidden)
        |> json(%{ok: false, error: "missing_scope_channel_messages_send"})

      {:error, :channel_not_authorized} ->
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

  defp bot_message_attrs(params) do
    body = Map.get(params, "body", "") |> to_string()
    escaped = body |> html_escape() |> Phoenix.HTML.safe_to_string()
    content_html = if String.trim(body) == "", do: "", else: "<p>#{escaped}</p>"

    %{
      "content_html" => content_html,
      "reply_to_id" => Map.get(params, "reply_to_id")
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
end
