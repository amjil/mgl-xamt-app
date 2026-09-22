defmodule XamtWeb.RoleHelperTest do
  use ExUnit.Case, async: true

  alias XamtWeb.RoleHelper

  describe "get_role_ui_config/1" do
    test "maps admin to red-role classes and badge" do
      ui = RoleHelper.get_role_ui_config("admin")

      assert ui.color_class == "xamt-role--admin"
      assert ui.bg_class == "xamt-role-badge--admin"
      assert ui.accent_class == "xamt-profile--role-admin"
      assert ui.label == "Admin"
      assert ui.icon == "hero-shield-check"
    end

    test "maps creator to gold-role classes and badge" do
      ui = RoleHelper.get_role_ui_config("creator")

      assert ui.color_class == "xamt-role--creator"
      assert ui.bg_class == "xamt-role-badge--creator"
      assert ui.accent_class == "xamt-profile--role-creator"
      assert ui.label == "Creator"
      assert ui.icon == "hero-sparkles"
    end

    test "accepts a user-like map via global_role" do
      ui = RoleHelper.get_role_ui_config(%{global_role: "admin"})
      assert ui.color_class == "xamt-role--admin"
    end

    test "falls back for ordinary users" do
      ui = RoleHelper.get_role_ui_config("user")

      assert ui.color_class == nil
      assert ui.bg_class == nil
      assert ui.accent_class == nil
      assert ui.label == nil
      assert ui.icon == nil
    end
  end
end
