defmodule Xamt.Bots do
  @moduledoc """
  Bot app creation, installation, token verification, and channel action authorization.
  """

  import Ecto.Query
  alias Xamt.Repo
  alias Xamt.Accounts.User
  alias Xamt.Servers.ServerMember
  alias Xamt.Bots.{Bot, BotInstallation, BotToken, BotSubscription}

  @doc """
  Creates a bot app and a shadow user account for it to post messages.
  """
  def create_bot(creator_user, attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:bot_user, fn repo, _ ->
      bot_uid = System.unique_integer([:positive])
      name = Map.get(attrs, "name") || Map.get(attrs, :name) || "Bot"

      %User{
        email: "bot_#{bot_uid}@bots.xamt.local",
        username: "bot_#{bot_uid}",
        display_name: "#{name} [BOT]",
        is_bot: true,
        confirmed_at: DateTime.utc_now(:second)
      }
      |> repo.insert()
    end)
    |> Ecto.Multi.run(:bot, fn repo, %{bot_user: bot_user} ->
      attrs =
        attrs
        |> Map.new(fn {k, v} -> {to_string(k), v} end)
        |> Map.put("creator_id", creator_user.id)
        |> Map.put("bot_user_id", bot_user.id)

      %Bot{}
      |> Bot.changeset(attrs)
      |> repo.insert()
    end)
    |> Repo.transaction()
  end

  @doc """
  Installs a bot on a server and issues a plaintext token (returned only once at install time).
  """
  def install_bot(bot_id, server_id, installed_by_user, opts \\ []) do
    granted_scopes = Keyword.get(opts, :granted_scopes, [])
    subscribed_events = Keyword.get(opts, :subscribed_events, [])
    allowed_channel_ids = Keyword.get(opts, :allowed_channel_ids, [])
    channel_id = Keyword.get(opts, :channel_id, nil)

    bot = Repo.get!(Bot, bot_id)

    Ecto.Multi.new()
    |> Ecto.Multi.insert(:installation, fn _ ->
      BotInstallation.changeset(%BotInstallation{}, %{
        bot_id: bot_id,
        server_id: server_id,
        channel_id: channel_id,
        installed_by_id: installed_by_user.id,
        granted_scopes: granted_scopes,
        allowed_channel_ids: allowed_channel_ids,
        status: "enabled"
      })
    end)
    |> Ecto.Multi.run(:bot_member, fn repo, %{installation: _inst} ->
      ensure_bot_server_member(repo, server_id, bot.bot_user_id)
    end)
    |> Ecto.Multi.run(:subscriptions, fn repo, %{installation: inst} ->
      subs =
        Enum.map(subscribed_events, fn ev ->
          {:ok, sub} =
            %BotSubscription{}
            |> BotSubscription.changeset(%{
              bot_installation_id: inst.id,
              channel_id: channel_id,
              event_type: ev,
              is_enabled: true
            })
            |> repo.insert()

          sub
        end)

      {:ok, subs}
    end)
    |> Ecto.Multi.run(:token, fn repo, %{installation: inst} ->
      issue_installation_token(repo, inst, granted_scopes)
    end)
    |> Repo.transaction()
  end

  defp ensure_bot_server_member(repo, server_id, bot_user_id) do
    case repo.get_by(ServerMember, server_id: server_id, user_id: bot_user_id) do
      %ServerMember{} = member ->
        {:ok, member}

      nil ->
        now = DateTime.utc_now(:second)

        %ServerMember{}
        |> ServerMember.changeset(%{
          server_id: server_id,
          user_id: bot_user_id,
          role: "member",
          joined_at: now
        })
        |> repo.insert()
    end
  end

  @doc """
  Issues an API token: returns `{:ok, %{raw_token: ..., record: %BotToken{}}}`; only SHA-256 hash is stored.
  """
  def issue_installation_token(repo \\ Repo, %BotInstallation{} = inst, scopes) do
    raw_random = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
    raw_token = "xamt_bot_" <> raw_random
    prefix = String.slice(raw_token, 0, 15)
    hash = :crypto.hash(:sha256, raw_token)
    now = DateTime.utc_now()

    token_record = %BotToken{
      bot_id: inst.bot_id,
      bot_installation_id: inst.id,
      token_hash: hash,
      token_prefix: prefix,
      scopes: scopes,
      inserted_at: now
    }

    case repo.insert(token_record) do
      {:ok, record} -> {:ok, %{raw_token: raw_token, record: record}}
      error -> error
    end
  end

  @doc """
  Validates a Bearer token for bot API requests; returns preloaded bot and installation context.
  """
  def authenticate_token(raw_token) when is_binary(raw_token) do
    hash = :crypto.hash(:sha256, raw_token)
    now = DateTime.utc_now()

    query =
      from t in BotToken,
        join: i in assoc(t, :bot_installation),
        join: b in assoc(t, :bot),
        join: u in assoc(b, :bot_user),
        where: t.token_hash == ^hash and is_nil(t.revoked_at),
        where: is_nil(t.expires_at) or t.expires_at > ^now,
        where: i.status == "enabled" and b.status == "active",
        preload: [bot_installation: i, bot: {b, bot_user: u}]

    case Repo.one(query) do
      nil -> {:error, :invalid_token}
      token -> {:ok, token}
    end
  end

  @doc """
  Authorizes a channel action: checks token and installation scopes for the target channel.
  """
  def authorize_channel_action(%BotToken{} = token, target_channel, required_scope) do
    inst = token.bot_installation

    cond do
      target_channel.server_id != inst.server_id ->
        {:error, :server_mismatch}

      required_scope not in token.scopes or required_scope not in inst.granted_scopes ->
        {:error, :insufficient_scope}

      not channel_allowed?(inst, target_channel.id) ->
        {:error, :channel_not_authorized}

      true ->
        :ok
    end
  end

  defp channel_allowed?(%BotInstallation{channel_id: inst_cid}, target_cid)
       when not is_nil(inst_cid) do
    inst_cid == target_cid
  end

  defp channel_allowed?(%BotInstallation{allowed_channel_ids: []}, _target_cid), do: true

  defp channel_allowed?(%BotInstallation{allowed_channel_ids: allowed}, target_cid) do
    target_cid in allowed
  end

  @doc "Lists bot installations on a server (preloads bot, subscriptions, active token prefixes)."
  def list_server_installations(server_id) do
    from(i in BotInstallation,
      where: i.server_id == ^server_id,
      order_by: [asc: i.inserted_at],
      preload: [
        :bot,
        :subscriptions,
        tokens: ^from(t in BotToken, where: is_nil(t.revoked_at), order_by: [desc: t.inserted_at])
      ]
    )
    |> Repo.all()
  end

  @doc "Creates a new bot and installs it on the given server in one step."
  def create_and_install_bot(admin_user, server_id, bot_attrs, install_opts) do
    with {:ok, %{bot: bot}} <- create_bot(admin_user, bot_attrs),
         {:ok, result} <- install_bot(bot.id, server_id, admin_user, install_opts) do
      {:ok, Map.put(result, :bot, bot)}
    end
  end

  @doc """
  Updates installation scopes, channel allowlist, and event subscriptions (idempotent full sync).
  """
  def update_installation_config(%BotInstallation{} = inst, %{
        "granted_scopes" => granted_scopes,
        "allowed_channel_ids" => allowed_channel_ids,
        "subscribed_events" => subscribed_events,
        "status" => status
      }) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:installation, fn _ ->
      BotInstallation.changeset(inst, %{
        granted_scopes: Enum.uniq(granted_scopes),
        allowed_channel_ids: Enum.uniq(allowed_channel_ids),
        status: status
      })
    end)
    |> Ecto.Multi.run(:sync_tokens, fn repo, _ ->
      from(t in BotToken, where: t.bot_installation_id == ^inst.id and is_nil(t.revoked_at))
      |> repo.update_all(set: [scopes: Enum.uniq(granted_scopes)])

      {:ok, :synced}
    end)
    |> Ecto.Multi.run(:sync_subscriptions, fn repo, _ ->
      from(s in BotSubscription, where: s.bot_installation_id == ^inst.id)
      |> repo.delete_all()

      now = DateTime.utc_now()

      new_subs =
        subscribed_events
        |> Enum.uniq()
        |> Enum.map(fn ev ->
          %{
            id: Ecto.UUID.generate(),
            bot_installation_id: inst.id,
            event_type: ev,
            filter: %{},
            is_enabled: true,
            inserted_at: now,
            updated_at: now
          }
        end)

      if new_subs != [] do
        repo.insert_all(BotSubscription, new_subs)
      end

      {:ok, :synced}
    end)
    |> Repo.transaction()
  end

  @doc "Rotates the installation token: revokes active tokens and issues a new one."
  def rotate_installation_token(%BotInstallation{} = inst) do
    now = DateTime.utc_now()

    Repo.transaction(fn ->
      from(t in BotToken, where: t.bot_installation_id == ^inst.id and is_nil(t.revoked_at))
      |> Repo.update_all(set: [revoked_at: now])

      {:ok, token_data} = issue_installation_token(Repo, inst, inst.granted_scopes)
      token_data
    end)
  end
end
