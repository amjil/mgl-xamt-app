defmodule Xamt.MglId.AuthAccountLinkTest do
  use Xamt.DataCase, async: false
  import Xamt.AccountsFixtures

  alias Xamt.Accounts
  alias Xamt.MglId
  alias Xamt.MglId.Auth

  setup do
    {:ok, user: user_fixture()}
  end

  test "complete_account_link confirms and stores identity", %{user: user} do
    amjil_user_id = Ecto.UUID.generate()
    stub_confirm(amjil_user_id, "readable_name")

    assert {:ok, ^user} = Auth.complete_account_link(user, "init-token", "xamt")

    identity = Accounts.get_mgl_identity(user)
    assert identity.subject == amjil_user_id
    assert identity.provider_username == "readable_name"
    assert identity.issuer == String.trim_trailing(MglId.issuer(), "/")
  end

  test "complete_account_link rejects non-xamt provider", %{user: user} do
    assert {:error, :invalid_provider} =
             Auth.complete_account_link(user, "init-token", "nomio")
  end

  test "complete_account_link rejects when already linked", %{user: user} do
    assert {:ok, _} =
             Accounts.link_mgl_identity(user, %{
               "sub" => Ecto.UUID.generate(),
               "iss" => MglId.issuer()
             })

    assert {:error, :user_already_linked} =
             Auth.complete_account_link(user, "init-token", "xamt")
  end

  test "complete_account_link surfaces confirm failures", %{user: user} do
    Req.Test.stub(Xamt.MglId, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(410, Jason.encode!(%{error: %{code: "ACCOUNT_LINK_EXPIRED"}}))
    end)

    assert {:error, {:account_link_confirm, 410, _}} =
             Auth.complete_account_link(user, "expired", "xamt")
  end

  defp stub_confirm(amjil_user_id, preferred_username) do
    Req.Test.stub(Xamt.MglId, fn conn ->
      Req.Test.json(conn, %{
        "data" => %{
          "user_id" => amjil_user_id,
          "amjil_user_id" => amjil_user_id,
          "preferred_username" => preferred_username,
          "link" => %{"provider" => "xamt"}
        },
        "meta" => %{}
      })
    end)
  end
end
