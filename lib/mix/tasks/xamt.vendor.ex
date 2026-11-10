defmodule Mix.Tasks.Xamt.Vendor do
  @moduledoc """
  Copies sibling front-end packages into `assets/vendor`.

  Packages (optional filter args: `mix xamt.vendor mgl-web-ime`):

    * `mgl-common-ui` — JS/CSS from `mgl-common-ui.js`
    * `mgl-web-ime` — ESM build + CSS + source map from `mgl-web-ime.js/dist`
    * `mongolian-editor` — single file from `richtext-editor.js`

  Source resolution for each package (first match):

    1. env var (`MGL_COMMON_UI_PATH`, `MGL_WEB_IME_PATH`, `MONGOLIAN_EDITOR_PATH`)
    2. `:xamt` application config (`:mgl_common_ui_path`, …)
    3. sibling checkout next to this app

  If a source is missing, the existing vendor copy is kept so CI/deploy
  does not depend on sibling checkouts.
  """
  use Mix.Task

  @shortdoc "Vendor sibling JS packages into assets/vendor"

  @packages ~w(mgl-common-ui mgl-web-ime mongolian-editor)

  @impl Mix.Task
  def run(args) do
    selected =
      case args do
        [] -> @packages
        names -> Enum.map(names, &normalize_name/1)
      end

    Enum.each(selected, &vendor_package!/1)
  end

  defp normalize_name(name) when name in @packages, do: name

  defp normalize_name(name) do
    Mix.raise(
      "Unknown vendor package #{inspect(name)}. Expected one of: #{Enum.join(@packages, ", ")}"
    )
  end

  defp vendor_package!("mgl-common-ui") do
    dest = Path.expand("assets/vendor/mgl-common-ui")
    src = resolve_source(:mgl_common_ui_path, "MGL_COMMON_UI_PATH", "mgl-common-ui.js")

    with_source(src, dest, "mgl-common-ui", fn root ->
      File.mkdir_p!(dest)
      copy_tree!(Path.join(root, "src"), dest)
      File.cp!(Path.join(root, "styles/mgl-common-ui.css"), Path.join(dest, "mgl-common-ui.css"))
      Mix.shell().info("Vendored mgl-common-ui from #{root}")
    end)
  end

  defp vendor_package!("mgl-web-ime") do
    dest = Path.expand("assets/vendor/mgl-web-ime")
    src = resolve_source(:mgl_web_ime_path, "MGL_WEB_IME_PATH", "mgl-web-ime.js")

    with_source(src, dest, "mgl-web-ime", fn root ->
      dist = Path.join(root, "dist")

      unless File.dir?(dist) do
        Mix.raise("mgl-web-ime dist/ missing at #{dist}. Build the package first.")
      end

      File.mkdir_p!(dest)

      for name <- ~w(mgl-web-ime.js mgl-web-ime.js.map mgl-web-ime.css) do
        File.cp!(Path.join(dist, name), Path.join(dest, name))
      end

      Mix.shell().info("Vendored mgl-web-ime from #{dist}")
    end)
  end

  defp vendor_package!("mongolian-editor") do
    dest = Path.expand("assets/vendor/mongolian-editor.js")
    src = resolve_source(:mongolian_editor_path, "MONGOLIAN_EDITOR_PATH", "richtext-editor.js")

    with_source(src, dest, "mongolian-editor", fn root ->
      file = Path.join(root, "mongolian-editor.js")

      unless File.regular?(file) do
        Mix.raise("mongolian-editor.js not found at #{file}")
      end

      File.mkdir_p!(Path.dirname(dest))
      File.cp!(file, dest)
      Mix.shell().info("Vendored mongolian-editor from #{file}")
    end)
  end

  defp with_source(src, dest, label, fun) do
    cond do
      is_binary(src) and File.dir?(src) ->
        fun.(src)

      exists?(dest) ->
        Mix.shell().info("Keeping #{dest} (#{label} source not found)")

      true ->
        Mix.raise("""
        #{label} not found. Set the matching env/config path or clone it next to this app.
        """)
    end
  end

  defp resolve_source(config_key, env_key, sibling_name) do
    System.get_env(env_key) ||
      Application.get_env(:xamt, config_key) ||
      Path.expand("../#{sibling_name}", Path.dirname(Mix.Project.project_file()))
  end

  defp exists?(path) do
    File.dir?(path) or File.regular?(path)
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
