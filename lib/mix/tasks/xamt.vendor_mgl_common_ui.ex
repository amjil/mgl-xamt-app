defmodule Mix.Tasks.Xamt.VendorMglCommonUi do
  @moduledoc """
  Deprecated alias for `mix xamt.vendor mgl-common-ui`.

  Prefer `mix xamt.vendor`, which also vendors mgl-web-ime and mongolian-editor.
  """
  use Mix.Task

  @shortdoc "Vendor mgl-common-ui (alias of mix xamt.vendor mgl-common-ui)"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("xamt.vendor", ["mgl-common-ui"])
  end
end
