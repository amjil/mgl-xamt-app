defmodule Xamt.Messages.Mentions do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Xamt.Accounts.User
  alias Xamt.Channels.Channel
  alias Xamt.Messages.{HtmlSanitizer, Mention}
  alias Xamt.Repo
  alias Xamt.Servers.ServerMember

  @mention_tag_re ~r/<(span|a)\b([^>]*\bdata-mention-id=["']([^"']+)["'][^>]*)>(.*?)<\/\1>/si
  @mention_id_re ~r/data-mention-id=["']([0-9a-fA-F-]{36})["']/

  def prepare(html, channel_id) when is_binary(html) and is_binary(channel_id) do
    html = HtmlSanitizer.sanitize(html)
    server_id = channel_server_id(channel_id)
    ids = extract_mention_ids(html)
    users = mentionable_users(server_id, ids)
    {rewrite_mention_tags(html, users), Map.keys(users)}
  end

  def prepare(_html, _channel_id), do: {"", []}

  def replace(message_id, user_ids) do
    from(m in Mention, where: m.message_id == ^message_id) |> Repo.delete_all()

    now = DateTime.utc_now(:second)

    entries =
      user_ids
      |> Enum.uniq()
      |> Enum.map(fn user_id ->
        %{
          id: Ecto.UUID.generate(),
          message_id: message_id,
          user_id: user_id,
          inserted_at: now,
          updated_at: now
        }
      end)

    if entries != [] do
      Repo.insert_all(Mention, entries)
    end

    :ok
  end

  def extract_mention_ids(html) do
    @mention_id_re
    |> Regex.scan(html)
    |> Enum.map(fn [_, id] -> id end)
    |> Enum.uniq()
    |> Enum.filter(&valid_uuid?/1)
  end

  def valid_uuid?(id) do
    match?({:ok, _}, Ecto.UUID.cast(id))
  end

  def mentionable_users(_server_id, []), do: %{}

  def mentionable_users(server_id, ids) when is_binary(server_id) do
    from(u in User,
      join: m in ServerMember,
      on: m.user_id == u.id,
      where: m.server_id == ^server_id and u.id in ^ids,
      select: u
    )
    |> Repo.all()
    |> Map.new(&{&1.id, &1})
  end

  def mentionable_users(_server_id, _ids), do: %{}

  def rewrite_mention_tags(html, users_by_id) do
    Regex.replace(@mention_tag_re, html, fn _full, _tag, _attrs, id, inner ->
      case Map.get(users_by_id, id) do
        %User{} = user -> mention_chip_html(user)
        _ -> strip_tags(inner)
      end
    end)
  end

  def mention_chip_html(%User{id: id, username: username} = user) do
    handle = html_escape(username || "")
    label = html_escape(mention_label(user))

    ~s(<a class="xamt-mention mongol-text" href="/profile/#{handle}" data-phx-link="redirect" data-phx-link-state="push" data-mention-id="#{id}" data-mention-username="#{handle}">@#{label}</a>)
  end

  defp mention_label(%User{display_name: name, username: username}) do
    trimmed = name |> to_string() |> String.trim()
    if trimmed != "", do: trimmed, else: to_string(username || "")
  end

  def strip_tags(html) when is_binary(html) do
    html
    |> String.replace(~r/<[^>]+>/, "")
    |> html_escape()
  end

  def html_escape(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end

  defp channel_server_id(channel_id) do
    Repo.one(from c in Channel, where: c.id == ^channel_id, select: c.server_id)
  end
end
