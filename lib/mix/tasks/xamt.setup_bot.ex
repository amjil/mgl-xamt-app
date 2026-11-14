defmodule Mix.Tasks.Xamt.SetupBot do
  @shortdoc "Create or reuse a channel + bot install; print IDs and register command"

  @moduledoc """
  Prepares a bot installation on an Xamt server (reuse-first) and prints
  everything needed to register it with xamt-bot.

      mix xamt.setup_bot --server-slug my-server
      mix xamt.setup_bot --server-id UUID --channel-name reviews --bot-name "My Bot"
      mix xamt.setup_bot --server-name "Acme" --bot-base-url http://127.0.0.1:4003 --write tmp/bot.env

  Options:

    --server-id / --server-slug / --server-name   (one required)
    --admin-email         actor for create/install (default: server owner)
    --channel-name        find-or-create channel (default: bot-channel)
    --channel-id          use an existing channel instead of name lookup
    --bot-name            find-or-create bot on this server (default: Xamt Bot)
    --bot-base-url        webhook root, no path (default: http://127.0.0.1:4003)
    --handler             value for printed `mix xamt_bot.register --handler` (default: echo)
    --write PATH          also write a sourceable env file

  Reuse rules: same channel name (or `--channel-id`) and same bot name on the
  server are reused. Reused installs rotate the API token and refresh webhook /
  channel allowlist.
  """

  use Mix.Task

  import Ecto.Query

  alias Xamt.Accounts
  alias Xamt.Accounts.User
  alias Xamt.Bots
  alias Xamt.Bots.BotInstallation
  alias Xamt.Channels
  alias Xamt.Channels.Channel
  alias Xamt.Repo
  alias Xamt.Servers.Server

  @requirements ["app.start"]

  @default_channel_name "bot-channel"
  @default_bot_name "Xamt Bot"
  @default_bot_base_url "http://127.0.0.1:4003"
  @default_handler "echo"
  @default_scopes ["channel.messages.send"]

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [
          server_id: :string,
          server_slug: :string,
          server_name: :string,
          admin_email: :string,
          channel_name: :string,
          channel_id: :string,
          bot_name: :string,
          bot_base_url: :string,
          handler: :string,
          write: :string
        ]
      )

    case setup(opts) do
      {:ok, result} ->
        text = format_output(result)
        Mix.shell().info(text)

        if path = Keyword.get(opts, :write) do
          File.mkdir_p!(Path.dirname(path))
          File.write!(path, env_file_contents(result))
          Mix.shell().info("\nWrote #{path}")
        end

      {:error, reason} ->
        Mix.raise(format_error(reason))
    end
  end

  @doc """
  Core setup used by the Mix task and tests.

  `opts` is a keyword list (string values) matching CLI flags.
  """
  def setup(opts) when is_list(opts) do
    with {:ok, server} <- resolve_server(opts),
         {:ok, admin} <- resolve_admin(server, opts),
         {:ok, channel, channel_action} <- resolve_channel(server, opts),
         {:ok, bot_result} <- resolve_bot(server, admin, channel, opts) do
      bot_base_url =
        opts
        |> Keyword.get(:bot_base_url, @default_bot_base_url)
        |> String.trim_trailing("/")

      handler = Keyword.get(opts, :handler, @default_handler)
      bot_name = Keyword.get(opts, :bot_name, @default_bot_name)

      {:ok,
       %{
         server: server,
         channel: channel,
         channel_action: channel_action,
         bot: bot_result.bot,
         installation: bot_result.installation,
         bot_action: bot_result.action,
         api_token: bot_result.api_token,
         signing_secret: bot_result.bot.signing_secret,
         bot_base_url: bot_base_url,
         webhook_url: bot_result.bot.webhook_url,
         handler: handler,
         bot_name: bot_name
       }}
    end
  end

  defp resolve_server(opts) do
    cond do
      id = present(opts[:server_id]) ->
        case Repo.get(Server, id) do
          %Server{} = server -> {:ok, server}
          nil -> {:error, {:server_not_found, id}}
        end

      slug = present(opts[:server_slug]) ->
        case Repo.get_by(Server, slug: slug) do
          %Server{} = server -> {:ok, server}
          nil -> {:error, {:server_not_found_slug, slug}}
        end

      name = present(opts[:server_name]) ->
        case Repo.all(from(s in Server, where: s.name == ^name, order_by: [asc: s.inserted_at])) do
          [%Server{} = server] ->
            {:ok, server}

          [] ->
            {:error, {:server_not_found_name, name}}

          many ->
            {:error, {:server_ambiguous, name, Enum.map(many, &{&1.id, &1.slug, &1.name})}}
        end

      true ->
        servers =
          Repo.all(
            from(s in Server, order_by: [asc: s.name], limit: 20, select: {s.id, s.slug, s.name})
          )

        {:error, {:server_required, servers}}
    end
  end

  defp resolve_admin(server, opts) do
    case present(opts[:admin_email]) do
      nil ->
        case Accounts.get_user!(server.owner_id) do
          %User{} = user -> {:ok, user}
        end

      email ->
        case Accounts.get_user_by_email(email) do
          %User{} = user -> {:ok, user}
          nil -> {:error, {:admin_not_found, email}}
        end
    end
  end

  defp resolve_channel(server, opts) do
    cond do
      id = present(opts[:channel_id]) ->
        case Channels.get_channel(id) do
          %Channel{server_id: sid} = channel when sid == server.id ->
            {:ok, channel, :reused}

          %Channel{} ->
            {:error, {:channel_wrong_server, id}}

          nil ->
            {:error, {:channel_not_found, id}}
        end

      true ->
        name = Keyword.get(opts, :channel_name, @default_channel_name)

        case find_channel_by_name(server.id, name) do
          %Channel{} = channel ->
            {:ok, channel, :reused}

          nil ->
            case Channels.create_channel(server, %{"name" => name}) do
              {:ok, channel} -> {:ok, channel, :created}
              {:error, changeset} -> {:error, {:channel_create_failed, changeset}}
            end
        end
    end
  end

  defp find_channel_by_name(server_id, name) do
    from(c in Channel,
      where: c.server_id == ^server_id and c.name == ^name,
      order_by: [asc: c.inserted_at],
      limit: 1
    )
    |> Repo.one()
  end

  defp resolve_bot(server, admin, channel, opts) do
    bot_name = Keyword.get(opts, :bot_name, @default_bot_name)

    bot_base_url =
      opts
      |> Keyword.get(:bot_base_url, @default_bot_base_url)
      |> String.trim_trailing("/")

    case find_installation(server.id, bot_name) do
      %BotInstallation{} = inst ->
        reuse_bot(inst, admin, channel, bot_base_url)

      nil ->
        create_bot(server, admin, channel, bot_name, bot_base_url)
    end
  end

  defp find_installation(server_id, bot_name) do
    from(i in BotInstallation,
      join: b in assoc(i, :bot),
      where: i.server_id == ^server_id and b.name == ^bot_name and i.status != "uninstalled",
      order_by: [desc: i.inserted_at],
      limit: 1,
      preload: [:bot]
    )
    |> Repo.one()
  end

  defp create_bot(server, admin, channel, bot_name, bot_base_url) do
    placeholder = "#{bot_base_url}/webhooks/xamt/pending"

    install_opts = [
      granted_scopes: @default_scopes,
      subscribed_events: [],
      allowed_channel_ids: [channel.id]
    ]

    case Bots.create_and_install_bot(
           admin,
           server.id,
           %{
             "name" => bot_name,
             "description" => "Created by mix xamt.setup_bot",
             "webhook_url" => placeholder
           },
           install_opts
         ) do
      {:ok, %{bot: bot, installation: inst, token: %{raw_token: raw_token}}} ->
        url = webhook_url(bot_base_url, bot.id)

        case Bots.update_bot(bot, %{"webhook_url" => url}, admin) do
          {:ok, %{bot: bot}} ->
            {:ok, %{bot: bot, installation: inst, api_token: raw_token, action: :created}}

          {:error, reason} ->
            {:error, {:bot_create_failed, reason}}

          {:error, _step, reason, _changes} ->
            {:error, {:bot_create_failed, reason}}
        end

      {:error, reason} ->
        {:error, {:bot_create_failed, reason}}

      {:error, _step, reason, _changes} ->
        {:error, {:bot_create_failed, reason}}
    end
  end

  defp reuse_bot(%BotInstallation{} = inst, admin, channel, bot_base_url) do
    bot = inst.bot
    url = webhook_url(bot_base_url, bot.id)

    with {:ok, %{bot: bot}} <- Bots.update_bot(bot, %{"webhook_url" => url}, admin),
         {:ok, %{installation: inst}} <-
           Bots.update_installation_config(inst, %{
             "granted_scopes" => @default_scopes,
             "allowed_channel_ids" => [channel.id],
             "subscribed_events" => [],
             "status" => "enabled"
           }),
         {:ok, %{raw_token: raw_token}} <- Bots.rotate_installation_token(inst, admin) do
      {:ok, %{bot: bot, installation: inst, api_token: raw_token, action: :reused}}
    else
      {:error, reason} -> {:error, {:bot_reuse_failed, reason}}
      {:error, _step, reason, _changes} -> {:error, {:bot_reuse_failed, reason}}
    end
  end

  defp webhook_url(bot_base_url, bot_id), do: "#{bot_base_url}/webhooks/xamt/#{bot_id}"

  defp present(nil), do: nil
  defp present(""), do: nil
  defp present(value) when is_binary(value), do: value

  def format_output(result) do
    """
    Xamt bot setup (#{result.bot_action} bot, #{result.channel_action} channel)

      server_id=#{result.server.id}
      server_slug=#{result.server.slug}
      channel_id=#{result.channel.id}
      channel_name=#{result.channel.name}
      bot_id=#{result.bot.id}
      bot_name=#{result.bot.name}
      webhook_url=#{result.webhook_url}
      signing_secret=#{result.signing_secret}
      api_token=#{result.api_token}

    # Env (optional)
    export XAMT_SERVER_ID=#{result.server.id}
    export XAMT_CHANNEL_ID=#{result.channel.id}
    export XAMT_BOT_UUID=#{result.bot.id}
    export XAMT_BOT_SIGNING_SECRET=#{result.signing_secret}
    export XAMT_BOT_API_TOKEN=#{result.api_token}
    export XAMT_BOT_BASE_URL=#{result.bot_base_url}

    # Register on xamt-bot (run from that repo):
    mix xamt_bot.register \\
      --external-bot-id #{result.bot.id} \\
      --name "#{escape_dq(result.bot_name)}" \\
      --handler #{result.handler} \\
      --channel-id #{result.channel.id} \\
      --signing-secret #{result.signing_secret} \\
      --api-token #{result.api_token}
    """
    |> String.trim_trailing()
  end

  def env_file_contents(result) do
    """
    # Generated by mix xamt.setup_bot — contains secrets; do not commit.
    export XAMT_SERVER_ID=#{result.server.id}
    export XAMT_CHANNEL_ID=#{result.channel.id}
    export XAMT_BOT_UUID=#{result.bot.id}
    export XAMT_BOT_SIGNING_SECRET=#{result.signing_secret}
    export XAMT_BOT_API_TOKEN=#{result.api_token}
    export XAMT_BOT_BASE_URL=#{result.bot_base_url}
    export XAMT_BOT_WEBHOOK_URL=#{result.webhook_url}
    export XAMT_BOT_NAME=#{shell_single_quote(result.bot_name)}
    export XAMT_BOT_HANDLER=#{result.handler}
    """
  end

  defp escape_dq(value), do: String.replace(value, "\"", "\\\"")

  defp shell_single_quote(value) do
    "'" <> String.replace(value, "'", "'\\''") <> "'"
  end

  defp format_error({:server_required, servers}) do
    listed =
      case servers do
        [] -> "  (no servers in database)"
        rows -> Enum.map_join(rows, "\n", fn {id, slug, name} -> "  #{id}\t#{slug}\t#{name}" end)
      end

    """
    Provide --server-id, --server-slug, or --server-name.

    Existing servers:
    #{listed}
    """
  end

  defp format_error({:server_ambiguous, name, many}) do
    listed = Enum.map_join(many, "\n", fn {id, slug, n} -> "  #{id}\t#{slug}\t#{n}" end)

    """
    Multiple servers named #{inspect(name)}. Pass --server-id or --server-slug:

    #{listed}
    """
  end

  defp format_error({:server_not_found, id}), do: "Server not found: #{id}"
  defp format_error({:server_not_found_slug, slug}), do: "Server slug not found: #{slug}"
  defp format_error({:server_not_found_name, name}), do: "Server name not found: #{name}"
  defp format_error({:admin_not_found, email}), do: "Admin user not found: #{email}"
  defp format_error({:channel_not_found, id}), do: "Channel not found: #{id}"
  defp format_error({:channel_wrong_server, id}), do: "Channel #{id} is not on that server"

  defp format_error({:channel_create_failed, cs}),
    do: "Channel create failed: #{inspect(cs.errors)}"

  defp format_error({:bot_create_failed, reason}), do: "Bot create failed: #{inspect(reason)}"
  defp format_error({:bot_reuse_failed, reason}), do: "Bot reuse failed: #{inspect(reason)}"
end
