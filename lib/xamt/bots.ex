defmodule Xamt.Bots do
  @moduledoc """
  Bot app creation, installation, token verification, and channel action authorization.
  """

  import Ecto.Query
  alias Xamt.Repo
  alias Xamt.Accounts.User
  alias Xamt.Channels
  alias Xamt.Servers.ServerMember

  alias Xamt.Bots.{
    Bot,
    BotAuditLog,
    BotEvent,
    BotIdempotencyKey,
    BotInstallation,
    BotInteraction,
    BotSubscription,
    BotToken
  }

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
    |> Ecto.Multi.run(:audit, fn repo, %{bot: bot} ->
      insert_audit(repo, %{
        bot_id: bot.id,
        actor_user_id: creator_user.id,
        action: "bot.created",
        resource_type: "bot",
        resource_id: bot.id,
        metadata: %{"name" => bot.name}
      })
    end)
    |> Repo.transaction()
  end

  def update_bot(%Bot{} = bot, attrs, actor_user \\ nil) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:bot, Bot.changeset(bot, stringify_keys(attrs)))
    |> Ecto.Multi.run(:audit, fn repo, %{bot: updated} ->
      insert_audit(repo, %{
        bot_id: updated.id,
        actor_user_id: actor_user && actor_user.id,
        action: if(updated.status == "suspended", do: "bot.suspended", else: "bot.updated"),
        resource_type: "bot",
        resource_id: updated.id,
        metadata: %{"status" => updated.status, "name" => updated.name}
      })
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
    |> Ecto.Multi.run(:audit, fn repo, %{installation: inst} ->
      insert_audit(repo, %{
        bot_id: bot_id,
        bot_installation_id: inst.id,
        actor_user_id: installed_by_user.id,
        server_id: server_id,
        action: "installation.created",
        resource_type: "installation",
        resource_id: inst.id
      })
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
      {:ok, record} ->
        _ =
          insert_audit(repo, %{
            bot_id: inst.bot_id,
            bot_installation_id: inst.id,
            server_id: inst.server_id,
            action: "token.issued",
            resource_type: "token",
            resource_id: record.id,
            metadata: %{"token_prefix" => prefix}
          })

        {:ok, %{raw_token: raw_token, record: record}}

      error ->
        error
    end
  end

  @doc """
  Validates a Bearer token for bot API requests; returns preloaded bot and installation context.
  """
  def authenticate_token(raw_token) when is_binary(raw_token) do
    if bot_api_enabled?() do
      hash = :crypto.hash(:sha256, raw_token)
      now = DateTime.utc_now()

      query =
        from t in BotToken,
          join: i in assoc(t, :bot_installation),
          join: b in assoc(t, :bot),
          join: u in assoc(b, :bot_user),
          where: t.token_hash == ^hash and is_nil(t.revoked_at),
          where: is_nil(t.expires_at) or t.expires_at > ^now,
          where: i.status == "enabled" and is_nil(i.uninstalled_at) and b.status == "active",
          preload: [bot_installation: i, bot: {b, bot_user: u}]

      case Repo.one(query) do
        nil ->
          {:error, :invalid_token}

        token ->
          touch_token_last_used(token.id)
          {:ok, token}
      end
    else
      {:error, :bot_api_disabled}
    end
  end

  def authenticate_token(_), do: {:error, :invalid_token}

  defp touch_token_last_used(token_id) do
    now = DateTime.utc_now()

    from(t in BotToken, where: t.id == ^token_id)
    |> Repo.update_all(set: [last_used_at: now])
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

  def list_authorized_channels(%BotToken{} = token) do
    inst = token.bot_installation
    channels = Channels.list_channels(inst.server_id)

    Enum.filter(channels, fn ch -> channel_allowed?(inst, ch.id) end)
  end

  def get_authorized_channel(%BotToken{} = token, channel_id) do
    case Channels.get_channel(channel_id) do
      nil ->
        {:error, :not_found}

      channel ->
        case authorize_channel_action(token, channel, "channel.messages.read") do
          :ok ->
            {:ok, channel}

          {:error, :insufficient_scope} ->
            # Allow read of channel metadata if send scope alone is granted for Echo setups
            case authorize_channel_action(token, channel, "channel.messages.send") do
              :ok -> {:ok, channel}
              error -> error
            end

          error ->
            error
        end
    end
  end

  @doc "Lists bot installations on a server (preloads bot, subscriptions, active token prefixes)."
  def list_server_installations(server_id) do
    from(i in BotInstallation,
      where: i.server_id == ^server_id and i.status != "uninstalled",
      order_by: [asc: i.inserted_at],
      preload: [
        :bot,
        :subscriptions,
        tokens: ^from(t in BotToken, where: is_nil(t.revoked_at), order_by: [desc: t.inserted_at])
      ]
    )
    |> Repo.all()
  end

  def get_installation(id) do
    from(i in BotInstallation,
      where: i.id == ^id,
      preload: [:bot, :subscriptions]
    )
    |> Repo.one()
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
    |> Ecto.Multi.run(:audit, fn repo, %{installation: updated} ->
      insert_audit(repo, %{
        bot_id: updated.bot_id,
        bot_installation_id: updated.id,
        actor_user_id: nil,
        server_id: updated.server_id,
        action: "installation.updated",
        resource_type: "installation",
        resource_id: updated.id,
        metadata: %{
          "status" => updated.status,
          "granted_scopes" => updated.granted_scopes,
          "subscribed_events" => subscribed_events
        }
      })
    end)
    |> Repo.transaction()
  end

  @doc "Rotates the installation token: revokes active tokens and issues a new one."
  def rotate_installation_token(%BotInstallation{} = inst, actor_user \\ nil) do
    now = DateTime.utc_now()

    Repo.transaction(fn ->
      from(t in BotToken, where: t.bot_installation_id == ^inst.id and is_nil(t.revoked_at))
      |> Repo.update_all(set: [revoked_at: now])

      {:ok, token_data} = issue_installation_token(Repo, inst, inst.granted_scopes)

      _ =
        insert_audit(Repo, %{
          bot_id: inst.bot_id,
          bot_installation_id: inst.id,
          actor_user_id: actor_user && actor_user.id,
          server_id: inst.server_id,
          action: "token.rotated",
          resource_type: "token",
          resource_id: token_data.record.id,
          metadata: %{"token_prefix" => token_data.record.token_prefix}
        })

      token_data
    end)
  end

  def revoke_installation_tokens(%BotInstallation{} = inst, actor_user \\ nil) do
    now = DateTime.utc_now()

    {count, _} =
      from(t in BotToken, where: t.bot_installation_id == ^inst.id and is_nil(t.revoked_at))
      |> Repo.update_all(set: [revoked_at: now])

    _ =
      insert_audit(Repo, %{
        bot_id: inst.bot_id,
        bot_installation_id: inst.id,
        actor_user_id: actor_user && actor_user.id,
        server_id: inst.server_id,
        action: "token.revoked",
        resource_type: "installation",
        resource_id: inst.id,
        metadata: %{"revoked_count" => count}
      })

    {:ok, count}
  end

  def uninstall_bot(%BotInstallation{} = inst, actor_user) do
    now = DateTime.utc_now()

    Ecto.Multi.new()
    |> Ecto.Multi.update(
      :installation,
      BotInstallation.changeset(inst, %{status: "uninstalled", uninstalled_at: now})
    )
    |> Ecto.Multi.run(:revoke_tokens, fn repo, _ ->
      from(t in BotToken, where: t.bot_installation_id == ^inst.id and is_nil(t.revoked_at))
      |> repo.update_all(set: [revoked_at: now])

      {:ok, :revoked}
    end)
    |> Ecto.Multi.run(:disable_subs, fn repo, _ ->
      from(s in BotSubscription, where: s.bot_installation_id == ^inst.id)
      |> repo.update_all(set: [is_enabled: false, updated_at: now])

      {:ok, :disabled}
    end)
    |> Ecto.Multi.run(:audit, fn repo, %{installation: updated} ->
      insert_audit(repo, %{
        bot_id: updated.bot_id,
        bot_installation_id: updated.id,
        actor_user_id: actor_user.id,
        server_id: updated.server_id,
        action: "installation.uninstalled",
        resource_type: "installation",
        resource_id: updated.id
      })
    end)
    |> Repo.transaction()
  end

  def list_installation_events(installation_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    from(e in BotEvent,
      where: e.bot_installation_id == ^installation_id,
      order_by: [desc: e.inserted_at],
      limit: ^limit,
      preload: [:bot]
    )
    |> Repo.all()
  end

  def retry_event_delivery(event_id, actor_user \\ nil) do
    case Repo.get(BotEvent, event_id) do
      nil ->
        {:error, :not_found}

      %BotEvent{status: status} = event when status in ["failed", "dead"] ->
        now = DateTime.utc_now()

        {1, _} =
          from(e in BotEvent, where: e.id == ^event.id)
          |> Repo.update_all(
            set: [
              status: "pending",
              next_attempt_at: now,
              updated_at: now
            ]
          )

        _ =
          insert_audit(Repo, %{
            bot_id: event.bot_id,
            bot_installation_id: event.bot_installation_id,
            actor_user_id: actor_user && actor_user.id,
            server_id: event.server_id,
            channel_id: event.channel_id,
            action: "delivery.retried",
            resource_type: "event",
            resource_id: event.id
          })

        _ = Xamt.Bots.DeliveryWorker.enqueue(event.id, max_attempts: event.max_retries)
        {:ok, Repo.get!(BotEvent, event.id)}

      _ ->
        {:error, :not_retryable}
    end
  end

  def disable_subscription(subscription_id, actor_user \\ nil) do
    case Repo.get(BotSubscription, subscription_id) do
      nil ->
        {:error, :not_found}

      sub ->
        {:ok, updated} =
          sub
          |> BotSubscription.changeset(%{is_enabled: false})
          |> Repo.update()

        inst = Repo.get!(BotInstallation, sub.bot_installation_id)

        _ =
          insert_audit(Repo, %{
            bot_id: inst.bot_id,
            bot_installation_id: inst.id,
            actor_user_id: actor_user && actor_user.id,
            server_id: inst.server_id,
            action: "subscription.disabled",
            resource_type: "subscription",
            resource_id: sub.id,
            metadata: %{"event_type" => sub.event_type}
          })

        {:ok, updated}
    end
  end

  def list_event_subscriptions(%BotToken{} = token) do
    from(s in BotSubscription,
      where: s.bot_installation_id == ^token.bot_installation_id,
      order_by: [asc: s.event_type]
    )
    |> Repo.all()
  end

  def find_message_by_nonce(installation_id, nonce) when is_binary(nonce) and nonce != "" do
    from(k in BotIdempotencyKey,
      where: k.bot_installation_id == ^installation_id and k.nonce == ^nonce,
      preload: [message: [:user]]
    )
    |> Repo.one()
  end

  def find_message_by_nonce(_, _), do: nil

  def remember_nonce(repo \\ Repo, installation_id, nonce, message_id)

  def remember_nonce(repo, installation_id, nonce, message_id)
      when is_binary(nonce) and nonce != "" do
    %BotIdempotencyKey{}
    |> BotIdempotencyKey.changeset(%{
      bot_installation_id: installation_id,
      nonce: nonce,
      message_id: message_id
    })
    |> repo.insert()
  end

  def remember_nonce(_repo, _installation_id, _nonce, _message_id), do: {:ok, nil}

  def create_interaction(%BotToken{} = token, attrs) do
    inst = token.bot_installation
    channel_id = Map.get(attrs, "channel_id") || Map.get(attrs, :channel_id)
    action_key = Map.get(attrs, "action_key") || Map.get(attrs, :action_key)

    expires_in =
      Map.get(attrs, "expires_in_seconds") || Map.get(attrs, :expires_in_seconds) || 3600

    with channel when not is_nil(channel) <- Channels.get_channel(channel_id),
         :ok <- authorize_channel_action(token, channel, "channel.messages.send") do
      expires_at = DateTime.add(DateTime.utc_now(), expires_in, :second)

      %BotInteraction{}
      |> BotInteraction.changeset(%{
        bot_id: token.bot_id,
        bot_installation_id: inst.id,
        server_id: inst.server_id,
        channel_id: channel.id,
        message_id: Map.get(attrs, "message_id") || Map.get(attrs, :message_id),
        action_key: action_key,
        label: Map.get(attrs, "label") || Map.get(attrs, :label),
        payload: Map.get(attrs, "payload") || Map.get(attrs, :payload) || %{},
        expires_at: expires_at,
        status: "pending"
      })
      |> Repo.insert()
      |> case do
        {:ok, interaction} ->
          _ =
            insert_audit(Repo, %{
              bot_id: token.bot_id,
              bot_installation_id: inst.id,
              server_id: inst.server_id,
              channel_id: channel.id,
              action: "interaction.created",
              resource_type: "interaction",
              resource_id: interaction.id
            })

          {:ok, interaction}

        error ->
          error
      end
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  def respond_to_interaction(interaction_id, %BotToken{} = token, response_payload)
      when is_map(response_payload) do
    now = DateTime.utc_now()

    case Repo.get(BotInteraction, interaction_id) do
      nil ->
        {:error, :not_found}

      %BotInteraction{bot_installation_id: inst_id}
      when inst_id != token.bot_installation_id ->
        {:error, :forbidden}

      %BotInteraction{status: "responded"} ->
        {:error, :already_responded}

      %BotInteraction{status: "pending", expires_at: expires_at} = interaction ->
        if DateTime.compare(expires_at, now) != :gt do
          from(i in BotInteraction, where: i.id == ^interaction_id)
          |> Repo.update_all(set: [status: "expired", updated_at: now])

          {:error, :expired}
        else
          interaction
          |> BotInteraction.changeset(%{
            status: "responded",
            responded_at: now,
            response_payload: response_payload
          })
          |> Repo.update()
          |> case do
            {:ok, updated} ->
              _ =
                insert_audit(Repo, %{
                  bot_id: token.bot_id,
                  bot_installation_id: token.bot_installation_id,
                  server_id: interaction.server_id,
                  channel_id: interaction.channel_id,
                  action: "interaction.responded",
                  resource_type: "interaction",
                  resource_id: updated.id
                })

              {:ok, updated}

            error ->
              error
          end
        end

      _ ->
        {:error, :invalid_status}
    end
  end

  def me_payload(%BotToken{} = token) do
    bot = token.bot
    inst = token.bot_installation

    %{
      bot: %{
        id: bot.id,
        name: bot.name,
        description: bot.description,
        avatar_url: bot.avatar_url,
        status: bot.status
      },
      installation: %{
        id: inst.id,
        server_id: inst.server_id,
        status: inst.status,
        granted_scopes: inst.granted_scopes,
        allowed_channel_ids: inst.allowed_channel_ids
      },
      token: %{
        id: token.id,
        scopes: token.scopes,
        prefix: token.token_prefix,
        last_used_at: token.last_used_at
      }
    }
  end

  def log_message_action(token, action, message, extra \\ %{}) do
    insert_audit(Repo, %{
      bot_id: token.bot_id,
      bot_installation_id: token.bot_installation_id,
      server_id: token.bot_installation.server_id,
      channel_id: message.channel_id,
      action: action,
      resource_type: "message",
      resource_id: message.id,
      metadata: extra
    })
  end

  defp insert_audit(repo, attrs) do
    %BotAuditLog{}
    |> BotAuditLog.changeset(attrs)
    |> repo.insert()
  end

  defp stringify_keys(attrs) do
    Map.new(attrs, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end

  defp bot_api_enabled? do
    Application.get_env(:xamt, :bot_api_enabled, true)
  end
end
