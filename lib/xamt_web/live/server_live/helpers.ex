defmodule XamtWeb.ServerLive.Helpers do
  @moduledoc false

  use Gettext, backend: XamtWeb.Gettext

  alias Xamt.Messages
  alias Xamt.Messages.Reaction

  # Consecutive messages from the same author within this window share one header.
  @grouping_threshold_seconds 300
  @long_text_threshold 400

  # `list_messages/2` already returns chronological (oldest first) after reversing
  # the desc query. Walk that order so each message is compared to its predecessor.
  def process_message_grouping(messages, timezone_offset) do
    empty_info = %{user_id: nil, time: nil}

    {acc, last_info, flags} =
      Enum.reduce(messages, {[], empty_info, %{}}, fn msg, {acc, prev_info, flags} ->
        show_header? = start_of_group?(prev_info, msg, timezone_offset)
        msg = %{msg | show_header: show_header?}
        info = %{user_id: msg.user_id, time: msg.inserted_at}

        {[msg | acc], info, Map.put(flags, msg.id, show_header?)}
      end)

    {Enum.reverse(acc), last_info, flags}
  end

  def start_of_group?(%{user_id: prev_user, time: prev_time}, message, offset) do
    is_nil(prev_user) or is_nil(prev_time) or prev_user != message.user_id or
      needs_date_divider?(prev_time, message.inserted_at, offset) or
      DateTime.diff(message.inserted_at, prev_time) > @grouping_threshold_seconds
  end

  def oldest_message_info([first | _]) do
    %{id: first.id, user_id: first.user_id, time: first.inserted_at}
  end

  def oldest_message_info(_), do: %{id: nil, user_id: nil, time: nil}

  def header_visible?(%{show_header: false}), do: false
  def header_visible?(_), do: true

  # Flatten virtual date dividers into the message stream so sticky CSS can
  # push prior day labels when a newer divider scrolls into view (vertical-lr).
  def with_date_dividers(messages, timezone_offset) do
    {items, _prev_date} =
      Enum.reduce(messages, {[], nil}, fn msg, {acc, prev_date} ->
        date = local_date(msg.inserted_at, timezone_offset)

        acc =
          if is_nil(prev_date) or prev_date != date do
            [msg, date_divider(date) | acc]
          else
            [msg | acc]
          end

        {acc, date}
      end)

    Enum.reverse(items)
  end

  def needs_date_divider?(nil, _new_at, _offset), do: true

  def needs_date_divider?(prev_at, new_at, offset) do
    local_date(prev_at, offset) != local_date(new_at, offset)
  end

  def date_divider(%Date{} = date) do
    %{
      id: "date-#{Date.to_iso8601(date)}",
      type: :date_divider,
      date: Date.to_iso8601(date)
    }
  end

  def date_divider?(%{type: :date_divider}), do: true
  def date_divider?(_), do: false

  def local_date(%DateTime{} = dt, offset) when is_integer(offset) do
    dt
    |> DateTime.add(-offset, :minute)
    |> DateTime.to_date()
  end

  def reactions_for(reactions, message_id) do
    reactions
    |> Map.get(message_id, %{})
    |> Enum.sort_by(fn {emoji, _users} -> Enum.find_index(Reaction.emojis(), &(&1 == emoji)) end)
  end

  def picker_emojis(reactions, message_id) do
    Reaction.emojis() -- Map.keys(Map.get(reactions, message_id, %{}))
  end

  def reaction_digits(user_ids) do
    user_ids |> length() |> Integer.to_string() |> String.length()
  end

  def display_name(%{display_name: name}) when is_binary(name) and name != "", do: name
  def display_name(%{username: name}) when is_binary(name), do: name
  def display_name(%{email: email}), do: email
  def display_name(_), do: "?"

  def own_presence_user?(%{id: id}, %{id: current_id})
      when not is_nil(id) and not is_nil(current_id) do
    to_string(id) == to_string(current_id)
  end

  def own_presence_user?(_, _), do: false

  def format_time(nil, _offset), do: ""

  def format_time(%DateTime{} = dt, offset) when is_integer(offset) do
    dt
    |> DateTime.add(-offset, :minute)
    |> Calendar.strftime("%H:%M")
  end

  def edited?(%{inserted_at: a, updated_at: b}) when not is_nil(a) and not is_nil(b) do
    DateTime.compare(b, a) == :gt
  end

  def edited?(_), do: false

  def mentioned?(%{mentioned_user_ids: ids}, %{id: user_id})
      when is_list(ids) and is_binary(user_id),
      do: user_id in ids

  def mentioned?(_, _), do: false

  def link_preview(%{link_preview: preview})
      when is_map(preview) and map_size(preview) > 0,
      do: preview

  def link_preview(_), do: nil

  def mention_search_row(%{user: user}) do
    %{
      id: user.id,
      username: user.username,
      display_name: display_name(user),
      avatar: user.avatar
    }
  end

  # `content_html` is sanitized on write; scrub again here so older rows and any
  # missed path cannot reach `raw/1` with attacker-controlled markup.
  def safe_html(message, current_user_id)

  def safe_html(%{content_html: html}, current_user_id)
      when is_binary(html) and html != "" do
    html
    |> Xamt.Messages.HtmlSanitizer.sanitize()
    |> decorate_own_mentions(current_user_id)
  end

  def safe_html(%{content: %{"html" => html}}, current_user_id) when is_binary(html) do
    html
    |> Xamt.Messages.HtmlSanitizer.sanitize()
    |> decorate_own_mentions(current_user_id)
  end

  def safe_html(%{content: content}, _current_user_id) when is_map(content),
    do: Phoenix.HTML.html_escape(inspect(content))

  def safe_html(_, _), do: ""

  def decorate_own_mentions(html, user_id) when is_binary(html) and is_binary(user_id) do
    String.replace(
      html,
      ~s(data-mention-id="#{user_id}"),
      ~s(data-mention-id="#{user_id}" data-you="true")
    )
  end

  def decorate_own_mentions(html, _), do: html

  def typing_label(typing_users) do
    names = Map.values(typing_users)

    case names do
      [] ->
        ""

      [name] ->
        gettext("%{name} is typing...", name: name)

      [name1, name2] ->
        gettext("%{name1} and %{name2} are typing...", name1: name1, name2: name2)

      _ ->
        gettext("Several people are typing...")
    end
  end

  def decode_json(nil), do: %{}
  def decode_json(""), do: %{}

  def decode_json(str) when is_binary(str) do
    case Jason.decode(str) do
      {:ok, data} -> data
      _ -> %{}
    end
  end

  def decode_json(data) when is_map(data), do: data

  def build_message_attrs(params, images, replying_to) when is_list(images) and images != [] do
    caption = params["content_html"] || ""
    content_json = decode_json(params["content_json"])
    images = Enum.take(images, 10)

    content =
      content_json
      |> Map.take(["blocks", "html", "json"])
      |> Map.merge(%{"type" => "gallery", "images" => images})

    attrs = %{
      "content" => content,
      "content_html" => caption,
      "content_type" => "gallery"
    }

    if replying_to do
      Map.put(attrs, "reply_to_id", replying_to.id)
    else
      attrs
    end
  end

  def build_message_attrs(params, _images, replying_to) do
    # Gallery/audio/poll must go through their dedicated upload/create paths.
    # Never trust a client-claimed media content_type without server uploads.
    content_type =
      case params["content_type"] do
        type when type in ["plain_text", "rich_text"] -> type
        _ -> "rich_text"
      end

    attrs = %{
      "content" => decode_json(params["content_json"]),
      "content_html" => params["content_html"] || "",
      "content_type" => content_type
    }

    if replying_to do
      Map.put(attrs, "reply_to_id", replying_to.id)
    else
      attrs
    end
  end

  def gallery_images(%{content: %{"type" => "gallery", "images" => images}})
      when is_list(images) and images != [] do
    images
    |> Enum.map(&normalize_gallery_image/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.take(10)
    |> case do
      [] -> nil
      list -> list
    end
  end

  def gallery_images(_), do: nil

  def normalize_gallery_image(%{"thumb" => thumb, "original" => original})
      when is_binary(thumb) and is_binary(original) do
    if safe_upload_url?(thumb) and safe_upload_url?(original) do
      %{"thumb" => thumb, "original" => original}
    end
  end

  def normalize_gallery_image(_), do: nil

  def safe_upload_url?(url), do: Messages.safe_upload_path?(url)

  def gallery_count_attr(total) when total > 8, do: "overflow"
  def gallery_count_attr(total) when total in 1..8, do: to_string(total)
  def gallery_count_attr(_), do: "1"

  def caption_html?(%{content_html: html}) when is_binary(html) do
    String.trim(html) != ""
  end

  def caption_html?(_), do: false

  def collapsible_text?(message) do
    is_nil(audio_src(message)) and is_nil(gallery_images(message)) and
      message.content_type != "poll" and long_text?(message)
  end

  def long_text?(message) do
    String.length(Messages.plain_text(message)) > @long_text_threshold
  end

  def audio_src(%{content: %{"type" => "audio", "url" => url}}) when is_binary(url) do
    if safe_upload_url?(url), do: url
  end

  def audio_src(_), do: nil

  def deleted?(%{deleted_at: %DateTime{}}), do: true
  def deleted?(_), do: false
end
