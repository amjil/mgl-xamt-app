defmodule Xamt.Messages.HtmlSanitizer do
  @moduledoc """
  Allowlist HTML sanitizer for message `content_html`.

  Client editors and the offline sync API are not a trust boundary. Anything that
  later passes through `Phoenix.HTML.raw/1` must be scrubbed here (and again at
  render for defense in depth against rows stored before this existed).
  """

  @allowed_tags MapSet.new(~w(
    a b blockquote br code del div em h1 h2 h3 h4 hr i img li ol p pre s span
    strong u ul
  ))

  # Tags whose contents must never be kept (even as text).
  @drop_with_children MapSet.new(~w(
    script style iframe object embed form input button textarea select option
    meta link base svg math video audio source track
  ))

  @allowed_attrs %{
    "a" =>
      MapSet.new(
        ~w(href class data-mention-id data-mention-username data-phx-link data-phx-link-state data-you)
      ),
    "img" => MapSet.new(~w(src alt class width height)),
    "div" => MapSet.new(~w(class data-block-type data-checked data-collapsed data-index)),
    "span" => MapSet.new(~w(class data-mention-id data-mention-username)),
    "p" => MapSet.new(~w(class)),
    "h1" => MapSet.new(~w(class)),
    "h2" => MapSet.new(~w(class)),
    "h3" => MapSet.new(~w(class)),
    "h4" => MapSet.new(~w(class)),
    "blockquote" => MapSet.new(~w(class)),
    "li" => MapSet.new(~w(class)),
    "ul" => MapSet.new(~w(class)),
    "ol" => MapSet.new(~w(class)),
    "pre" => MapSet.new(~w(class)),
    "code" => MapSet.new(~w(class)),
    "hr" => MapSet.new(~w(class)),
    "br" => MapSet.new([]),
    "b" => MapSet.new(~w(class)),
    "i" => MapSet.new(~w(class)),
    "u" => MapSet.new(~w(class)),
    "s" => MapSet.new(~w(class)),
    "em" => MapSet.new(~w(class)),
    "strong" => MapSet.new(~w(class)),
    "del" => MapSet.new(~w(class))
  }

  # ZWJ sequences + optional variation selectors. Flags are Extended_Pictographic pairs.
  @emoji_re ~r/(\p{Extended_Pictographic}(?:\x{FE0F}|\x{FE0E})?(?:\x{200D}\p{Extended_Pictographic}(?:\x{FE0F}|\x{FE0E})?)*)/u

  @doc """
  Returns allowlisted HTML. Empty / non-binary input becomes `""`.
  """
  def sanitize(nil), do: ""
  def sanitize(""), do: ""

  def sanitize(html) when is_binary(html) do
    case Floki.parse_fragment(html) do
      {:ok, tree} ->
        tree
        |> scrub_nodes()
        |> wrap_emojis()
        |> Floki.raw_html()

      {:error, _} ->
        ""
    end
  end

  def sanitize(_), do: ""

  defp scrub_nodes(nodes) when is_list(nodes) do
    Enum.flat_map(nodes, &scrub_node/1)
  end

  defp scrub_node(text) when is_binary(text), do: [text]

  defp scrub_node({:comment, _}), do: []

  defp scrub_node({tag, attrs, children}) when is_binary(tag) do
    tag = String.downcase(tag)

    cond do
      MapSet.member?(@drop_with_children, tag) ->
        []

      MapSet.member?(@allowed_tags, tag) ->
        scrubbed_attrs = scrub_attrs(tag, attrs)

        if tag == "img" and not Enum.any?(scrubbed_attrs, fn {name, _} -> name == "src" end) do
          []
        else
          [{tag, scrubbed_attrs, scrub_nodes(children)}]
        end

      true ->
        # Unwrap unknown tags; keep safe descendants.
        scrub_nodes(children)
    end
  end

  defp scrub_node(_), do: []

  defp wrap_emojis(nodes) when is_list(nodes), do: Enum.flat_map(nodes, &wrap_emoji_node/1)

  defp wrap_emoji_node(text) when is_binary(text), do: wrap_emoji_text(text)

  defp wrap_emoji_node({tag, attrs, children}) when is_binary(tag) do
    cond do
      tag in ["code", "pre"] ->
        [{tag, attrs, children}]

      emoji_span?(tag, attrs) ->
        [{tag, attrs, children}]

      true ->
        [{tag, attrs, wrap_emojis(children)}]
    end
  end

  defp wrap_emoji_node(other), do: [other]

  defp wrap_emoji_text(text) do
    @emoji_re
    |> Regex.split(text, include_captures: true, trim: false)
    |> Enum.flat_map(fn
      "" ->
        []

      part ->
        if Regex.match?(@emoji_re, part) do
          [{"span", [{"class", "xamt-emoji"}], [part]}]
        else
          [part]
        end
    end)
  end

  defp emoji_span?("span", attrs) do
    attrs
    |> Enum.find_value(fn {name, value} ->
      name == "class" && value
    end)
    |> Kernel.||("")
    |> String.split()
    |> Enum.member?("xamt-emoji")
  end

  defp emoji_span?(_, _), do: false

  defp scrub_attrs(tag, attrs) do
    allowed = Map.get(@allowed_attrs, tag, MapSet.new())

    attrs
    |> Enum.reduce([], fn {name, value}, acc ->
      name = String.downcase(to_string(name))

      cond do
        String.starts_with?(name, "on") ->
          acc

        name in ["style", "srcdoc", "formaction", "xlink:href"] ->
          acc

        not MapSet.member?(allowed, name) ->
          acc

        name == "href" ->
          case safe_href(value) do
            nil -> acc
            href -> [{name, href} | acc]
          end

        name == "src" ->
          case safe_src(value) do
            nil -> acc
            src -> [{name, src} | acc]
          end

        name == "class" ->
          case safe_class(value) do
            nil -> acc
            class -> [{name, class} | acc]
          end

        name in ["width", "height"] ->
          case safe_dimension(value) do
            nil -> acc
            dim -> [{name, dim} | acc]
          end

        name in [
          "data-mention-id",
          "data-mention-username",
          "data-phx-link",
          "data-phx-link-state",
          "data-you",
          "data-block-type",
          "data-checked",
          "data-collapsed",
          "data-index",
          "alt"
        ] ->
          [{name, scrub_attr_value(value)} | acc]

        true ->
          acc
      end
    end)
    |> Enum.reverse()
  end

  defp safe_href(value) when is_binary(value) do
    value = String.trim(value)

    cond do
      value == "" ->
        nil

      String.contains?(value, ["<", ">", "\"", "'"]) ->
        nil

      # Protocol-relative or sneaky schemes
      String.starts_with?(value, "//") ->
        nil

      String.match?(value, ~r/^\s*(javascript|vbscript|data)\s*:/i) ->
        nil

      String.starts_with?(value, "/") and not String.starts_with?(value, "//") ->
        if String.contains?(value, ".."), do: nil, else: value

      String.match?(value, ~r/^https?:\/\//i) ->
        value

      true ->
        nil
    end
  end

  defp safe_href(_), do: nil

  defp safe_src(value) when is_binary(value) do
    value = String.trim(value)

    cond do
      value == "" ->
        nil

      String.contains?(value, ["<", ">", "\"", "'"]) ->
        nil

      String.starts_with?(value, "/uploads/") and not String.contains?(value, "..") ->
        value

      String.match?(value, ~r/^https?:\/\//i) ->
        value

      true ->
        nil
    end
  end

  defp safe_src(_), do: nil

  defp safe_class(value) when is_binary(value) do
    cleaned =
      value
      |> String.split(~r/\s+/, trim: true)
      |> Enum.filter(&String.match?(&1, ~r/^[A-Za-z0-9_-]+$/))
      |> Enum.join(" ")

    if cleaned == "", do: nil, else: cleaned
  end

  defp safe_class(_), do: nil

  defp safe_dimension(value) when is_binary(value) do
    if String.match?(value, ~r/^\d{1,4}(px)?$/i), do: value, else: nil
  end

  defp safe_dimension(value) when is_integer(value) and value >= 0 and value <= 9999,
    do: Integer.to_string(value)

  defp safe_dimension(_), do: nil

  defp scrub_attr_value(value) when is_binary(value) do
    value
    |> String.replace(~r/[\x00-\x1F\x7F]/, "")
    |> String.replace(~r/[<>"']/, "")
  end

  defp scrub_attr_value(value), do: scrub_attr_value(to_string(value))
end
