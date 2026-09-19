defmodule Xamt.Notifications do
  @moduledoc """
  Push subscription credentials for Web Push.

  One user can have many devices; `endpoint` is globally unique so the same
  browser cannot be stored twice.
  """

  import Ecto.Query, warn: false

  alias Xamt.Notifications.PushSubscription
  alias Xamt.Repo

  @doc """
  Inserts a subscription, or updates keys / owner when the endpoint already exists.

  Replacing on conflict lets a shared device move to the newly signed-in user
  instead of keeping a stale owner.
  """
  def save_subscription(user_id, attrs) when is_binary(user_id) and is_map(attrs) do
    %PushSubscription{}
    |> PushSubscription.changeset(attrs)
    |> Ecto.Changeset.put_change(:user_id, user_id)
    |> Repo.insert(
      on_conflict: {:replace, [:user_id, :p256dh, :auth, :updated_at]},
      conflict_target: :endpoint,
      returning: true
    )
  end

  def list_user_subscriptions(user_id) when is_binary(user_id) do
    from(s in PushSubscription, where: s.user_id == ^user_id)
    |> Repo.all()
  end

  def delete_subscription(id) when is_binary(id) do
    from(s in PushSubscription, where: s.id == ^id)
    |> Repo.delete_all()
  end
end
