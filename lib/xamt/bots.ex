defmodule Xamt.Bots do
  @moduledoc """
  Bot 应用创建、安装、Token 校验与频道操作授权。
  """

  import Ecto.Query
  alias Xamt.Repo
  alias Xamt.Accounts.User
  alias Xamt.Servers.ServerMember
  alias Xamt.Bots.{Bot, BotInstallation, BotToken, BotSubscription}

  @doc """
  创建一个 Bot 应用，同时在 users 表创建一个影子账号供其发言使用。
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
  将 Bot 安装到指定 Server，同时生成首次调用的明文 Token（仅在安装时返回一次）。
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
  签发 API Token：返回 `{:ok, %{raw_token: ..., record: %BotToken{}}}`，数据库只存 SHA-256 哈希。
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
  验证 Bot API 请求的 Bearer Token，返回预加载了 bot 与 installation 的上下文。
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
  双重权限校验：验证该 Token 是否有权在目标频道执行指定 scope 操作。
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
end
