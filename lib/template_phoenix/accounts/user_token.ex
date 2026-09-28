defmodule TemplatePhoenix.Accounts.UserToken do
  use Ecto.Schema
  import Ecto.Query
  alias TemplatePhoenix.Accounts.UserToken

  @type t :: %__MODULE__{}

  @hash_algorithm :sha256
  @rand_size 32

  # It is very important to keep the magic link token expiry short,
  # since someone with access to the email may take over the account.
  @magic_link_validity_in_minutes 15
  @change_email_validity_in_days 7
  @session_validity_in_days 14
  @passkey_pending_validity_in_minutes 10
  @webauthn_login_validity_in_minutes 2

  schema "users_tokens" do
    field :token, :binary
    field :context, :string
    field :sent_to, :string
    field :authenticated_at, :utc_datetime
    belongs_to :user, TemplatePhoenix.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc """
  Generates a token that will be stored in a signed place,
  such as session or cookie. As they are signed, those
  tokens do not need to be hashed.

  The reason why we store session tokens in the database, even
  though Phoenix already provides a session cookie, is because
  Phoenix's default session cookies are not persisted, they are
  simply signed and potentially encrypted. This means they are
  valid indefinitely, unless you change the signing/encryption
  salt.

  Therefore, storing them allows individual user
  sessions to be expired. The token system can also be extended
  to store additional data, such as the device used for logging in.
  You could then use this information to display all valid sessions
  and devices in the UI and allow users to explicitly expire any
  session they deem invalid.
  """
  @spec build_session_token(TemplatePhoenix.Accounts.User.t()) :: {binary(), t()}
  def build_session_token(user) do
    token = :crypto.strong_rand_bytes(@rand_size)
    dt = user.authenticated_at || DateTime.utc_now(:second)
    {token, %UserToken{token: token, context: "session", user_id: user.id, authenticated_at: dt}}
  end

  @doc """
  Checks if the token is valid and returns its underlying lookup query.

  The query returns the user found by the token, if any, along with the token's creation time.

  The token is valid if it matches the value in the database and it has
  not expired (after @session_validity_in_days).
  """
  @spec verify_session_token_query(binary()) :: {:ok, Ecto.Query.t()}
  def verify_session_token_query(token) do
    query =
      from token in by_token_and_context_query(token, "session"),
        join: user in assoc(token, :user),
        where: token.inserted_at > ago(@session_validity_in_days, "day"),
        select: {%{user | authenticated_at: token.authenticated_at}, token.inserted_at}

    {:ok, query}
  end

  @doc """
  Builds a token and its hash to be delivered to the user's email.

  The non-hashed token is sent to the user email while the
  hashed part is stored in the database. The original token cannot be reconstructed,
  which means anyone with read-only access to the database cannot directly use
  the token in the application to gain access. Furthermore, if the user changes
  their email in the system, the tokens sent to the previous email are no longer
  valid.

  Users can easily adapt the existing code to provide other types of delivery methods,
  for example, by phone numbers.
  """
  @spec build_email_token(TemplatePhoenix.Accounts.User.t(), String.t()) :: {String.t(), t()}
  def build_email_token(user, context) do
    build_hashed_token(user, context, user.email)
  end

  defp build_hashed_token(user, context, sent_to) do
    token = :crypto.strong_rand_bytes(@rand_size)
    hashed_token = :crypto.hash(@hash_algorithm, token)

    {Base.url_encode64(token, padding: false),
     %UserToken{
       token: hashed_token,
       context: context,
       sent_to: sent_to,
       user_id: user.id
     }}
  end

  @doc """
  Checks if the token is valid and returns its underlying lookup query.

  If found, the query returns a tuple of the form `{user, token}`.

  The given token is valid if it matches its hashed counterpart in the
  database. This function also checks whether the token has expired. The context
  of a magic link token is always "login".
  """
  @spec verify_magic_link_token_query(String.t()) :: {:ok, Ecto.Query.t()} | :error
  def verify_magic_link_token_query(token) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded_token} ->
        hashed_token = :crypto.hash(@hash_algorithm, decoded_token)

        query =
          from token in by_token_and_context_query(hashed_token, "login"),
            join: user in assoc(token, :user),
            where: token.inserted_at > ago(^@magic_link_validity_in_minutes, "minute"),
            where: token.sent_to == user.email,
            select: {user, token}

        {:ok, query}

      :error ->
        :error
    end
  end

  @doc """
  Checks if the token is valid and returns its underlying lookup query.

  The query returns the user_token found by the token, if any.

  This is used to validate requests to change the user
  email.
  The given token is valid if it matches its hashed counterpart in the
  database and if it has not expired (after @change_email_validity_in_days).
  The context must always start with "change:".
  """
  @spec verify_change_email_token_query(String.t(), String.t()) :: {:ok, Ecto.Query.t()} | :error
  def verify_change_email_token_query(token, "change:" <> _ = context) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded_token} ->
        hashed_token = :crypto.hash(@hash_algorithm, decoded_token)

        query =
          from token in by_token_and_context_query(hashed_token, context),
            where: token.inserted_at > ago(@change_email_validity_in_days, "day")

        {:ok, query}

      :error ->
        :error
    end
  end

  defp by_token_and_context_query(token, context) do
    from UserToken, where: [token: ^token, context: ^context]
  end

  @doc """
  Builds a hashed, single-purpose passkey-flow token. `context` is
  "passkey-2fa" (pending second factor) or "webauthn-login" (assertion
  completion); `tag` is stored in `sent_to` and records how the token was
  issued ("second_factor" | "discoverable").
  """
  @spec build_passkey_token(TemplatePhoenix.Accounts.User.t(), String.t(), String.t() | nil) ::
          {String.t(), t()}
  def build_passkey_token(user, context, tag) when context in ["passkey-2fa", "webauthn-login"] do
    token = :crypto.strong_rand_bytes(@rand_size)
    hashed_token = :crypto.hash(@hash_algorithm, token)

    {Base.url_encode64(token, padding: false),
     %UserToken{token: hashed_token, context: context, sent_to: tag, user_id: user.id}}
  end

  @doc """
  Builds a pending second-factor token (`"passkey-2fa"` context, no tag) for
  `user`. A thin wrapper over `build_passkey_token/3` so that the completion
  ("webauthn-login") mint stays confined to `Passkeys` and this module —
  `Accounts` never calls `build_passkey_token/3` directly.
  """
  @spec build_pending_second_factor_token(TemplatePhoenix.Accounts.User.t()) :: {String.t(), t()}
  def build_pending_second_factor_token(user), do: build_passkey_token(user, "passkey-2fa", nil)

  @doc "Query for a still-valid passkey-flow token joined to its user."
  @spec verify_passkey_token_query(String.t(), String.t()) :: {:ok, Ecto.Query.t()} | :error
  def verify_passkey_token_query(encoded, context) do
    case Base.url_decode64(encoded, padding: false) do
      {:ok, decoded} ->
        hashed = :crypto.hash(@hash_algorithm, decoded)
        minutes = passkey_token_validity(context)

        query =
          from token in by_token_and_context_query(hashed, context),
            join: user in assoc(token, :user),
            where: token.inserted_at > ago(^minutes, "minute"),
            select: {user, token}

        {:ok, query}

      :error ->
        :error
    end
  end

  @spec passkey_token_validity(String.t()) :: pos_integer()
  defp passkey_token_validity("passkey-2fa"), do: @passkey_pending_validity_in_minutes

  @doc """
  Query to atomically delete-and-return a still-valid webauthn-login token
  (single-use: matched rows are gone once `Repo.delete_all/1` runs this
  query). The 2-minute TTL (`@webauthn_login_validity_in_minutes`) lives
  here — the only place it's defined — so `Accounts.consume_webauthn_login_token/1`
  never needs its own copy of the expiry window.

  Returns the query's `{:ok, query}`, selecting `%{user_id:, sent_to:}` per
  matched row, or `:error` if `encoded` isn't valid base64url.
  """
  @spec consume_passkey_token_query(String.t()) :: {:ok, Ecto.Query.t()} | :error
  def consume_passkey_token_query(encoded) do
    case Base.url_decode64(encoded, padding: false) do
      {:ok, decoded} ->
        hashed = :crypto.hash(@hash_algorithm, decoded)

        query =
          from token in by_token_and_context_query(hashed, "webauthn-login"),
            where: token.inserted_at > ago(^@webauthn_login_validity_in_minutes, "minute"),
            select: %{user_id: token.user_id, sent_to: token.sent_to}

        {:ok, query}

      :error ->
        :error
    end
  end
end
