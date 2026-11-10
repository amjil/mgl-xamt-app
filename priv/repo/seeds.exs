alias Xamt.Accounts
alias Xamt.Accounts.{Scope, User}
alias Xamt.Repo
alias Xamt.Servers
alias Xamt.Servers.Server

demo_password = "hello world1!"
demo_email = "demo@xamt.local"
server_slug = "mongol-bichig"

user =
  case Accounts.get_user_by_email(demo_email) do
    %User{} = existing ->
      existing

    nil ->
      {:ok, registered} =
        Accounts.register_user(%{
          "email" => demo_email,
          "username" => "demo",
          "display_name" => "Demo",
          "password" => demo_password,
          "password_confirmation" => demo_password
        })

      registered
      |> User.confirm_changeset()
      |> Repo.update!()
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

IO.puts(
  "Seeded demo user #{demo_email} (username: demo, role: creator) and server #{server_slug}"
)
