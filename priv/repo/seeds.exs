alias Xamt.Accounts
alias Xamt.Accounts.{Scope, User}
alias Xamt.Repo
alias Xamt.Servers

demo_password = "hello world!!"

{:ok, user} =
  Accounts.register_user(%{
    "email" => "demo@xamt.local",
    "username" => "demo",
    "display_name" => "Demo",
    "password" => demo_password,
    "password_confirmation" => demo_password
  })

user =
  user
  |> User.confirm_changeset()
  |> Repo.update!()

scope = Scope.for_user(user)

{:ok, _server} =
  Servers.create_server(scope, %{
    "name" => "Mongol Bichig",
    "slug" => "mongol-bichig"
  })

IO.puts("Seeded demo user demo@xamt.local (username: demo) and server mongol-bichig")
