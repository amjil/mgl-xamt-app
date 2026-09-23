defmodule Xamt.SiteSettingsTest do
  use Xamt.DataCase, async: true

  import Xamt.AccountsFixtures

  alias Xamt.SiteSettings

  test "registration is enabled by default" do
    assert SiteSettings.registration_enabled?()
    assert SiteSettings.get().registration_enabled
  end

  test "admins can close and reopen registration" do
    admin = admin_fixture()

    assert {:ok, closed} = SiteSettings.update_registration_enabled(admin, false)
    refute closed.registration_enabled
    refute SiteSettings.registration_enabled?()

    assert {:ok, opened} = SiteSettings.update_registration_enabled(admin, true)
    assert opened.registration_enabled
    assert SiteSettings.registration_enabled?()
  end

  test "non-admins cannot change registration" do
    user = user_fixture()
    creator = creator_fixture()

    assert {:error, :unauthorized} = SiteSettings.update_registration_enabled(user, false)
    assert {:error, :unauthorized} = SiteSettings.update_registration_enabled(creator, false)
    assert SiteSettings.registration_enabled?()
  end
end
