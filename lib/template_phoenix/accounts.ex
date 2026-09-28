defmodule TemplatePhoenix.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias TemplatePhoenix.Repo

  alias TemplatePhoenix.Accounts.{User, UserNotifier, UserToken}

  ## Database getters

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  @spec get_user_by_email(String.t()) :: User.t() | nil
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  @spec get_user_by_email_and_password(String.t(), String.t()) :: User.t() | nil
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  @spec get_user!(integer()) :: User.t()
  def get_user!(id), do: Repo.get!(User, id)

  ## User registration

  @doc """
  Registers a user.

  ## Examples

      iex> register_user(%{field: value})
      {:ok, %User{}}

      iex> register_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec register_user(map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def register_user(attrs) do
    %User{}
    |> User.email_changeset(attrs)
    |> Repo.insert()
  end

  ## Settings

  @doc """
  Checks whether the user is in sudo mode.

  The user is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.
  """
  @spec sudo_mode?(User.t() | nil, integer()) :: boolean()
  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  See `TemplatePhoenix.Accounts.User.email_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  @spec change_user_email(User.t(), map(), keyword()) :: Ecto.Changeset.t()
  def change_user_email(user, attrs \\ %{}, opts \\ []) do
    User.email_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  """
  @spec update_user_email(User.t(), String.t()) ::
          {:ok, User.t()} | {:error, :transaction_aborted}
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    Repo.transact(fn ->
      with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
           %UserToken{sent_to: email} <- Repo.one(query),
           {:ok, user} <- Repo.update(User.email_changeset(user, %{email: email})),
           {_count, _result} <-
             Repo.delete_all(from(UserToken, where: [user_id: ^user.id, context: ^context])) do
        {:ok, user}
      else
        _ -> {:error, :transaction_aborted}
      end
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  See `TemplatePhoenix.Accounts.User.password_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  @spec change_user_password(User.t(), map(), keyword()) :: Ecto.Changeset.t()
  def change_user_password(user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user password.

  Returns a tuple with the updated user, as well as a list of expired tokens.

  ## Examples

      iex> update_user_password(user, %{password: ...})
      {:ok, {%User{}, [...]}}

      iex> update_user_password(user, %{password: "too short"})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_user_password(User.t(), map()) ::
          {:ok, {User.t(), [UserToken.t()]}} | {:error, Ecto.Changeset.t()}
  def update_user_password(user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> update_user_and_delete_all_tokens()
  end

  ## Session

  @doc """
  Generates a session token.
  """
  @spec generate_user_session_token(User.t()) :: binary()
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.

  If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  @spec get_user_by_session_token(binary()) :: {User.t(), DateTime.t()} | nil
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Gets the user with the given magic link token.
  """
  @spec get_user_by_magic_link_token(String.t()) :: User.t() | nil
  def get_user_by_magic_link_token(token) do
    with {:ok, query} <- UserToken.verify_magic_link_token_query(token),
         {user, _token} <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Logs the user in by magic link.

  There are three cases to consider:

  1. The user has already confirmed their email. They are logged in
     and the magic link is expired.

  2. The user has not confirmed their email and no password is set.
     In this case, the user gets confirmed, logged in, and all tokens -
     including session ones - are expired. In theory, no other tokens
     exist but we delete all of them for best security practices.

  3. The user has not confirmed their email but a password is set.
     This cannot happen in the default implementation but may be the
     source of security pitfalls. See the "Mixing magic link and password registration" section of
     `mix help phx.gen.auth`.
  """
  @spec login_user_by_magic_link(String.t()) ::
          {:ok, {User.t(), [UserToken.t()]}} | {:error, Ecto.Changeset.t() | :not_found}
  def login_user_by_magic_link(token) do
    {:ok, query} = UserToken.verify_magic_link_token_query(token)

    case Repo.one(query) do
      # Prevent session fixation attacks by disallowing magic links for unconfirmed users with password
      {%User{confirmed_at: nil, hashed_password: hash}, _token} when not is_nil(hash) ->
        raise """
        magic link log in is not allowed for unconfirmed users with a password set!

        This cannot happen with the default implementation, which indicates that you
        might have adapted the code to a different use case. Please make sure to read the
        "Mixing magic link and password registration" section of `mix help phx.gen.auth`.
        """

      {%User{confirmed_at: nil} = user, _token} ->
        user
        |> User.confirm_changeset()
        |> update_user_and_delete_all_tokens()

      {user, token} ->
        Repo.delete!(token)
        {:ok, {user, []}}

      nil ->
        {:error, :not_found}
    end
  end

  @doc ~S"""
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/users/settings/confirm-email/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  @spec deliver_user_update_email_instructions(User.t(), String.t(), (String.t() -> String.t())) ::
          {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @doc """
  Delivers the magic link login instructions to the given user.
  """
  @spec deliver_login_instructions(User.t(), (String.t() -> String.t())) ::
          {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver_login_instructions(%User{} = user, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "login")
    Repo.insert!(user_token)
    UserNotifier.deliver_login_instructions(user, magic_link_url_fun.(encoded_token))
  end

  @doc """
  Deletes the signed token with the given context.
  """
  @spec delete_user_session_token(binary()) :: :ok
  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  ## Passkey flow tokens

  @doc """
  Generates a pending second-factor token for `user`, deleting any prior
  pending token for that user first (10-minute TTL).
  """
  @spec generate_pending_second_factor_token(User.t()) :: String.t()
  def generate_pending_second_factor_token(user) do
    {:ok, encoded} =
      Repo.transact(fn ->
        Repo.delete_all(
          from(t in UserToken, where: t.user_id == ^user.id and t.context == "passkey-2fa")
        )

        {encoded, token} = UserToken.build_pending_second_factor_token(user)
        Repo.insert!(token)
        {:ok, encoded}
      end)

    encoded
  end

  @doc """
  Gets the user for a pending second-factor token, if it is still valid.
  Reading does not consume the token.
  """
  @spec get_user_by_pending_second_factor_token(String.t()) :: User.t() | nil
  def get_user_by_pending_second_factor_token(encoded) when is_binary(encoded) do
    with {:ok, query} <- UserToken.verify_passkey_token_query(encoded, "passkey-2fa"),
         {user, _token} <- Repo.one(query) do
      user
    else
      _invalid -> nil
    end
  end

  def get_user_by_pending_second_factor_token(_other), do: nil

  @doc """
  Deletes a pending second-factor token, if any. Always returns `:ok`.
  """
  @spec delete_pending_second_factor_token(String.t()) :: :ok
  def delete_pending_second_factor_token(encoded) when is_binary(encoded) do
    case Base.url_decode64(encoded, padding: false) do
      {:ok, decoded} ->
        hashed = :crypto.hash(:sha256, decoded)

        Repo.delete_all(
          from(t in UserToken, where: t.token == ^hashed and t.context == "passkey-2fa")
        )

        :ok

      :error ->
        :ok
    end
  end

  def delete_pending_second_factor_token(_other), do: :ok

  @doc """
  Deletes every pending second-factor token for `user`. Always returns `:ok`.
  """
  @spec delete_pending_second_factor_tokens_for_user(User.t()) :: :ok
  def delete_pending_second_factor_tokens_for_user(%User{id: user_id}) do
    Repo.delete_all(
      from(t in UserToken, where: t.user_id == ^user_id and t.context == "passkey-2fa")
    )

    :ok
  end

  @doc """
  Atomically consumes a webauthn login-completion token (2-minute TTL,
  sourced from `UserToken.consume_passkey_token_query/1`), returning the
  user and the tag recorded at issuance ("second_factor" or "discoverable").
  Single-use: the row is deleted in the same query that matches it.

  Returns `:error` (never raises) if the user backing the token was deleted
  in the window between issuance and consumption.
  """
  @spec consume_webauthn_login_token(String.t()) :: {:ok, User.t(), String.t()} | :error
  def consume_webauthn_login_token(encoded) when is_binary(encoded) do
    with {:ok, query} <- UserToken.consume_passkey_token_query(encoded) do
      query |> Repo.delete_all() |> finish_webauthn_login_token_consumption()
    end
  end

  def consume_webauthn_login_token(_other), do: :error

  defp finish_webauthn_login_token_consumption({1, [%{user_id: user_id, sent_to: method}]}) do
    case Repo.get(User, user_id) do
      nil -> :error
      user -> {:ok, user, method}
    end
  end

  defp finish_webauthn_login_token_consumption(_none), do: :error

  ## Token helper

  defp update_user_and_delete_all_tokens(changeset) do
    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        tokens_to_expire = Repo.all_by(UserToken, user_id: user.id)

        Repo.delete_all(from(t in UserToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id)))

        {:ok, {user, tokens_to_expire}}
      end
    end)
  end
end
