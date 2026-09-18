defmodule Xamt.Slug do
  @moduledoc """
  Converts names into URL-friendly slugs.
  """

  @doc """
  Slugifies a name: downcase, replace non-alphanumeric runs with `-`, trim edges.

  Returns `"untitled"` when the result would be empty. Callers add unique suffixes when needed.
  """
  def slugify(name) when is_binary(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
    |> case do
      "" -> "untitled"
      slug -> slug
    end
  end

  def slugify(_), do: "untitled"
end
