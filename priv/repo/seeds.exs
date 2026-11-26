alias Xamt.Accounts
alias Xamt.Accounts.{Scope, User}
alias Xamt.Repo
alias Xamt.Servers
alias Xamt.Servers.Server

demo_username = "demo"
server_slug = "mongol-bichig"

user =
  case Accounts.get_user_by_username(demo_username) do
    %User{} = existing ->
      existing

    nil ->
      # Seeds bypass public sign-up (removed); the admin changeset creates a
      # confirmed account directly. Sign-in for the demo user is via Mgl ID.
      %User{}
      |> User.admin_registration_changeset(%{
        "username" => demo_username,
        "display_name" => "Demo",
        "global_role" => "creator"
      })
      |> Repo.insert!()
  end

user =
  if user.global_role == "creator" do
    user
  else
    {:ok, updated} = Accounts.update_user_global_role(user, "creator")
    updated
  end

scope = Scope.for_user(user)

case Repo.get_by(Server, slug: server_slug) do
  %Server{} ->
    :ok

  nil ->
    {:ok, _server} =
      Servers.create_server(scope, %{
        "name" => "Mongol Bichig",
        "slug" => server_slug
      })
end

IO.puts("Seeded demo user #{demo_username} (role: creator) and server #{server_slug}")
