defmodule Xamt.Uploads do
  @moduledoc """
  Authorization for upload URLs (`/uploads/:filename`).

  Bytes live in `Xamt.Storage` (local disk or S3). Avatars and server icons are
  public once a profile or server row points at them. Message media is readable
  only by someone who can view the server that received the upload. Mentioning
  the path in another server does not grant access.
  """

  import Ecto.Query, warn: false

  alias Xamt.Accounts.User
  alias Xamt.Repo
  alias Xamt.Servers
  alias Xamt.Servers.Server
  alias Xamt.Uploads.Grant

  @filename_re ~r/\A[A-Za-z0-9._-]+\z/

  def safe_filename?(name) when is_binary(name), do: Regex.match?(@filename_re, name)
  def safe_filename?(_), do: false

  @doc """
  Records that `filename` was uploaded into `server_id` by `user_id`.

  The row is the authorization source for later `GET /uploads/:filename`.
  A message that merely quotes the path does not create a grant.
  """
  def grant_server_file(filename, server_id, user_id)
      when is_binary(filename) and is_binary(server_id) and is_binary(user_id) do
    %Grant{}
    |> Ecto.Changeset.change(filename: filename, server_id: server_id, user_id: user_id)
    |> Ecto.Changeset.validate_required([:filename, :server_id, :user_id])
    |> Ecto.Changeset.validate_format(:filename, @filename_re)
    |> Ecto.Changeset.unique_constraint(:filename)
    |> Repo.insert()
  end

  def grant_server_file(_, _, _), do: {:error, :invalid_grant}

  @doc """
  Drops the grant for `filename`. Missing rows are ignored.
  """
  def revoke_server_file(filename) when is_binary(filename) do
    Repo.delete_all(from g in Grant, where: g.filename == ^filename)
    :ok
  end

  def revoke_server_file(_), do: :ok

  def public_path?(path) when is_binary(path) do
    Repo.exists?(from u in User, where: u.avatar == ^path) or
      Repo.exists?(from s in Server, where: s.icon == ^path)
  end

  def public_path?(_), do: false

  def visible_to_user?(path, user) when is_binary(path) do
    public_path?(path) or (match?(%User{}, user) and granted_to_user?(path, user.id))
  end

  def visible_to_user?(_, _), do: false

  defp granted_to_user?(path, user_id) do
    filename = Path.basename(path)

    if safe_filename?(filename) do
      case Repo.get_by(Grant, filename: filename) do
        %Grant{server_id: server_id} -> Servers.can?(server_id, user_id, :view_channel)
        _ -> false
      end
    else
      false
    end
  end
end
