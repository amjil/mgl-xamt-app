defmodule XamtWeb.UploadControllerTest do
  use XamtWeb.ConnCase, async: false

  import Xamt.AccountsFixtures

  alias Xamt.Accounts
  alias Xamt.Accounts.Scope
  alias Xamt.{Channels, Messages, Servers}

  @fixture Path.expand("../../support/fixtures/gallery_sample.png", __DIR__)

  setup do
    owner = creator_fixture()
    outsider = user_fixture()
    scope = Scope.for_user(owner)
    {:ok, server} = Servers.create_server(scope, %{"name" => "Private Media"})
    channel = hd(Channels.list_channels(server.id))

    filename = "media-#{System.unique_integer([:positive])}.png"
    dest = Path.join([:code.priv_dir(:xamt), "static", "uploads", filename])
    File.mkdir_p!(Path.dirname(dest))
    File.cp!(@fixture, dest)

    url = "/uploads/#{filename}"

    {:ok, _message} =
      Messages.create_message(scope, channel.id, %{
        "content_html" => "",
        "content" => %{"type" => "gallery", "images" => [%{"thumb" => url, "original" => url}]}
      })

    on_exit(fn -> File.rm(dest) end)

    %{
      owner: owner,
      outsider: outsider,
      filename: filename,
      dest: dest,
      url: url,
      server: server
    }
  end

  test "members can fetch message media", %{conn: conn, owner: owner, filename: filename} do
    conn = conn |> log_in_user(owner) |> get(~p"/uploads/#{filename}")
    assert conn.status == 200
    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
    assert get_resp_header(conn, "content-type") == ["image/png"]
  end

  test "anonymous users cannot fetch private media", %{conn: conn, filename: filename} do
    conn = get(conn, ~p"/uploads/#{filename}")
    assert conn.status == 404
  end

  test "non-members cannot fetch private media", %{
    conn: conn,
    outsider: outsider,
    filename: filename
  } do
    conn = conn |> log_in_user(outsider) |> get(~p"/uploads/#{filename}")
    assert conn.status == 404
  end

  test "avatars are public", %{conn: conn, owner: owner} do
    filename = "avatar-#{System.unique_integer([:positive])}.png"
    dest = Path.join([:code.priv_dir(:xamt), "static", "uploads", filename])
    File.cp!(@fixture, dest)
    on_exit(fn -> File.rm(dest) end)

    {:ok, _} = Accounts.update_user_profile(owner, %{"avatar" => "/uploads/#{filename}"})

    conn = get(conn, ~p"/uploads/#{filename}")
    assert conn.status == 200
  end

  test "rejects path-like filenames", %{conn: conn, owner: owner} do
    conn = conn |> log_in_user(owner) |> get("/uploads/../mix.exs")
    assert conn.status == 404
  end
end
