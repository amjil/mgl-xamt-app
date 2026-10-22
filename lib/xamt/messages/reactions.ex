defmodule Xamt.Messages.Reactions do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Xamt.Messages.Reaction
  alias Xamt.Repo

  @doc """
  Inserts or deletes the user's reaction for a message.

  Callers are responsible for authorization and broadcasting.
  """
  def toggle_on(message, user, emoji) do
    existing =
      Repo.get_by(Reaction, message_id: message.id, user_id: user.id, emoji: emoji)

    if existing do
      case Repo.delete(existing) do
        {:ok, reaction} -> {:ok, :removed, reaction}
        error -> error
      end
    else
      case %Reaction{}
           |> Reaction.changeset(%{message_id: message.id, user_id: user.id, emoji: emoji})
           |> Repo.insert() do
        {:ok, reaction} -> {:ok, :added, reaction}
        error -> error
      end
    end
  end

  @doc """
  Reactions for the given messages as `%{message_id => %{emoji => [user_id]}}`.
  """
  def summary([]), do: %{}

  def summary(message_ids) when is_list(message_ids) do
    from(r in Reaction,
      where: r.message_id in ^message_ids,
      order_by: [asc: r.inserted_at],
      select: {r.message_id, r.emoji, r.user_id}
    )
    |> Repo.all()
    |> Enum.reduce(%{}, fn {message_id, emoji, user_id}, acc ->
      Map.update(acc, message_id, %{emoji => [user_id]}, fn by_emoji ->
        Map.update(by_emoji, emoji, [user_id], &(&1 ++ [user_id]))
      end)
    end)
  end
end
