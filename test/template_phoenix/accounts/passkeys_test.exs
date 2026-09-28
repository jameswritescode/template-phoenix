defmodule TemplatePhoenix.Accounts.PasskeysTest do
  use TemplatePhoenix.DataCase, async: true

  alias TemplatePhoenix.Accounts
  alias TemplatePhoenix.Accounts.UserPasskey
  alias TemplatePhoenix.Accounts.WebAuthn
  alias TemplatePhoenixWeb.Endpoint

  import TemplatePhoenix.AccountsFixtures

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
end
