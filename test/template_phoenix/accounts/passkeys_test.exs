defmodule TemplatePhoenix.Accounts.PasskeysTest do
  use TemplatePhoenix.DataCase, async: true

  alias TemplatePhoenix.Accounts.UserPasskey

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
end
