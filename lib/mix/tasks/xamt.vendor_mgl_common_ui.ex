defmodule Mix.Tasks.Xamt.VendorMglCommonUi do
  @moduledoc """
  Copies mgl-common-ui JS/CSS into `assets/vendor/mgl-common-ui`.

  Source path (first match):
    1. `MGL_COMMON_UI_PATH`
    2. `:xamt, :mgl_common_ui_path`
    3. sibling `../mgl-common-ui.js` next to this app

  If the source is missing, the existing vendor copy is kept so CI/deploy
  does not depend on the sibling checkout.
  """
  use Mix.Task

  @shortdoc "Vendor mgl-common-ui into assets/vendor"

  @impl Mix.Task
  def run(_args) do
    dest = Path.expand("assets/vendor/mgl-common-ui")
    src = source_root()

    cond do
      is_binary(src) and File.dir?(src) ->
        File.mkdir_p!(dest)
        copy_tree!(Path.join(src, "src"), dest)
        File.cp!(Path.join(src, "styles/mgl-common-ui.css"), Path.join(dest, "mgl-common-ui.css"))
        Mix.shell().info("Vendored mgl-common-ui from #{src}")

      File.dir?(dest) ->
        Mix.shell().info("Keeping #{dest} (source not found)")

      true ->
        Mix.raise("""
        mgl-common-ui not found. Set MGL_COMMON_UI_PATH or clone it next to this app.
        """)
    end
  end

  defp source_root do
    System.get_env("MGL_COMMON_UI_PATH") ||
      Application.get_env(:xamt, :mgl_common_ui_path) ||
      Path.expand("../mgl-common-ui.js", Path.dirname(Mix.Project.project_file()))
  end

  defp copy_tree!(from, to) do
    Path.wildcard(Path.join(from, "**/*"))
    |> Enum.filter(&File.regular?/1)
    |> Enum.each(fn file ->
      rel = Path.relative_to(file, from)
      target = Path.join(to, rel)
      File.mkdir_p!(Path.dirname(target))
      File.cp!(file, target)
    end)
  end
end
