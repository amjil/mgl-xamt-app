defmodule Mix.Tasks.Xamt.MigrateUploads do
  @moduledoc """
  Copies files from the local uploads directory into the configured S3 bucket.

      mix xamt.migrate_uploads
      mix xamt.migrate_uploads --source priv/uploads --delete

  Requires S3 env vars (see `config/runtime.exs`):

      XAMT_S3_ENDPOINT   e.g. http://127.0.0.1:8333
      XAMT_S3_BUCKET     e.g. xamt
      XAMT_S3_ACCESS_KEY
      XAMT_S3_SECRET_KEY
      XAMT_S3_REGION     optional, default us-east-1

  By default local files are kept after a successful upload. Pass `--delete`
  to remove each local file only after S3 confirms the put.
  """
  use Mix.Task

  @shortdoc "Migrate priv/uploads to configured S3 storage"

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [source: :string, delete: :boolean],
        aliases: [s: :source]
      )

    Mix.Task.run("app.start")
    {:ok, _} = Application.ensure_all_started(:req)

    cfg = Application.get_env(:xamt, Xamt.Storage, [])

    unless Keyword.get(cfg, :adapter) == Xamt.Storage.S3 do
      Mix.raise("""
      S3 adapter is not configured. Set XAMT_S3_ENDPOINT / XAMT_S3_BUCKET /
      XAMT_S3_ACCESS_KEY / XAMT_S3_SECRET_KEY, then retry.
      """)
    end

    source =
      opts
      |> Keyword.get(:source)
      |> case do
        nil -> Path.expand("priv/uploads")
        path -> Path.expand(path)
      end

    delete? = Keyword.get(opts, :delete, false)

    unless File.dir?(source) do
      Mix.raise("Source directory missing: #{source}")
    end

    files =
      source
      |> File.ls!()
      |> Enum.filter(fn name ->
        name != ".gitkeep" and Xamt.Uploads.safe_filename?(name) and
          File.regular?(Path.join(source, name))
      end)
      |> Enum.sort()

    Mix.shell().info("Migrating #{length(files)} file(s) from #{source} → S3")

    {ok, fail} =
      Enum.reduce(files, {0, 0}, fn name, {ok, fail} ->
        path = Path.join(source, name)

        case Xamt.Storage.put(name, path) do
          :ok ->
            if delete?, do: File.rm(path)
            Mix.shell().info("  ok  #{name}")
            {ok + 1, fail}

          {:error, reason} ->
            Mix.shell().error("  FAIL #{name}: #{inspect(reason)}")
            {ok, fail + 1}
        end
      end)

    Mix.shell().info("Done: #{ok} uploaded, #{fail} failed")

    if fail > 0, do: Mix.raise("Migration finished with errors")
  end
end
