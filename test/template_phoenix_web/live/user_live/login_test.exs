defmodule TemplatePhoenixWeb.UserLive.LoginTest do
  use TemplatePhoenixWeb.ConnCase, async: true

  import Ecto.Query
  import Mox
  import Phoenix.LiveViewTest
  import TemplatePhoenix.AccountsFixtures

  alias TemplatePhoenix.Accounts.Passkeys
  alias TemplatePhoenix.Accounts.Scope
  alias TemplatePhoenix.Accounts.UserToken
  alias TemplatePhoenix.Repo

  setup :verify_on_exit!

  setup do
    Mox.stub_with(TemplatePhoenix.MockWebAuthn, TemplatePhoenix.Accounts.FakeWebAuthn)
    :ok
  end

  describe "login page" do
    test "renders login page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/log-in")

      assert html =~ "Log in"
      assert html =~ "Sign up"
      assert html =~ "Log in with email"
    end

    test "navbar shows log-in links when signed out", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/log-in")
      assert has_element?(view, "#user-menu-log-in")
      refute has_element?(view, "#user-menu-log-out")
    end
  end

  describe "user login - magic link" do
    test "sends magic link email when user exists", %{conn: conn} do
      user = user_fixture()

      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      {:ok, _lv, html} =
        form(lv, "#login_form_magic", user: %{email: user.email})
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/log-in")

      assert html =~ "If your email is in our system"

      assert TemplatePhoenix.Repo.get_by!(TemplatePhoenix.Accounts.UserToken, user_id: user.id).context ==
               "login"
    end

    test "does not disclose if user is registered", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      {:ok, _lv, html} =
        form(lv, "#login_form_magic", user: %{email: "idonotexist@example.com"})
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/log-in")

      assert html =~ "If your email is in our system"
    end
  end

  describe "user login - password" do
    test "redirects if user logs in with valid credentials", %{conn: conn} do
      user = user_fixture() |> set_password()

      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      form =
        form(lv, "#login_form_password",
          user: %{email: user.email, password: valid_user_password(), remember_me: true}
        )

      conn = submit_form(form, conn)

      assert redirected_to(conn) == ~p"/"
    end

    test "redirects to login page with a flash error if credentials are invalid", %{
      conn: conn
    } do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      form =
        form(lv, "#login_form_password", user: %{email: "test@email.com", password: "123456"})

      render_submit(form, %{user: %{remember_me: true}})

      conn = follow_trigger_action(form, conn)
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password"
      assert redirected_to(conn) == ~p"/users/log-in"
    end
  end

  describe "login navigation" do
    test "redirects to registration page when the Register button is clicked", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      {:ok, _login_live, login_html} =
        lv
        |> element("main a", "Sign up")
        |> render_click()
        |> follow_redirect(conn, ~p"/users/register")

      assert login_html =~ "Register"
    end
  end

  describe "re-authentication (sudo mode)" do
    setup %{conn: conn} do
      user = user_fixture()
      %{user: user, conn: log_in_user(conn, user)}
    end

    test "shows login page with email filled in", %{conn: conn, user: user} do
      {:ok, _lv, html} = live(conn, ~p"/users/log-in")

      assert html =~ "You need to reauthenticate"
      refute html =~ "Register"
      assert html =~ "Log in with email"

      assert html =~
               ~s(<input type="email" name="user[email]" id="login_form_magic_email" value="#{user.email}")
    end
  end

  describe "passkey-only sign-in" do
    setup do
      user = user_fixture()
      # ensure a webauthn_user_handle exists (registration challenge persists it)
      {_challenge, user, _} = Passkeys.new_registration_challenge(Scope.for_user(user))

      %{user: user, passkey: user_passkey_fixture(user, credential_id: "login-cred")}
    end

    test "button starts a discoverable ceremony and success arms the completion form",
         %{conn: conn, user: user, passkey: passkey} do
      {:ok, view, _html} = live(conn, ~p"/users/log-in")

      view |> element("#passkey-login-button") |> render_click()
      assert_push_event(view, "webauthn:authenticate", %{userVerification: "required"})

      render_hook(
        view,
        "webauthn:asserted",
        webauthn_assertion_payload(passkey.credential_id, user.webauthn_user_handle)
      )

      assert has_element?(view, "#passkey-complete-form input[name='user[token]'][value]")
    end

    test "assertion without user_handle shows the fallback hint", %{conn: conn, passkey: passkey} do
      {:ok, view, _html} = live(conn, ~p"/users/log-in")
      view |> element("#passkey-login-button") |> render_click()

      render_hook(
        view,
        "webauthn:asserted",
        webauthn_assertion_payload(passkey.credential_id, nil)
      )

      assert render(view) =~ "use email and password, then your passkey"
    end

    test "unsupported browsers hide the button", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/log-in")
      render_hook(view, "webauthn:unsupported", %{})
      refute has_element?(view, "#passkey-login-button")
    end

    test "double-submitting the same assertion payload issues no second token",
         %{conn: conn, user: user, passkey: passkey} do
      {:ok, view, _html} = live(conn, ~p"/users/log-in")

      view |> element("#passkey-login-button") |> render_click()
      assert_push_event(view, "webauthn:authenticate", %{userVerification: "required"})

      payload = webauthn_assertion_payload(passkey.credential_id, user.webauthn_user_handle)

      render_hook(view, "webauthn:asserted", payload)
      assert has_element?(view, "#passkey-complete-form input[name='user[token]'][value]")

      token_count = fn ->
        Repo.aggregate(
          from(t in UserToken, where: t.user_id == ^user.id and t.context == "webauthn-login"),
          :count
        )
      end

      assert token_count.() == 1

      render_hook(view, "webauthn:asserted", payload)

      # HEEx HTML-escapes the flash text, so the apostrophe renders as `&#39;`.
      assert render(view) =~ "We couldn&#39;t verify that passkey"
      assert token_count.() == 1
    end

    test "re-auth (sudo) uses an allow-listed challenge for the current user",
         %{conn: conn} do
      user = user_fixture()
      passkey = user_passkey_fixture(user, credential_id: "sudo-cred")

      conn = log_in_user(conn, user, token_authenticated_at: stale_authenticated_at())
      {:ok, view, _html} = live(conn, ~p"/users/log-in")

      view |> element("#passkey-login-button") |> render_click()

      assert_push_event(view, "webauthn:authenticate", %{allowCredentials: [%{id: allowed}]})
      assert allowed == Base.url_encode64(passkey.credential_id, padding: false)

      render_hook(view, "webauthn:asserted", webauthn_assertion_payload(passkey.credential_id))
      assert has_element?(view, "#passkey-complete-form input[name='user[token]'][value]")
    end
  end

  # Well past sudo_mode?/1's 20-minute default, so the login LiveView mounts
  # into the re-authentication (sudo) branch rather than the plain
  # signed-out one.
  defp stale_authenticated_at, do: DateTime.add(DateTime.utc_now(:second), -2, :hour)
end
