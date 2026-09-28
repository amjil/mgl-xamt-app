defmodule XamtWeb.SearchPaletteHook do
  @moduledoc false

  use XamtWeb, :verified_routes

  import Phoenix.Component
  import Phoenix.LiveView

  alias Xamt.Messages

  def on_mount(:default, _params, _session, socket) do
    {:cont,
     socket
     |> assign(:show_search, false)
     |> assign(:global_search_query, "")
     |> assign(:global_search_results, [])
     |> attach_hook(:search_palette, :handle_event, &handle_event/3)}
  end

  defp handle_event("open_search", _params, socket) do
    if signed_in?(socket) do
      {:halt, open_palette(socket)}
    else
      {:halt, socket}
    end
  end

  defp handle_event("close_search", _params, socket) do
    if socket.assigns.show_search do
      {:halt, close_palette(socket)}
    else
      {:cont, socket}
    end
  end

  defp handle_event("perform_search", %{"q" => query}, socket) do
    if signed_in?(socket) do
      {:halt, run_search(socket, query)}
    else
      {:halt, socket}
    end
  end

  defp handle_event("perform_search", _params, socket), do: {:halt, socket}

  defp handle_event("open_global_search_result", params, socket) do
    socket = close_palette(socket)

    if socket.view == XamtWeb.ServerLive and socket.assigns[:member?] do
      {:cont, socket}
    else
      case jump_path(params) do
        nil -> {:halt, socket}
        path -> {:halt, push_navigate(socket, to: path)}
      end
    end
  end

  defp handle_event(_event, _params, socket), do: {:cont, socket}

  defp open_palette(socket) do
    assign(socket, show_search: true, global_search_results: [], global_search_query: "")
  end

  defp close_palette(socket) do
    assign(socket, show_search: false, global_search_results: [], global_search_query: "")
  end

  defp run_search(socket, query) do
    query = query |> to_string() |> String.trim()

    results =
      if query == "" do
        []
      else
        Messages.search_user_messages(socket.assigns.current_scope, query)
      end

    assign(socket, global_search_query: query, global_search_results: results)
  end

  defp jump_path(%{"id" => id, "server-slug" => server, "channel-slug" => channel})
       when is_binary(id) and is_binary(server) and is_binary(channel) and
              id != "" and server != "" and channel != "" do
    ~p"/servers/#{server}/#{channel}?highlight=#{id}"
  end

  defp jump_path(_), do: nil

  defp signed_in?(socket) do
    match?(%{user: %{id: _}}, socket.assigns[:current_scope])
  end
end
