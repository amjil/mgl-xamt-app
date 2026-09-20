defmodule XamtWeb.MessageApiController do
  @moduledoc """
  HTTP fallback for Service Worker Background Sync.

  LiveView's WebSocket is not visible to the worker thread, so queued offline
  messages are replayed here. Creating a message still broadcasts over PubSub,
  so any open LiveView receives `:new_message` as usual.
  """

  use XamtWeb, :controller

  alias Xamt.Channels
  alias Xamt.Channels.Channel
  alias Xamt.Messages
  alias Xamt.Servers

  def sync(conn, params) do
    scope = conn.assigns.current_scope
    channel_id = params["channel_id"]

    with {:ok, channel_id} <- cast_uuid(channel_id),
         %Channel{} = channel <- Channels.get_channel(channel_id),
         true <- Servers.member?(channel.server_id, scope.user.id) do
      case Messages.create_message(scope, channel.id, message_attrs(params)) do
        {:ok, _message} ->
          json(conn, %{status: "ok"})

        {:error, :rate_limited} ->
          conn
          |> put_status(:too_many_requests)
          |> json(%{status: "error", detail: "rate_limited"})

        {:error, :unauthorized} ->
          conn
          |> put_status(:forbidden)
          |> json(%{status: "error", detail: "forbidden"})

        {:error, _changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{status: "error", detail: "validation_failed"})
      end
    else
      :invalid_id ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{status: "error", detail: "invalid_channel"})

      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{status: "error", detail: "not_found"})

      false ->
        conn
        |> put_status(:forbidden)
        |> json(%{status: "error", detail: "forbidden"})
    end
  end

  defp message_attrs(params) do
    %{
      "content_html" => params["content_html"],
      "content_json" => params["content_json"],
      "content_type" => params["content_type"] || "rich_text",
      "content" => params["content"],
      "reply_to_id" => present_id(params["reply_to_id"])
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp present_id(id) when is_binary(id) and id != "", do: id
  defp present_id(_), do: nil

  defp cast_uuid(id) when is_binary(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> {:ok, uuid}
      :error -> :invalid_id
    end
  end

  defp cast_uuid(_), do: :invalid_id
end
