defmodule TemplatePhoenixWeb.UserLive.PasskeysTest do
  use TemplatePhoenixWeb.ConnCase, async: true

  import Mox
  import Phoenix.LiveViewTest
  import TemplatePhoenix.AccountsFixtures

  alias TemplatePhoenix.Accounts.Passkeys
  alias TemplatePhoenix.Accounts.Scope

  setup :verify_on_exit!

  setup do
    Mox.stub_with(TemplatePhoenix.MockWebAuthn, TemplatePhoenix.Accounts.FakeWebAuthn)
    :ok
  end

  setup %{conn: conn} do
    user = user_fixture()
    %{conn: log_in_user(conn, user), user: user}
  end

  test "requires sudo mode", %{user: user} do
    # Mirrors the generated user_auth_test.exs' `on_mount :require_sudo_mode`
    # staleness idiom exactly: `eleven_minutes_ago = DateTime.utc_now(:second)
    # |> DateTime.add(-11, :minute)`, threaded through `log_in_user/3`'s
    # `token_authenticated_at` option (ConnCase) into
    # `override_token_authenticated_at/2` (AccountsFixtures). The sudo window
    # for this LiveView's `on_mount {UserAuth, :require_sudo_mode}` is -10
    # minutes (see `UserAuth.on_mount(:require_sudo_mode, ...)`), so -11
    # minutes is stale.
    eleven_minutes_ago = DateTime.utc_now(:second) |> DateTime.add(-11, :minute)

    conn = log_in_user(build_conn(), user, token_authenticated_at: eleven_minutes_ago)

    assert {:error, {:redirect, %{to: "/users/log-in"}}} =
             live(conn, ~p"/users/settings/passkeys")
  end

  test "adds a passkey via the hook round-trip", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/users/settings/passkeys")

    view |> element("#add-passkey") |> render_click()
    assert_push_event(view, "webauthn:register", %{challenge: _, user: %{id: _}})

    render_hook(view, "webauthn:registered", webauthn_registration_payload("settings-cred"))

    assert has_element?(view, "#passkeys-table")
    assert render(view) =~ "always requires a passkey"
    assert Passkeys.passkeys_enabled?(user)
  end

  test "double-submitting the same registration payload does not add a second passkey", %{
    conn: conn,
    user: user
  } do
    {:ok, view, _html} = live(conn, ~p"/users/settings/passkeys")

    view |> element("#add-passkey") |> render_click()
    assert_push_event(view, "webauthn:register", %{challenge: _, user: %{id: _}})

    payload = webauthn_registration_payload("double-submit-cred")

    render_hook(view, "webauthn:registered", payload)
    assert length(Passkeys.list_passkeys(Scope.for_user(user))) == 1

    render_hook(view, "webauthn:registered", payload)

    assert render(view) =~ "No registration in progress"
    assert length(Passkeys.list_passkeys(Scope.for_user(user))) == 1
  end

  test "renames and deletes, with last-passkey messaging", %{conn: conn, user: user} do
    passkey = user_passkey_fixture(user)
    {:ok, view, _html} = live(conn, ~p"/users/settings/passkeys")

    view
    |> form("#rename-passkey-#{passkey.id}", %{"passkey" => %{"name" => "Work Yubikey"}})
    |> render_submit()

    assert has_element?(view, "#passkey-#{passkey.id}", "Work Yubikey")

    view |> element("#delete-passkey-#{passkey.id}") |> render_click()
    refute has_element?(view, "#passkey-#{passkey.id}")
    assert render(view) =~ "two-factor is now off"
    refute Passkeys.passkeys_enabled?(user)
  end

  test "another user's passkey id cannot be touched", %{conn: conn} do
    other_passkey = user_passkey_fixture(user_fixture())
    {:ok, view, _html} = live(conn, ~p"/users/settings/passkeys")
    refute has_element?(view, "#passkey-#{other_passkey.id}")
  end

  test "webauthn:error renders server-owned copy", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/users/settings/passkeys")
    render_hook(view, "webauthn:error", %{"name" => "InvalidStateError", "message" => ""})
    assert render(view) =~ "already registered"
  end

  test "webauthn:error without a name is answered generically", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/users/settings/passkeys")
    render_hook(view, "webauthn:error", %{"unexpected" => 1})
    assert render(view) =~ "Something went wrong"
  end
end
