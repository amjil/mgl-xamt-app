defmodule Xamt.NotificationsTest do
  use Xamt.DataCase, async: true

  alias Xamt.Notifications
  alias Xamt.Notifications.PushSubscription

  setup do
    user = Xamt.AccountsFixtures.user_fixture()
    %{user: user}
  end

  test "saves a subscription for a user", %{user: user} do
    attrs = subscription_attrs()

    assert {:ok, %PushSubscription{} = sub} = Notifications.save_subscription(user.id, attrs)
    assert sub.user_id == user.id
    assert sub.endpoint == attrs["endpoint"]
    assert sub.p256dh == attrs["p256dh"]
    assert sub.auth == attrs["auth"]

    assert Notifications.list_user_subscriptions(user.id) == [sub]
  end

  test "updates owner and keys when the same endpoint is saved again", %{user: user} do
    attrs = subscription_attrs()
    {:ok, original} = Notifications.save_subscription(user.id, attrs)

    other = Xamt.AccountsFixtures.user_fixture()

    assert {:ok, updated} =
             Notifications.save_subscription(other.id, %{
               attrs
               | "p256dh" => "new-p256dh-key",
                 "auth" => "new-auth-key"
             })

    assert updated.id == original.id
    assert updated.user_id == other.id
    assert updated.p256dh == "new-p256dh-key"
    assert updated.auth == "new-auth-key"
    assert Notifications.list_user_subscriptions(user.id) == []
    assert [%{id: id}] = Notifications.list_user_subscriptions(other.id)
    assert id == original.id
  end

  test "rejects a non-https endpoint", %{user: user} do
    assert {:error, changeset} =
             Notifications.save_subscription(user.id, %{
               "endpoint" => "http://insecure.example/push",
               "p256dh" => "p256dh",
               "auth" => "auth"
             })

    assert %{endpoint: [_ | _]} = errors_on(changeset)
  end

  test "deletes a subscription", %{user: user} do
    {:ok, sub} = Notifications.save_subscription(user.id, subscription_attrs())
    assert {1, _} = Notifications.delete_subscription(sub.id)
    assert Notifications.list_user_subscriptions(user.id) == []
  end

  defp subscription_attrs do
    %{
      "endpoint" => "https://push.example/device-#{System.unique_integer([:positive])}",
      "p256dh" => "p256dh-key",
      "auth" => "auth-key"
    }
  end
end
