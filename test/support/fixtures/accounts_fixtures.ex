defmodule TemplatePhoenix.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `TemplatePhoenix.Accounts` context.
  """

  import Ecto.Query

  alias TemplatePhoenix.Accounts
  alias TemplatePhoenix.Accounts.Scope
  alias TemplatePhoenix.Accounts.User
  alias TemplatePhoenix.Accounts.UserPasskey

  @spec unique_user_email() :: String.t()
  def unique_user_email, do: "user#{System.unique_integer()}@example.com"

  @spec valid_user_password() :: String.t()
  def valid_user_password, do: "hello world!"

  @spec valid_user_attributes(map() | keyword()) :: map()
  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_user_email()
    })
  end

  @spec unconfirmed_user_fixture(map() | keyword()) :: User.t()
  def unconfirmed_user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> valid_user_attributes()
      |> Accounts.register_user()

    user
  end

  @spec user_fixture(map() | keyword()) :: User.t()
  def user_fixture(attrs \\ %{}) do
    user = unconfirmed_user_fixture(attrs)

    token =
      extract_user_token(fn url ->
        Accounts.deliver_login_instructions(user, url)
      end)

    {:ok, {user, _expired_tokens}} =
      Accounts.login_user_by_magic_link(token)

    user
  end

  @spec user_scope_fixture() :: Scope.t()
  def user_scope_fixture do
    user = user_fixture()
    user_scope_fixture(user)
  end

  @spec user_scope_fixture(User.t()) :: Scope.t()
  def user_scope_fixture(user) do
    Scope.for_user(user)
  end

  @spec set_password(User.t()) :: User.t()
  def set_password(user) do
    {:ok, {user, _expired_tokens}} =
      Accounts.update_user_password(user, %{password: valid_user_password()})

    user
  end

  @spec extract_user_token(((String.t() -> String.t()) -> {:ok, Swoosh.Email.t()})) ::
          String.t()
  def extract_user_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end

  @spec override_token_authenticated_at(binary(), DateTime.t()) :: {non_neg_integer(), nil}
  def override_token_authenticated_at(token, authenticated_at) when is_binary(token) do
    TemplatePhoenix.Repo.update_all(
      from(t in Accounts.UserToken,
        where: t.token == ^token
      ),
      set: [authenticated_at: authenticated_at]
    )
  end

  @spec generate_user_magic_link_token(User.t()) :: {String.t(), binary()}
  def generate_user_magic_link_token(user) do
    {encoded_token, user_token} = Accounts.UserToken.build_email_token(user, "login")
    TemplatePhoenix.Repo.insert!(user_token)
    {encoded_token, user_token.token}
  end

  @spec offset_user_token(binary(), integer(), :day | :hour | :minute | System.time_unit()) ::
          {non_neg_integer(), nil}
  def offset_user_token(token, amount_to_add, unit) do
    dt = DateTime.add(DateTime.utc_now(:second), amount_to_add, unit)

    TemplatePhoenix.Repo.update_all(
      from(ut in Accounts.UserToken, where: ut.token == ^token),
      set: [inserted_at: dt, authenticated_at: dt]
    )
  end

  @spec backdate_tokens(User.t(), String.t(), keyword()) :: :ok
  def backdate_tokens(user, context, minutes: minutes) do
    shifted = DateTime.add(DateTime.utc_now(:second), minutes * 60, :second)

    TemplatePhoenix.Repo.update_all(
      from(t in Accounts.UserToken,
        where: t.user_id == ^user.id and t.context == ^context
      ),
      set: [inserted_at: shifted]
    )

    :ok
  end

  @spec issue_webauthn_login_token(User.t(), String.t()) :: String.t()
  def issue_webauthn_login_token(user, tag) do
    {encoded, token} =
      Accounts.UserToken.build_passkey_token(user, "webauthn-login", tag)

    TemplatePhoenix.Repo.insert!(token)
    encoded
  end

  @spec user_passkey_fixture(User.t(), keyword()) :: UserPasskey.t()
  def user_passkey_fixture(user, opts \\ []) do
    %UserPasskey{
      user_id: user.id,
      credential_id: Keyword.get(opts, :credential_id, :crypto.strong_rand_bytes(16)),
      public_key:
        Keyword.get(opts, :public_key, %{1 => 1, 3 => -8, -1 => :crypto.strong_rand_bytes(32)}),
      sign_count: Keyword.get(opts, :sign_count, 0),
      aaguid: <<0::128>>
    }
    |> UserPasskey.register_changeset(%{
      "name" => Keyword.get(opts, :name, "Test passkey")
    })
    |> TemplatePhoenix.Repo.insert!()
  end
end
