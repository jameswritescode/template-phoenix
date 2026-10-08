defmodule TemplatePhoenixWeb.UserSessionControllerTest do
  use TemplatePhoenixWeb.ConnCase, async: true

  import Ecto.Query
  import TemplatePhoenix.AccountsFixtures
  alias TemplatePhoenix.Accounts
  alias TemplatePhoenixWeb.UserAuth

  setup do
    %{unconfirmed_user: unconfirmed_user_fixture(), user: user_fixture()}
  end

  describe "POST /users/log-in - email and password" do
    test "logs the user in", %{conn: conn, user: user} do
      user = set_password(user)

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/"

      # Now do a logged in request and assert on the user menu
      conn = get(conn, ~p"/users/settings")
      response = html_response(conn, 200)
      assert response =~ user.email
      assert response =~ ~p"/users/settings"
      assert response =~ ~p"/users/log-out"
    end

    test "logs the user in with remember me", %{conn: conn, user: user} do
      user = set_password(user)

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password(),
            "remember_me" => "true"
          }
        })

      assert conn.resp_cookies["_template_phoenix_web_user_remember_me"]
      assert redirected_to(conn) == ~p"/"
    end

    test "logs the user in with return to", %{conn: conn, user: user} do
      user = set_password(user)

      conn =
        conn
        |> init_test_session(user_return_to: "/foo/bar")
        |> post(~p"/users/log-in", %{
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password()
          }
        })

      assert redirected_to(conn) == "/foo/bar"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Welcome back!"
    end

    test "redirects to login page with invalid credentials", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/users/log-in?mode=password", %{
          "user" => %{"email" => user.email, "password" => "invalid_password"}
        })

      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password"
      assert redirected_to(conn) == ~p"/users/log-in"
    end
  end

  describe "POST /users/log-in - magic link" do
    test "logs the user in", %{conn: conn, user: user} do
      {token, _hashed_token} = generate_user_magic_link_token(user)

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"token" => token}
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/"

      # Now do a logged in request and assert on the user menu
      conn = get(conn, ~p"/users/settings")
      response = html_response(conn, 200)
      assert response =~ user.email
      assert response =~ ~p"/users/settings"
      assert response =~ ~p"/users/log-out"
    end

    test "confirms unconfirmed user", %{conn: conn, unconfirmed_user: user} do
      {token, _hashed_token} = generate_user_magic_link_token(user)
      refute user.confirmed_at

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"token" => token},
          "_action" => "confirmed"
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "User confirmed successfully."

      assert Accounts.get_user!(user.id).confirmed_at

      # Now do a logged in request and assert on the user menu
      conn = get(conn, ~p"/users/settings")
      response = html_response(conn, 200)
      assert response =~ user.email
      assert response =~ ~p"/users/settings"
      assert response =~ ~p"/users/log-out"
    end

    test "redirects to login page when magic link is invalid", %{conn: conn} do
      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"token" => "invalid"}
        })

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "The link is invalid or it has expired."

      assert redirected_to(conn) == ~p"/users/log-in"
    end
  end

  describe "POST /users/log-in/passkey" do
    setup do
      user = user_fixture()
      %{user: user, passkey: user_passkey_fixture(user)}
    end

    test "valid completion token mints a session and honors return_to", %{conn: conn, user: user} do
      token = issue_webauthn_login_token(user, "discoverable")

      conn =
        conn
        |> init_test_session(user_return_to: "/users/settings")
        |> post(~p"/users/log-in/passkey", %{
          "user" => %{"token" => token, "remember_me" => "true"}
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == "/users/settings"
      assert conn.resp_cookies["_template_phoenix_web_user_remember_me"]
    end

    test "a replayed token mints nothing", %{conn: conn, user: user} do
      token = issue_webauthn_login_token(user, "discoverable")
      first = post(conn, ~p"/users/log-in/passkey", %{"user" => %{"token" => token}})
      assert get_session(first, :user_token)

      replay = post(build_conn(), ~p"/users/log-in/passkey", %{"user" => %{"token" => token}})
      refute get_session(replay, :user_token)
      assert redirected_to(replay) == ~p"/users/log-in"
    end

    test "expired and garbage tokens mint nothing", %{user: user} do
      token = issue_webauthn_login_token(user, "discoverable")
      backdate_tokens(user, "webauthn-login", minutes: -3)

      for bad <- [token, "garbage"] do
        conn = post(build_conn(), ~p"/users/log-in/passkey", %{"user" => %{"token" => bad}})
        refute get_session(conn, :user_token)
        assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "couldn't complete"
      end
    end

    test "a discoverable login ignores a leftover gate remember_me and uses the posted value",
         %{user: user} do
      token = issue_webauthn_login_token(user, "discoverable")

      conn =
        build_conn()
        |> init_test_session(passkey_2fa_remember_me: true)
        |> post(~p"/users/log-in/passkey", %{
          "user" => %{"token" => token, "remember_me" => "false"}
        })

      assert get_session(conn, :user_token)
      refute conn.resp_cookies["_template_phoenix_web_user_remember_me"]
    end

    test "session is renewed at completion (fixation defense)", %{user: user} do
      token = issue_webauthn_login_token(user, "discoverable")

      conn =
        build_conn()
        |> init_test_session(to_be_removed: "attacker-set")
        |> post(~p"/users/log-in/passkey", %{"user" => %{"token" => token}})

      refute get_session(conn, :to_be_removed)
      assert get_session(conn, :user_token)
    end
  end

  describe "second-factor gate" do
    setup do
      user = user_fixture() |> set_password()
      %{user: user, passkey: user_passkey_fixture(user)}
    end

    test "password login with a passkey on the account mints NO session", %{
      conn: conn,
      user: user
    } do
      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password(),
            "remember_me" => "true"
          }
        })

      refute get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/users/log-in/two-factor"

      pending = get_session(conn, :passkey_2fa_token)
      assert Accounts.get_user_by_pending_second_factor_token(pending).id == user.id
      assert get_session(conn, :passkey_2fa_remember_me) == true
    end

    test "magic-link login detours the same way AND consumes the link", %{conn: conn, user: user} do
      token =
        extract_user_token(fn url -> Accounts.deliver_login_instructions(user, url) end)

      conn = post(conn, ~p"/users/log-in", %{"user" => %{"token" => token}})
      refute get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/users/log-in/two-factor"

      retry = post(build_conn(), ~p"/users/log-in", %{"user" => %{"token" => token}})
      refute get_session(retry, :user_token)
      refute redirected_to(retry) == ~p"/users/log-in/two-factor"
      assert redirected_to(retry) == ~p"/users/log-in"
    end

    test "the detour carries no info flash from the magic-link branch", %{conn: conn, user: user} do
      token =
        extract_user_token(fn url -> Accounts.deliver_login_instructions(user, url) end)

      conn = post(conn, ~p"/users/log-in", %{"user" => %{"token" => token}})

      assert redirected_to(conn) == ~p"/users/log-in/two-factor"
      refute Phoenix.Flash.get(conn.assigns.flash, :info)
    end

    test "the detour renews the session and preserves return_to", %{conn: conn, user: user} do
      conn =
        conn
        |> init_test_session(user_return_to: "/users/settings", fixate: "attacker")
        |> post(~p"/users/log-in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      refute get_session(conn, :fixate)
      assert get_session(conn, :user_return_to) == "/users/settings"
    end

    test "completing 2FA yields a session honoring return_to and remember_me",
         %{conn: conn, user: user} do
      login =
        conn
        |> init_test_session(user_return_to: "/users/settings")
        |> post(~p"/users/log-in", %{
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password(),
            "remember_me" => "true"
          }
        })

      token = issue_webauthn_login_token(user, "second_factor")

      completed =
        recycle(login)
        |> post(~p"/users/log-in/passkey", %{"user" => %{"token" => token}})

      assert get_session(completed, :user_token)
      refute get_session(completed, :passkey_2fa_token)
      refute get_session(completed, :passkey_2fa_remember_me)
      assert pending_2fa_token_count(user) == 0
      assert redirected_to(completed) == "/users/settings"
      assert completed.resp_cookies["_template_phoenix_web_user_remember_me"]
    end

    test "the remember_me captured at the gate wins over the completion form's value",
         %{conn: conn, user: user} do
      login =
        post(conn, ~p"/users/log-in", %{
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password(),
            "remember_me" => "true"
          }
        })

      token = issue_webauthn_login_token(user, "second_factor")

      completed =
        recycle(login)
        |> post(~p"/users/log-in/passkey", %{
          "user" => %{"token" => token, "remember_me" => "false"}
        })

      assert get_session(completed, :user_token)
      assert completed.resp_cookies["_template_phoenix_web_user_remember_me"]
    end

    test "accounts WITHOUT passkeys are completely unaffected", %{conn: conn} do
      plain = user_fixture() |> set_password()

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"email" => plain.email, "password" => valid_user_password()}
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/"
    end
  end

  describe "sudo and the carve-out for passkey accounts" do
    setup %{conn: conn} do
      user = user_fixture() |> set_password()
      passkey = user_passkey_fixture(user)
      %{conn: conn, user: user, passkey: passkey}
    end

    test "password re-auth with STALE sudo does not refresh authenticated_at",
         %{user: user} do
      conn = log_in_user(build_conn(), user, token_authenticated_at: stale_authenticated_at())

      reauth =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      assert redirected_to(reauth) == ~p"/users/log-in/two-factor"

      # the old session token is untouched and still stale:
      {reloaded, _token_inserted_at} =
        Accounts.get_user_by_session_token(get_session(conn, :user_token))

      assert reloaded.id == user.id
      refute Accounts.sudo_mode?(reloaded)
    end

    test "completing the passkey step refreshes sudo (fresh authenticated_at)", %{user: user} do
      stale = log_in_user(build_conn(), user, token_authenticated_at: stale_authenticated_at())
      token = issue_webauthn_login_token(user, "second_factor")

      refreshed =
        post(recycle(stale), ~p"/users/log-in/passkey", %{"user" => %{"token" => token}})

      {refreshed_user, _token_inserted_at} =
        Accounts.get_user_by_session_token(get_session(refreshed, :user_token))

      assert Accounts.sudo_mode?(refreshed_user)
    end

    test "carve-out: sudo-FRESH same-user re-mint skips the ceremony", %{user: user} do
      # fresh authenticated_at (defaults to now)
      conn = log_in_user(build_conn(), user)

      remint =
        conn
        |> UserAuth.fetch_current_scope_for_user([])
        |> UserAuth.log_in_user(user)

      assert get_session(remint, :user_token)
      refute get_session(remint, :passkey_2fa_token)
    end

    test "carve-out: a fresh re-mint keeps the original ceremony time (never extends sudo)",
         %{user: user} do
      ceremony_at = DateTime.add(DateTime.utc_now(:second), -5, :minute)
      conn = log_in_user(build_conn(), user, token_authenticated_at: ceremony_at)

      remint =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      refute get_session(remint, :passkey_2fa_token)

      {reminted, _token_inserted_at} =
        Accounts.get_user_by_session_token(get_session(remint, :user_token))

      assert reminted.authenticated_at == ceremony_at
    end

    test "carve-out: does NOT apply at ~15 minutes old (outside the sudo gate's 10-minute window)",
         %{user: user} do
      conn = log_in_user(build_conn(), user, token_authenticated_at: outside_gate_at())

      reauth =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      assert redirected_to(reauth) == ~p"/users/log-in/two-factor"
      refute get_session(reauth, :user_token)
      assert get_session(reauth, :passkey_2fa_token)
    end

    test "password re-auth at ~15 minutes does not satisfy require_sudo_mode afterward",
         %{user: user} do
      conn = log_in_user(build_conn(), user, token_authenticated_at: outside_gate_at())

      reauth =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      settings = get(recycle(reauth), ~p"/users/settings")
      assert redirected_to(settings) == ~p"/users/log-in"
    end

    test "carve-out does NOT apply to a different user", %{user: user} do
      other = user_fixture()
      _other_passkey = user_passkey_fixture(other)
      # fresh session as `user`
      conn = log_in_user(build_conn(), user)

      remint =
        conn
        |> UserAuth.fetch_current_scope_for_user([])
        |> UserAuth.log_in_user(other)

      refute get_session(remint, :user_token)
    end
  end

  # Well past both the on_mount(:require_sudo_mode) gate's 10-minute window
  # and sudo_mode?/1's 20-minute default — unambiguously stale either way.
  defp stale_authenticated_at, do: DateTime.add(DateTime.utc_now(:second), -2, :hour)

  # Inside sudo_mode?/1's 20-minute default but outside the
  # on_mount(:require_sudo_mode) gate's 10-minute window — the band where a
  # looser carve-out would refresh sudo without a ceremony.
  defp outside_gate_at, do: DateTime.add(DateTime.utc_now(:second), -15, :minute)

  defp pending_2fa_token_count(user) do
    TemplatePhoenix.Repo.aggregate(
      from(t in Accounts.UserToken, where: t.user_id == ^user.id and t.context == "passkey-2fa"),
      :count
    )
  end

  describe "login telemetry (single emission point)" do
    test "login outcomes emit telemetry", %{conn: conn} do
      user = user_fixture() |> set_password()

      ref =
        :telemetry_test.attach_event_handlers(self(), [[:template_phoenix, :accounts, :login]])

      post(conn, ~p"/users/log-in", %{
        "user" => %{"email" => user.email, "password" => valid_user_password()}
      })

      assert_received {[:template_phoenix, :accounts, :login], ^ref, %{count: 1},
                       %{result: :success, method: "password"}}
    end

    test "an attacker-supplied _login_method param cannot poison the tag", %{conn: conn} do
      user = user_fixture() |> set_password()

      ref =
        :telemetry_test.attach_event_handlers(self(), [[:template_phoenix, :accounts, :login]])

      post(conn, ~p"/users/log-in", %{
        "user" => %{
          "email" => user.email,
          "password" => valid_user_password(),
          "_login_method" => "passkey_discoverable"
        }
      })

      assert_received {[:template_phoenix, :accounts, :login], ^ref, %{count: 1},
                       %{result: :success, method: "password"}}
    end

    test "magic-link login is tagged magic_link", %{conn: conn} do
      user = user_fixture()
      {token, _hashed_token} = generate_user_magic_link_token(user)

      ref =
        :telemetry_test.attach_event_handlers(self(), [[:template_phoenix, :accounts, :login]])

      post(conn, ~p"/users/log-in", %{"user" => %{"token" => token}})

      assert_received {[:template_phoenix, :accounts, :login], ^ref, %{count: 1},
                       %{result: :success, method: "magic_link"}}
    end

    test "discoverable passkey completion is tagged passkey_discoverable", %{conn: conn} do
      user = user_fixture()
      _passkey = user_passkey_fixture(user)
      token = issue_webauthn_login_token(user, "discoverable")

      ref =
        :telemetry_test.attach_event_handlers(self(), [[:template_phoenix, :accounts, :login]])

      post(conn, ~p"/users/log-in/passkey", %{"user" => %{"token" => token}})

      assert_received {[:template_phoenix, :accounts, :login], ^ref, %{count: 1},
                       %{result: :success, method: "passkey_discoverable"}}
    end

    test "second-factor passkey completion is tagged passkey_second_factor", %{conn: conn} do
      user = user_fixture() |> set_password()
      _passkey = user_passkey_fixture(user)

      login =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      token = issue_webauthn_login_token(user, "second_factor")

      ref =
        :telemetry_test.attach_event_handlers(self(), [[:template_phoenix, :accounts, :login]])

      recycle(login) |> post(~p"/users/log-in/passkey", %{"user" => %{"token" => token}})

      assert_received {[:template_phoenix, :accounts, :login], ^ref, %{count: 1},
                       %{result: :success, method: "passkey_second_factor"}}
    end

    test "invalid password credentials emit a failure event", %{conn: conn} do
      user = user_fixture() |> set_password()

      ref =
        :telemetry_test.attach_event_handlers(self(), [[:template_phoenix, :accounts, :login]])

      post(conn, ~p"/users/log-in", %{
        "user" => %{"email" => user.email, "password" => "invalid_password"}
      })

      assert_received {[:template_phoenix, :accounts, :login], ^ref, %{count: 1},
                       %{result: :failure, method: "password"}}
    end

    test "a failed passkey completion emits a failure event", %{conn: conn} do
      ref =
        :telemetry_test.attach_event_handlers(self(), [[:template_phoenix, :accounts, :login]])

      post(conn, ~p"/users/log-in/passkey", %{"user" => %{"token" => "garbage"}})

      assert_received {[:template_phoenix, :accounts, :login], ^ref, %{count: 1},
                       %{result: :failure, method: "passkey"}}
    end

    test "an invalid magic link emits a failure event", %{conn: conn} do
      ref =
        :telemetry_test.attach_event_handlers(self(), [[:template_phoenix, :accounts, :login]])

      post(conn, ~p"/users/log-in", %{"user" => %{"token" => "invalid"}})

      assert_received {[:template_phoenix, :accounts, :login], ^ref, %{count: 1},
                       %{result: :failure, method: "magic_link"}}
    end
  end

  describe "DELETE /users/log-out" do
    test "logs the user out", %{conn: conn, user: user} do
      conn = conn |> log_in_user(user) |> delete(~p"/users/log-out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Logged out successfully"
    end

    test "succeeds even if the user is not logged in", %{conn: conn} do
      conn = delete(conn, ~p"/users/log-out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Logged out successfully"
    end
  end
end
