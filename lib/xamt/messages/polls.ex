defmodule Xamt.Messages.Polls do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Xamt.Repo
  alias Xamt.Messages.{Poll, PollOption, PollVote}

  @min_options 2
  @max_options 10

  @doc "Minimum / maximum option counts for a new poll."
  def option_limits, do: {@min_options, @max_options}

  @doc """
  Inserts a poll and its options for an existing message.

  Caller must run this inside the same transaction as the message insert.
  """
  def insert_for_message!(message_id, question, options, allow_multiple, results_open \\ true)
      when is_binary(message_id) and is_binary(question) and is_list(options) do
    cleaned =
      options
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    if length(cleaned) < @min_options or length(cleaned) > @max_options do
      raise ArgumentError,
            "polls require #{@min_options}..#{@max_options} non-empty options, got #{length(cleaned)}"
    end

    {:ok, poll} =
      %Poll{}
      |> Poll.changeset(%{
        message_id: message_id,
        question: String.trim(question),
        allow_multiple: allow_multiple == true,
        results_open: results_open != false
      })
      |> Repo.insert()

    Enum.with_index(cleaned)
    |> Enum.each(fn {text, index} ->
      %PollOption{}
      |> PollOption.changeset(%{
        poll_id: poll.id,
        text: text,
        position: index,
        votes_count: 0
      })
      |> Repo.insert!()
    end)

    get_poll_with_options!(poll.id)
  end

  @doc """
  Toggles the user's vote on an option.

  Returns `{:ok, payload}` where payload is suitable for PubSub / LiveView,
  or `{:error, reason}`.
  """
  def toggle_vote(user_id, poll_id, option_id)
      when is_binary(user_id) and is_binary(poll_id) and is_binary(option_id) do
    poll = get_poll_with_options(poll_id)

    cond do
      is_nil(poll) ->
        {:error, :not_found}

      not Enum.any?(poll.poll_options, &(&1.id == option_id)) ->
        {:error, :invalid_option}

      true ->
        do_toggle_vote(poll, user_id, option_id)
    end
  end

  defp do_toggle_vote(poll, user_id, option_id) do
    result =
      Ecto.Multi.new()
      |> Ecto.Multi.run(:vote_op, fn repo, _ ->
        existing =
          repo.get_by(PollVote, user_id: user_id, poll_option_id: option_id)

        cond do
          existing ->
            with {:ok, _} <- repo.delete(existing) do
              {:ok, {:removed, [option_id]}}
            end

          poll.allow_multiple ->
            insert_vote(repo, poll.id, option_id, user_id)

          true ->
            switch_single_vote(repo, poll, user_id, option_id)
        end
      end)
      |> Ecto.Multi.run(:update_counts, fn repo, %{vote_op: op} ->
        case op do
          {:removed, [id]} ->
            bump_count(repo, id, -1)
            {:ok, :ok}

          {:added, added_id, removed_ids} ->
            Enum.each(removed_ids, &bump_count(repo, &1, -1))
            bump_count(repo, added_id, 1)
            {:ok, :ok}
        end
      end)
      |> Repo.transaction()

    case result do
      {:ok, _} ->
        poll = get_poll_with_options!(poll.id)
        selected = option_ids_for_user(user_id, poll.id)
        {:ok, summary_entry(poll, selected)}

      {:error, _op, reason, _} ->
        {:error, reason}
    end
  end

  defp insert_vote(repo, poll_id, option_id, user_id) do
    case %PollVote{}
         |> PollVote.changeset(%{
           poll_id: poll_id,
           poll_option_id: option_id,
           user_id: user_id
         })
         |> repo.insert() do
      {:ok, _} ->
        {:ok, {:added, option_id, []}}

      {:error, %Ecto.Changeset{errors: errors} = cs} ->
        if Keyword.has_key?(errors, :poll_option_id) do
          {:error, :already_voted}
        else
          {:error, cs}
        end
    end
  end

  defp switch_single_vote(repo, poll, user_id, option_id) do
    others =
      from(v in PollVote,
        where: v.poll_id == ^poll.id and v.user_id == ^user_id,
        select: {v.id, v.poll_option_id}
      )
      |> repo.all()

    removed_option_ids = Enum.map(others, fn {_id, oid} -> oid end)

    if others != [] do
      ids = Enum.map(others, fn {id, _} -> id end)

      from(v in PollVote, where: v.id in ^ids)
      |> repo.delete_all()
    end

    insert_vote(repo, poll.id, option_id, user_id)
    |> case do
      {:ok, {:added, added_id, _}} -> {:ok, {:added, added_id, removed_option_ids}}
      other -> other
    end
  end

  defp bump_count(repo, option_id, delta) do
    from(o in PollOption, where: o.id == ^option_id)
    |> repo.update_all(inc: [votes_count: delta])
  end

  @doc """
  Poll summaries keyed by message_id for LiveView side assigns.
  """
  def summary([]), do: %{}

  def summary(message_ids) when is_list(message_ids) do
    polls =
      from(p in Poll,
        where: p.message_id in ^message_ids,
        preload: [poll_options: ^from(o in PollOption, order_by: [asc: o.position, asc: o.id])]
      )
      |> Repo.all()

    Map.new(polls, fn poll ->
      {poll.message_id, summary_entry(poll, MapSet.new())}
    end)
  end

  @doc """
  Selected option ids for a user, keyed by poll_id.
  """
  def votes_for_user(_user_id, []), do: %{}

  def votes_for_user(user_id, poll_ids) when is_list(poll_ids) do
    from(v in PollVote,
      where: v.user_id == ^user_id and v.poll_id in ^poll_ids,
      select: {v.poll_id, v.poll_option_id}
    )
    |> Repo.all()
    |> Enum.reduce(%{}, fn {poll_id, option_id}, acc ->
      Map.update(acc, poll_id, MapSet.new([option_id]), &MapSet.put(&1, option_id))
    end)
  end

  def get_poll_with_options!(id) do
    case get_poll_with_options(id) do
      nil -> raise Ecto.NoResultsError, queryable: Poll
      poll -> poll
    end
  end

  def get_poll_with_options(id) do
    from(p in Poll,
      where: p.id == ^id,
      preload: [poll_options: ^from(o in PollOption, order_by: [asc: o.position, asc: o.id])]
    )
    |> Repo.one()
  end

  def get_by_message_id(message_id) when is_binary(message_id) do
    from(p in Poll,
      where: p.message_id == ^message_id,
      preload: [poll_options: ^from(o in PollOption, order_by: [asc: o.position, asc: o.id])]
    )
    |> Repo.one()
  end

  @doc """
  Full poll breakdown for the details sheet: each option with its voters.

  Voters are ordered by vote time ascending. Returns `nil` when missing.
  """
  def details(poll_id) when is_binary(poll_id) do
    case get_poll_with_options(poll_id) do
      nil ->
        nil

      poll ->
        voters_by_option = voters_grouped(poll.id)

        options =
          Enum.map(poll.poll_options, fn opt ->
            %{
              id: opt.id,
              text: opt.text,
              votes_count: opt.votes_count,
              position: opt.position,
              voters: Map.get(voters_by_option, opt.id, [])
            }
          end)

        %{
          id: poll.id,
          message_id: poll.message_id,
          question: poll.question,
          allow_multiple: poll.allow_multiple,
          results_open: poll.results_open,
          options: options,
          total_votes: Enum.sum(Enum.map(options, & &1.votes_count))
        }
    end
  end

  defp voters_grouped(poll_id) do
    from(v in PollVote,
      join: u in assoc(v, :user),
      where: v.poll_id == ^poll_id,
      order_by: [asc: v.inserted_at, asc: v.id],
      select:
        {v.poll_option_id,
         %{
           id: u.id,
           username: u.username,
           display_name: u.display_name,
           avatar: u.avatar,
           status_emoji: u.status_emoji,
           status_text: u.status_text
         }}
    )
    |> Repo.all()
    |> Enum.reduce(%{}, fn {option_id, user}, acc ->
      Map.update(acc, option_id, [user], &(&1 ++ [user]))
    end)
  end

  defp option_ids_for_user(user_id, poll_id) do
    from(v in PollVote,
      where: v.user_id == ^user_id and v.poll_id == ^poll_id,
      select: v.poll_option_id
    )
    |> Repo.all()
    |> MapSet.new()
  end

  defp summary_entry(%Poll{} = poll, selected) do
    options =
      Enum.map(poll.poll_options, fn opt ->
        %{
          id: opt.id,
          text: opt.text,
          votes_count: opt.votes_count,
          position: opt.position
        }
      end)

    %{
      id: poll.id,
      message_id: poll.message_id,
      question: poll.question,
      allow_multiple: poll.allow_multiple,
      results_open: poll.results_open,
      options: options,
      selected_option_ids: MapSet.to_list(selected)
    }
  end
end
