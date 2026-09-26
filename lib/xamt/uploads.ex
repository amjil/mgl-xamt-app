defmodule Xamt.Uploads do
  @moduledoc """
  Authorization for files stored under `priv/static/uploads`.

  Avatars and server icons are public (profile pages are unauthenticated).
  Message media requires membership of a server that references the file.
  """

  import Ecto.Query, warn: false

  alias Xamt.Accounts.User
  alias Xamt.Channels.Channel
  alias Xamt.Messages.Message
  alias Xamt.Repo
  alias Xamt.Servers
  alias Xamt.Servers.Server

  @filename_re ~r/\A[A-Za-z0-9._-]+\z/

  def safe_filename?(name) when is_binary(name), do: Regex.match?(@filename_re, name)
  def safe_filename?(_), do: false

  def public_path?(path) when is_binary(path) do
    Repo.exists?(from u in User, where: u.avatar == ^path) or
      Repo.exists?(from s in Server, where: s.icon == ^path)
  end

  def public_path?(_), do: false

  def visible_to_user?(path, user) when is_binary(path) do
    public_path?(path) or (user && member_of_referencing_server?(path, user.id))
  end

  def visible_to_user?(_, _), do: false

  defp member_of_referencing_server?(path, user_id) do
    like = "%" <> path <> "%"

    server_ids =
      from(m in Message,
        join: c in Channel,
        on: c.id == m.channel_id,
        where:
          fragment(
            "(?::text LIKE ?) OR (coalesce(?, '') LIKE ?)",
            m.content,
            ^like,
            m.content_html,
            ^like
          ),
        select: c.server_id,
        distinct: true
      )
      |> Repo.all()

    Enum.any?(server_ids, &Servers.member?(&1, user_id))
  end
end
