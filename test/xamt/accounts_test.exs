defmodule Xamt.AccountsTest do
  use Xamt.DataCase

  alias Xamt.Accounts

  import Xamt.AccountsFixtures
  alias Xamt.Accounts.{Scope, User, UserToken}

  describe "get_user_by_email/1" do
    test "does not return the user if the email does not exist" do
      refute Accounts.get_user_by_email("unknown@example.com")
    end

    test "returns the user if the email exists" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Accounts.get_user_by_email(user.email)
    end
  end

  describe "get_user!/1" do
    test "raises if id is invalid" do
      assert_raise Ecto.NoResultsError, fn ->
        Accounts.get_user!("11111111-1111-1111-1111-111111111111")
      end
    end

    test "returns the user with the given id" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Accounts.get_user!(user.id)
    end
  end

  describe "sudo_mode?/2" do
    test "validates the authenticated_at time" do
      now = DateTime.utc_now()

      assert Accounts.sudo_mode?(%User{authenticated_at: DateTime.utc_now()})
      assert Accounts.sudo_mode?(%User{authenticated_at: DateTime.add(now, -19, :minute)})
      refute Accounts.sudo_mode?(%User{authenticated_at: DateTime.add(now, -21, :minute)})

      # minute override
      refute Accounts.sudo_mode?(
               %User{authenticated_at: DateTime.add(now, -11, :minute)},
               -10
             )

      # not authenticated
      refute Accounts.sudo_mode?(%User{})
    end
  end

  describe "change_user_email/3" do
    test "returns a user changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_user_email(%User{})
      assert changeset.required == [:email]
    end
  end

  describe "deliver_user_update_email_instructions/3" do
    setup do
      %{user: user_fixture()}
    end

    test "sends token through notification", %{user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_update_email_instructions(user, "current@example.com", url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert user_token = Repo.get_by(UserToken, token: :crypto.hash(:sha256, token))
      assert user_token.user_id == user.id
      assert user_token.sent_to == user.email
      assert user_token.context == "change:current@example.com"
    end
  end

  describe "update_user_email/2" do
    setup do
      user = unconfirmed_user_fixture()
      email = unique_user_email()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_update_email_instructions(%{user | email: email}, user.email, url)
        end)

      %{user: user, token: token, email: email}
    end

    test "updates the email with a valid token", %{user: user, token: token, email: email} do
      assert {:ok, %{email: ^email}} = Accounts.update_user_email(user, token)
      changed_user = Repo.get!(User, user.id)
      assert changed_user.email != user.email
      assert changed_user.email == email
      refute Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email with invalid token", %{user: user} do
      assert Accounts.update_user_email(user, "oops") ==
               {:error, :transaction_aborted}

      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email if user email changed", %{user: user, token: token} do
      assert Accounts.update_user_email(%{user | email: "current@example.com"}, token) ==
               {:error, :transaction_aborted}

      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email if token expired", %{user: user, token: token} do
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])

      assert Accounts.update_user_email(user, token) ==
               {:error, :transaction_aborted}

      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "generate_user_session_token/1" do
    setup do
      %{user: user_fixture()}
    end

    test "generates a token", %{user: user} do
      token = Accounts.generate_user_session_token(user)
      assert user_token = Repo.get_by(UserToken, token: token)
      assert user_token.context == "session"
      assert user_token.authenticated_at != nil

      # Creating the same token for another user should fail
      assert_raise Ecto.ConstraintError, fn ->
        Repo.insert!(%UserToken{
          token: user_token.token,
          user_id: user_fixture().id,
          context: "session"
        })
      end
    end

    test "duplicates the authenticated_at of given user in new token", %{user: user} do
      user = %{user | authenticated_at: DateTime.add(DateTime.utc_now(:second), -3600)}
      token = Accounts.generate_user_session_token(user)
      assert user_token = Repo.get_by(UserToken, token: token)
      assert user_token.authenticated_at == user.authenticated_at
      assert DateTime.compare(user_token.inserted_at, user.authenticated_at) == :gt
    end
  end

  describe "get_user_by_session_token/1" do
    setup do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      %{user: user, token: token}
    end

    test "returns user by token", %{user: user, token: token} do
      assert {session_user, token_inserted_at} = Accounts.get_user_by_session_token(token)
      assert session_user.id == user.id
      assert session_user.authenticated_at != nil
      assert token_inserted_at != nil
    end

    test "does not return user for invalid token" do
      refute Accounts.get_user_by_session_token("oops")
    end

    test "does not return user for expired token", %{token: token} do
      dt = ~N[2020-01-01 00:00:00]
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: dt, authenticated_at: dt])
      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "delete_user_session_token/1" do
    test "deletes the token" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      assert Accounts.delete_user_session_token(token) == :ok
      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "search_users_as_admin/2" do
    test "admins can list and filter users by username, email, or display name" do
      admin = admin_fixture()
      scope = Scope.for_user(admin)
      suffix = System.unique_integer([:positive])

      alice =
        user_fixture(%{
          username: "alice#{suffix}",
          display_name: "Alice Neighbor",
          email: "alice#{suffix}@example.com"
        })

      bob =
        user_fixture(%{
          username: "bob#{suffix}",
          display_name: "Bob Guest",
          email: "findme#{suffix}@example.com"
        })

      assert {:ok, listed} = Accounts.search_users_as_admin(scope, "")
      assert Enum.any?(listed, &(&1.id == alice.id))
      assert Enum.any?(listed, &(&1.id == bob.id))

      assert {:ok, [found]} = Accounts.search_users_as_admin(scope, "alice#{suffix}")
      assert found.id == alice.id

      assert {:ok, [found_email]} = Accounts.search_users_as_admin(scope, "findme#{suffix}")
      assert found_email.id == bob.id

      assert {:ok, [found_name]} = Accounts.search_users_as_admin(scope, "Alice Neighbor")
      assert found_name.id == alice.id

      assert {:ok, [found_mention]} = Accounts.search_users_as_admin(scope, "@bob#{suffix}")
      assert found_mention.id == bob.id

      assert {:ok, []} = Accounts.search_users_as_admin(scope, "no-such-user-#{suffix}")
    end

    test "rejects non-admins" do
      user = user_fixture()
      creator = creator_fixture()

      assert {:error, :unauthorized} = Accounts.search_users_as_admin(Scope.for_user(user), "")

      assert {:error, :unauthorized} =
               Accounts.search_users_as_admin(Scope.for_user(creator), "alice")
    end
  end

  describe "update_user_as_admin/3" do
    test "admins can update profile fields and role" do
      admin = admin_fixture()
      user = user_fixture(%{display_name: "Old Name"})
      email = unique_user_email()
      username = unique_user_username()

      assert {:ok, updated} =
               Accounts.update_user_as_admin(Scope.for_user(admin), user, %{
                 display_name: "New Neighbor",
                 username: username,
                 email: email,
                 bio: "Writes in Mongolian.",
                 global_role: "creator"
               })

      assert updated.display_name == "New Neighbor"
      assert updated.username == username
      assert updated.email == email
      assert updated.bio == "Writes in Mongolian."
      assert updated.global_role == "creator"
      assert User.can_create_server?(updated)
    end

    test "rejects non-admins" do
      actor = user_fixture()
      target = user_fixture()

      assert {:error, :unauthorized} =
               Accounts.update_user_as_admin(Scope.for_user(actor), target, %{
                 display_name: "Nope",
                 username: target.username,
                 email: target.email,
                 global_role: "admin"
               })

      assert Accounts.get_user!(target.id).global_role == "user"
    end

    test "cannot demote the last admin" do
      admin = admin_fixture()

      assert {:error, changeset} =
               Accounts.update_user_as_admin(Scope.for_user(admin), admin, %{
                 username: admin.username,
                 email: admin.email,
                 global_role: "user"
               })

      assert "cannot remove the last admin" in errors_on(changeset).global_role
      assert Accounts.get_user!(admin.id).global_role == "admin"
    end
  end

  describe "update_user_global_role/2" do
    test "promotes a user to creator or admin" do
      user = user_fixture()
      assert user.global_role == "user"
      refute User.can_create_server?(user)

      {:ok, creator} = Accounts.update_user_global_role(user, "creator")
      assert creator.global_role == "creator"
      assert User.can_create_server?(creator)

      {:ok, admin} = Accounts.update_user_global_role(creator, "admin")
      assert admin.global_role == "admin"
      assert User.can_create_server?(admin)
      assert User.admin?(admin)
      refute User.admin?(creator)
      refute User.admin?(user)
    end

    test "rejects unknown roles" do
      user = user_fixture()
      assert {:error, changeset} = Accounts.update_user_global_role(user, "superadmin")
      assert "is invalid" in errors_on(changeset).global_role
    end
  end

  describe "profile_changeset/2" do
    test "cannot change global_role" do
      user = user_fixture()
      changeset = User.profile_changeset(user, %{global_role: "admin", display_name: "Pat"})
      assert Ecto.Changeset.get_field(changeset, :global_role) == "user"
      refute Ecto.Changeset.get_change(changeset, :global_role)
    end
  end

  describe "update_user_custom_status/2" do
    test "sets emoji and text" do
      user = user_fixture()

      assert {:ok, updated} =
               Accounts.update_user_custom_status(user, %{
                 status_emoji: "🎧",
                 status_text: "Listening to an audiobook"
               })

      assert updated.status_emoji == "🎧"
      assert updated.status_text == "Listening to an audiobook"
    end

    test "clears blank values to nil" do
      user = user_fixture()

      {:ok, user} =
        Accounts.update_user_custom_status(user, %{
          status_emoji: "🚗",
          status_text: "On a road trip"
        })

      assert {:ok, cleared} =
               Accounts.update_user_custom_status(user, %{
                 status_emoji: "  ",
                 status_text: ""
               })

      assert cleared.status_emoji == nil
      assert cleared.status_text == nil
    end

    test "rejects status text longer than 50 characters" do
      user = user_fixture()
      long = String.duplicate("a", 51)

      assert {:error, changeset} =
               Accounts.update_user_custom_status(user, %{
                 status_emoji: "😀",
                 status_text: long
               })

      assert "should be at most 50 character(s)" in errors_on(changeset).status_text
    end
  end

  describe "update_user_profile/2" do
    test "ignores username, status, and unsafe avatar URLs" do
      user = user_fixture(%{display_name: "Old", username: "keepme"})
      original = user.username

      assert {:ok, updated} =
               Accounts.update_user_profile(user, %{
                 "username" => "hijacked",
                 "display_name" => "New Neighbor",
                 "bio" => "Writes in Mongolian.",
                 "status" => "dnd",
                 "avatar" => "https://evil.example/track.gif"
               })

      assert updated.username == original
      assert updated.display_name == "New Neighbor"
      assert updated.bio == "Writes in Mongolian."
      assert updated.status == user.status
      assert updated.avatar == user.avatar
    end

    test "accepts a same-origin upload avatar" do
      user = user_fixture()

      assert {:ok, updated} =
               Accounts.update_user_profile(user, %{"avatar" => "/uploads/avatar-ok.webp"})

      assert updated.avatar == "/uploads/avatar-ok.webp"
    end
  end
end
