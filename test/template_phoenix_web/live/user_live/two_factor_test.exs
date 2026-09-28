defmodule TemplatePhoenixWeb.UserLive.TwoFactorTest do
  use TemplatePhoenixWeb.ConnCase, async: true

  import Ecto.Query
  import Mox
  import Phoenix.LiveViewTest
  import TemplatePhoenix.AccountsFixtures

  alias TemplatePhoenix.Accounts
  alias TemplatePhoenix.Repo

  setup :verify_on_exit!

  setup do
    Mox.stub_with(TemplatePhoenix.MockWebAuthn, TemplatePhoenix.Accounts.FakeWebAuthn)
    user = user_fixture()
    passkey = user_passkey_fixture(user, credential_id: "tf-cred")
    %{user: user, passkey: passkey}
  end

  defp pending_conn(conn, user, remember_me \\ false) do
    init_test_session(conn, %{
      passkey_2fa_token: Accounts.generate_pending_second_factor_token(user),
      passkey_2fa_remember_me: remember_me
    })
  end

  defp token_count(user, context) do
    Repo.aggregate(
      from(t in Accounts.UserToken, where: t.user_id == ^user.id and t.context == ^context),
      :count
    )
  end

  test "mount without pending state redirects to log-in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} =
             live(conn, ~p"/users/log-in/two-factor")
  end

  test "mount with an expired pending token redirects to log-in", %{conn: conn, user: user} do
    conn = pending_conn(conn, user)
    backdate_tokens(user, "passkey-2fa", minutes: -11)

    assert {:error, {:redirect, %{to: "/users/log-in"}}} =
             live(conn, ~p"/users/log-in/two-factor")
  end

  test "connected mount pushes an allow-listed challenge",
       %{conn: conn, user: user, passkey: passkey} do
    {:ok, view, _html} = live(pending_conn(conn, user), ~p"/users/log-in/two-factor")

    assert_push_event(view, "webauthn:authenticate", %{
      allowCredentials: [%{id: allowed_id}],
      userVerification: "required"
    })

    assert allowed_id == Base.url_encode64(passkey.credential_id, padding: false)
  end

  test "a verified assertion arms the completion form",
       %{conn: conn, user: user, passkey: passkey} do
    {:ok, view, _html} = live(pending_conn(conn, user, true), ~p"/users/log-in/two-factor")
    render_hook(view, "webauthn:asserted", webauthn_assertion_payload(passkey.credential_id))
    assert has_element?(view, "#two-factor-complete-form input[name='user[token]'][value]")
  end

  test "re-sending an asserted payload after success is refused and issues no second token",
       %{conn: conn, user: user, passkey: passkey} do
    {:ok, view, _html} = live(pending_conn(conn, user), ~p"/users/log-in/two-factor")
    payload = webauthn_assertion_payload(passkey.credential_id)

    render_hook(view, "webauthn:asserted", payload)
    assert has_element?(view, "#two-factor-complete-form input[name='user[token]'][value]")

    render_hook(view, "webauthn:asserted", payload)
    assert has_element?(view, "#flash-error", "couldn't verify")
    assert token_count(user, "webauthn-login") == 1
  end

  test "a malformed asserted payload is answered generically and the view survives",
       %{conn: conn, user: user} do
    {:ok, view, _html} = live(pending_conn(conn, user), ~p"/users/log-in/two-factor")
    render_hook(view, "webauthn:asserted", %{"nonsense" => true})
    assert has_element?(view, "#flash-error", "couldn't verify")
    assert has_element?(view, "#two-factor-retry")
  end

  test "five failed attempts delete the pending token and bail to log-in",
       %{conn: conn, user: user} do
    conn = pending_conn(conn, user)
    {:ok, view, _html} = live(conn, ~p"/users/log-in/two-factor")

    for _attempt <- 1..4 do
      render_click(view, "retry")
      render_hook(view, "webauthn:asserted", webauthn_assertion_payload("wrong-cred"))
    end

    assert has_element?(view, "#two-factor-retry")

    render_click(view, "retry")

    assert {:error, {:redirect, %{to: "/users/log-in"}}} =
             render_hook(view, "webauthn:asserted", webauthn_assertion_payload("wrong-cred"))

    assert token_count(user, "passkey-2fa") == 0

    assert {:error, {:redirect, %{to: "/users/log-in"}}} =
             live(conn, ~p"/users/log-in/two-factor")
  end

  test "webauthn:error shows copy and a retry control", %{conn: conn, user: user} do
    {:ok, view, _html} = live(pending_conn(conn, user), ~p"/users/log-in/two-factor")
    render_hook(view, "webauthn:error", %{"name" => "NotAllowedError", "message" => ""})
    assert has_element?(view, "#flash-error", "Cancelled or timed out")
    assert has_element?(view, "#two-factor-retry")
  end

  test "webauthn:error without a name is answered generically", %{conn: conn, user: user} do
    {:ok, view, _html} = live(pending_conn(conn, user), ~p"/users/log-in/two-factor")
    render_hook(view, "webauthn:error", %{"unexpected" => 1})
    assert has_element?(view, "#flash-error", "Something went wrong")
    assert has_element?(view, "#two-factor-retry")
  end
end
