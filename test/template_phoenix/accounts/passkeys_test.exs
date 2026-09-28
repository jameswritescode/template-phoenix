defmodule TemplatePhoenix.Accounts.PasskeysTest do
  use TemplatePhoenix.DataCase, async: true

  import Mox
  import TemplatePhoenix.AccountsFixtures

  alias TemplatePhoenix.Accounts
  alias TemplatePhoenix.Accounts.FakeWebAuthn
  alias TemplatePhoenix.Accounts.Passkeys
  alias TemplatePhoenix.Accounts.Scope
  alias TemplatePhoenix.Accounts.UserPasskey
  alias TemplatePhoenix.Accounts.WebAuthn
  alias TemplatePhoenixWeb.Endpoint

  setup :verify_on_exit!

  setup do
    Mox.stub_with(TemplatePhoenix.MockWebAuthn, TemplatePhoenix.Accounts.FakeWebAuthn)
    :ok
  end

  describe "UserPasskey.register_changeset/2" do
    test "requires a name between 1 and 80 characters" do
      changeset = UserPasskey.register_changeset(%UserPasskey{}, %{"name" => ""})
      assert %{name: ["can't be blank"]} = errors_on(changeset)

      changeset =
        UserPasskey.register_changeset(%UserPasskey{}, %{"name" => String.duplicate("a", 81)})

      assert %{name: [_]} = errors_on(changeset)
    end

    test "does not cast programmatic fields" do
      changeset =
        UserPasskey.register_changeset(%UserPasskey{}, %{
          "name" => "ok",
          "sign_count" => 999,
          "credential_id" => "attacker"
        })

      refute Ecto.Changeset.changed?(changeset, :sign_count)
      refute Ecto.Changeset.changed?(changeset, :credential_id)
    end
  end

  describe "credential_id uniqueness" do
    test "is enforced globally, across users" do
      user1 = user_fixture()
      user2 = user_fixture()
      credential_id = :crypto.strong_rand_bytes(16)
      user_passkey_fixture(user1, credential_id: credential_id)

      assert_raise Ecto.ConstraintError, fn ->
        Repo.insert!(%UserPasskey{
          user_id: user2.id,
          credential_id: credential_id,
          public_key: %{-1 => "key"},
          name: "dup"
        })
      end
    end
  end

  describe "WebAuthn.ceremony_opts/0" do
    test "derives origin and rp_id from the endpoint at runtime" do
      opts = WebAuthn.ceremony_opts()
      assert opts[:origin] == Endpoint.url()
      assert opts[:rp_id] == Endpoint.host()
      assert opts[:user_verification] == "required"
    end
  end

  describe "pending second factor tokens" do
    test "round-trips within TTL and is replaced on re-issue" do
      user = user_fixture()
      encoded = Accounts.generate_pending_second_factor_token(user)
      assert Accounts.get_user_by_pending_second_factor_token(encoded).id == user.id

      encoded2 = Accounts.generate_pending_second_factor_token(user)
      assert Accounts.get_user_by_pending_second_factor_token(encoded) == nil
      assert Accounts.get_user_by_pending_second_factor_token(encoded2).id == user.id
    end

    test "expires after 10 minutes" do
      user = user_fixture()
      encoded = Accounts.generate_pending_second_factor_token(user)
      backdate_tokens(user, "passkey-2fa", minutes: -11)
      assert Accounts.get_user_by_pending_second_factor_token(encoded) == nil
    end

    test "reads are non-consuming; delete removes it" do
      user = user_fixture()
      encoded = Accounts.generate_pending_second_factor_token(user)
      assert Accounts.get_user_by_pending_second_factor_token(encoded)
      assert Accounts.get_user_by_pending_second_factor_token(encoded)
      assert :ok = Accounts.delete_pending_second_factor_token(encoded)
      assert Accounts.get_user_by_pending_second_factor_token(encoded) == nil
    end

    test "garbage input returns nil, never raises" do
      assert Accounts.get_user_by_pending_second_factor_token("!!! not base64 !!!") == nil
      assert :ok = Accounts.delete_pending_second_factor_token("!!! not base64 !!!")
    end
  end

  describe "webauthn login tokens" do
    test "consume is single-use and returns the issuance tag" do
      user = user_fixture()
      encoded = issue_webauthn_login_token(user, "discoverable")
      assert {:ok, consumed_user, "discoverable"} = Accounts.consume_webauthn_login_token(encoded)
      assert consumed_user.id == user.id
      assert Accounts.consume_webauthn_login_token(encoded) == :error
    end

    test "expires after 2 minutes and rejects garbage" do
      user = user_fixture()
      encoded = issue_webauthn_login_token(user, "second_factor")
      backdate_tokens(user, "webauthn-login", minutes: -3)
      assert Accounts.consume_webauthn_login_token(encoded) == :error
      assert Accounts.consume_webauthn_login_token("garbage") == :error
    end
  end

  describe "new_registration_challenge/1" do
    test "generates and persists a stable webauthn_user_handle" do
      user = user_fixture()
      assert user.webauthn_user_handle == nil

      {_challenge, user_with_handle, []} =
        Passkeys.new_registration_challenge(Scope.for_user(user))

      assert byte_size(user_with_handle.webauthn_user_handle) == 32

      {_challenge, again, []} =
        Passkeys.new_registration_challenge(Scope.for_user(user_with_handle))

      assert again.webauthn_user_handle == user_with_handle.webauthn_user_handle
    end

    test "excludes already-registered credential ids" do
      user = user_fixture()
      passkey = user_passkey_fixture(user)
      {_challenge, _user, exclude_ids} = Passkeys.new_registration_challenge(Scope.for_user(user))
      assert exclude_ids == [passkey.credential_id]
    end
  end

  describe "register_passkey/4" do
    setup do
      user = user_fixture()
      {challenge, user, _exclude} = Passkeys.new_registration_challenge(Scope.for_user(user))
      %{user: user, scope: Scope.for_user(user), challenge: challenge}
    end

    test "persists the verified credential", %{scope: scope, challenge: challenge, user: user} do
      payload = webauthn_registration_payload("credential-abc")

      assert {:ok, passkey} = Passkeys.register_passkey(scope, challenge, payload, "My laptop")
      assert passkey.user_id == user.id
      assert passkey.credential_id == "credential-abc"
      assert passkey.name == "My laptop"
      assert Passkeys.passkeys_enabled?(user)
    end

    test "duplicate credential id is rejected", %{scope: scope, challenge: challenge} do
      payload = webauthn_registration_payload("credential-dup")
      assert {:ok, _} = Passkeys.register_passkey(scope, challenge, payload, "One")

      assert {:error, :already_registered} =
               Passkeys.register_passkey(scope, challenge, payload, "Two")
    end

    test "undecodable base64url payload fails cleanly", %{scope: scope, challenge: challenge} do
      payload = %{"attestation_object" => "!!!", "client_data_json" => "!!!"}

      assert {:error, :invalid_payload} =
               Passkeys.register_passkey(scope, challenge, payload, "X")
    end

    test "verification failure surfaces as verification_failed", %{
      scope: scope,
      challenge: challenge
    } do
      Mox.expect(TemplatePhoenix.MockWebAuthn, :register, fn _, _, _ ->
        {:error, %RuntimeError{message: "bad attestation"}}
      end)

      payload = webauthn_registration_payload("credential-bad")

      assert {:error, :verification_failed} =
               Passkeys.register_passkey(scope, challenge, payload, "X")
    end

    test "missing user verification flag is rejected", %{scope: scope, challenge: challenge} do
      Mox.expect(TemplatePhoenix.MockWebAuthn, :register, fn attestation_object, _, _ ->
        auth_data =
          FakeWebAuthn.auth_data(credential_id: attestation_object, flag_user_verified: false)

        {:ok, {auth_data, :none}}
      end)

      ref =
        :telemetry_test.attach_event_handlers(self(), [
          [:template_phoenix, :accounts, :passkey, :verification_failed]
        ])

      payload = webauthn_registration_payload("credential-nouv")

      assert {:error, :verification_failed} =
               Passkeys.register_passkey(scope, challenge, payload, "X")

      assert_received {[:template_phoenix, :accounts, :passkey, :verification_failed], ^ref,
                       %{count: 1}, %{reason: :user_verification_missing}}
    end
  end

  describe "discoverable assertion" do
    setup do
      user = user_fixture()
      {_challenge, user, _} = Passkeys.new_registration_challenge(Scope.for_user(user))
      passkey = user_passkey_fixture(user, credential_id: "cred-disco")
      challenge = Passkeys.new_discoverable_authentication_challenge()
      %{user: user, passkey: passkey, challenge: challenge}
    end

    test "verifies, bumps last_used_at, and issues a consumable login token",
         %{user: user, passkey: passkey, challenge: challenge} do
      payload = webauthn_assertion_payload(passkey.credential_id, user.webauthn_user_handle)

      assert {:ok, verified_user, login_token} =
               Passkeys.verify_assertion_and_issue_login_token(challenge, payload)

      assert verified_user.id == user.id
      assert {:ok, _user, "discoverable"} = Accounts.consume_webauthn_login_token(login_token)
      assert Repo.get!(UserPasskey, passkey.id).last_used_at
    end

    test "unknown credential id fails generically", %{challenge: challenge, user: user} do
      payload = webauthn_assertion_payload("no-such-cred", user.webauthn_user_handle)

      assert {:error, :verification_failed} =
               Passkeys.verify_assertion_and_issue_login_token(challenge, payload)
    end

    test "user_handle mismatch is rejected even when Wax would pass",
         %{passkey: passkey, challenge: challenge} do
      payload = webauthn_assertion_payload(passkey.credential_id, :crypto.strong_rand_bytes(32))

      assert {:error, :verification_failed} =
               Passkeys.verify_assertion_and_issue_login_token(challenge, payload)
    end

    test "missing user_handle is rejected", %{passkey: passkey, challenge: challenge} do
      payload = webauthn_assertion_payload(passkey.credential_id, nil)

      assert {:error, :invalid_payload} =
               Passkeys.verify_assertion_and_issue_login_token(challenge, payload)
    end

    test "malformed base64url in any field fails cleanly", %{challenge: challenge} do
      payload = %{
        "credential_id" => "!!!",
        "authenticator_data" => "!!!",
        "signature" => "!!!",
        "client_data_json" => "!!!",
        "user_handle" => "!!!"
      }

      assert {:error, :invalid_payload} =
               Passkeys.verify_assertion_and_issue_login_token(challenge, payload)
    end
  end

  describe "second-factor assertion" do
    setup do
      user = user_fixture()
      passkey = user_passkey_fixture(user, credential_id: "cred-2fa")
      {challenge, allow_ids} = Passkeys.new_authentication_challenge_for_user(user)
      %{user: user, passkey: passkey, challenge: challenge, allow_ids: allow_ids}
    end

    test "allow list contains exactly the user's credentials", %{
      passkey: passkey,
      allow_ids: allow_ids
    } do
      assert allow_ids == [passkey.credential_id]
    end

    test "verifies and issues a second_factor-tagged token",
         %{user: user, passkey: passkey, challenge: challenge} do
      payload = webauthn_assertion_payload(passkey.credential_id)

      assert {:ok, _user, login_token} =
               Passkeys.verify_second_factor_and_issue_login_token(user, challenge, payload)

      assert {:ok, _user, "second_factor"} = Accounts.consume_webauthn_login_token(login_token)
    end

    test "another user's valid passkey cannot complete this user's second factor",
         %{user: user, challenge: challenge} do
      other = user_fixture()
      other_passkey = user_passkey_fixture(other, credential_id: "cred-other")
      payload = webauthn_assertion_payload(other_passkey.credential_id)

      assert {:error, :verification_failed} =
               Passkeys.verify_second_factor_and_issue_login_token(user, challenge, payload)
    end
  end

  describe "sign-count policy" do
    setup do
      user = user_fixture()
      %{user: user}
    end

    test "0 -> 0 is accepted (counter unsupported)", %{user: user} do
      passkey = user_passkey_fixture(user, sign_count: 0)
      {challenge, _} = Passkeys.new_authentication_challenge_for_user(user)
      payload = webauthn_assertion_payload(passkey.credential_id)

      assert {:ok, _, _} =
               Passkeys.verify_second_factor_and_issue_login_token(user, challenge, payload)
    end

    test "increment is accepted and persisted", %{user: user} do
      passkey = user_passkey_fixture(user, sign_count: 5)
      {challenge, _} = Passkeys.new_authentication_challenge_for_user(user)

      Mox.expect(TemplatePhoenix.MockWebAuthn, :authenticate, fn cred_id, _, _, _, _, _ ->
        {:ok, FakeWebAuthn.auth_data(credential_id: cred_id, sign_count: 6)}
      end)

      payload = webauthn_assertion_payload(passkey.credential_id)

      assert {:ok, _, _} =
               Passkeys.verify_second_factor_and_issue_login_token(user, challenge, payload)

      assert Repo.get!(UserPasskey, passkey.id).sign_count == 6
    end

    test "regression is rejected and emits telemetry", %{user: user} do
      passkey = user_passkey_fixture(user, sign_count: 10)
      {challenge, _} = Passkeys.new_authentication_challenge_for_user(user)

      ref =
        :telemetry_test.attach_event_handlers(self(), [
          [:template_phoenix, :accounts, :passkey, :sign_count_regression]
        ])

      Mox.expect(TemplatePhoenix.MockWebAuthn, :authenticate, fn cred_id, _, _, _, _, _ ->
        {:ok, FakeWebAuthn.auth_data(credential_id: cred_id, sign_count: 3)}
      end)

      payload = webauthn_assertion_payload(passkey.credential_id)

      assert {:error, :verification_failed} =
               Passkeys.verify_second_factor_and_issue_login_token(user, challenge, payload)

      assert_received {[:template_phoenix, :accounts, :passkey, :sign_count_regression], ^ref, _,
                       _}

      assert Repo.get!(UserPasskey, passkey.id).sign_count == 10
    end

    test "optimistic guard: concurrent bump of the row rejects the assertion", %{user: user} do
      passkey = user_passkey_fixture(user, sign_count: 5)
      {challenge, _} = Passkeys.new_authentication_challenge_for_user(user)

      Mox.expect(TemplatePhoenix.MockWebAuthn, :authenticate, fn cred_id, _, _, _, _, _ ->
        Repo.update_all(
          from(p in UserPasskey, where: p.id == ^passkey.id),
          set: [sign_count: 7]
        )

        {:ok, FakeWebAuthn.auth_data(credential_id: cred_id, sign_count: 6)}
      end)

      payload = webauthn_assertion_payload(passkey.credential_id)

      assert {:error, :verification_failed} =
               Passkeys.verify_second_factor_and_issue_login_token(user, challenge, payload)
    end
  end
end
