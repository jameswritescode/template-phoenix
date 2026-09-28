defmodule TemplatePhoenix.Accounts.Passkeys do
  @moduledoc """
  WebAuthn passkey ceremonies, credential management, and the sign-count
  clone-detection policy.

  Completion (`"webauthn-login"`) tokens are minted ONLY inside
  `verify_assertion_and_issue_login_token/2` and
  `verify_second_factor_and_issue_login_token/3` — every fully
  authenticated session for a passkey-holding account traces back to one
  of those two verified assertions.

  ## Observability

  Telemetry (all under `[:template_phoenix, :accounts, ...]`):
  `[:passkey, :registered | :renamed | :deleted]`,
  `[:passkey, :asserted]` (metadata: `:context`),
  `[:passkey, :verification_failed]`,
  `[:passkey, :sign_count_regression]`.

  Suggested alerts (Health-module style):
  - Page on ANY `sign_count_regression` — it indicates a cloned credential
    or a replayed assertion.
  - Chart login volume by `method` (see the session controller events) and
    passkey registrations/deletions per day.
  - Alert when `verification_failed` spikes relative to `asserted`.
  """

  import Ecto.Query

  alias TemplatePhoenix.Accounts.Scope
  alias TemplatePhoenix.Accounts.User
  alias TemplatePhoenix.Accounts.UserPasskey
  alias TemplatePhoenix.Accounts.WebAuthn
  alias TemplatePhoenix.Repo

  @spec passkeys_enabled?(User.t()) :: boolean()
  def passkeys_enabled?(%User{id: user_id}) do
    Repo.exists?(from p in UserPasskey, where: p.user_id == ^user_id)
  end

  ## Registration

  @spec new_registration_challenge(Scope.t()) :: {Wax.Challenge.t(), User.t(), [binary()]}
  def new_registration_challenge(%Scope{user: user}) do
    user = ensure_user_handle(user)

    exclude_ids =
      Repo.all(from p in UserPasskey, where: p.user_id == ^user.id, select: p.credential_id)

    challenge =
      WebAuthn.impl().new_registration_challenge(
        Keyword.put(WebAuthn.ceremony_opts(), :attestation, "none")
      )

    {challenge, user, exclude_ids}
  end

  @spec register_passkey(Scope.t(), Wax.Challenge.t(), map(), String.t()) ::
          {:ok, UserPasskey.t()}
          | {:error, :already_registered | :invalid_payload | :verification_failed}
  def register_passkey(%Scope{user: user}, %Wax.Challenge{} = challenge, payload, name) do
    with {:ok, attestation_object} <- decode_field(payload, "attestation_object"),
         {:ok, client_data_json} <- decode_field(payload, "client_data_json"),
         {:ok, {auth_data, _attestation}} <-
           verify(WebAuthn.impl().register(attestation_object, client_data_json, challenge)),
         :ok <- require_user_verified(auth_data) do
      insert_passkey(user, auth_data, name)
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @spec client_registration_options(Wax.Challenge.t(), User.t(), [binary()]) :: map()
  def client_registration_options(%Wax.Challenge{} = challenge, %User{} = user, exclude_ids) do
    %{
      challenge: Base.url_encode64(challenge.bytes, padding: false),
      rp: %{id: challenge.rp_id, name: "TemplatePhoenix"},
      user: %{
        id: Base.url_encode64(user.webauthn_user_handle, padding: false),
        name: user.email,
        displayName: user.email
      },
      pubKeyCredParams: [
        %{type: "public-key", alg: -8},
        %{type: "public-key", alg: -7},
        %{type: "public-key", alg: -257}
      ],
      authenticatorSelection: %{
        residentKey: "required",
        requireResidentKey: true,
        userVerification: "required"
      },
      excludeCredentials: Enum.map(exclude_ids, &credential_descriptor/1),
      attestation: "none",
      timeout: 120_000
    }
  end

  ## Shared helpers (private)

  defp ensure_user_handle(%User{webauthn_user_handle: nil} = user) do
    handle = :crypto.strong_rand_bytes(32)

    {_count, _} =
      Repo.update_all(
        from(u in User, where: u.id == ^user.id and is_nil(u.webauthn_user_handle)),
        set: [webauthn_user_handle: handle]
      )

    Repo.get!(User, user.id)
  end

  defp ensure_user_handle(%User{} = user), do: user

  defp insert_passkey(user, auth_data, name) do
    attested = auth_data.attested_credential_data

    %UserPasskey{
      user_id: user.id,
      credential_id: attested.credential_id,
      public_key: attested.credential_public_key,
      aaguid: attested.aaguid,
      sign_count: auth_data.sign_count,
      backup_eligible: backup_flag(auth_data, :flag_backup_eligible),
      backup_state: backup_flag(auth_data, :flag_credential_backed_up)
    }
    |> UserPasskey.register_changeset(%{"name" => name})
    |> Repo.insert()
    |> case do
      {:ok, passkey} ->
        emit([:passkey, :registered], %{user_id: user.id, passkey_id: passkey.id})
        {:ok, passkey}

      {:error, %Ecto.Changeset{errors: errors}} ->
        if Keyword.has_key?(errors, :credential_id),
          do: {:error, :already_registered},
          else: verification_failed(:changeset)
    end
  end

  # `field` is the literal Wax.AuthenticatorData key (`:flag_backup_eligible` /
  # `:flag_credential_backed_up`) — DB column names and Wax field names don't
  # align mechanically, so this takes the exact atom rather than interpolating it.
  defp backup_flag(auth_data, field) do
    case Map.get(auth_data, field) do
      value when is_boolean(value) -> value
      _absent -> false
    end
  end

  defp require_user_verified(%{flag_user_verified: true}), do: :ok
  defp require_user_verified(_auth_data), do: verification_failed(:user_verification_missing)

  defp verify({:ok, result}), do: {:ok, result}

  defp verify({:error, error}) do
    emit([:passkey, :verification_failed], %{error: inspect(error)})
    {:error, :verification_failed}
  end

  # Every `{:error, :verification_failed}` return path funnels through here (or
  # emits inline, for `verify/1`'s wax-error shape) so the moduledoc's "alert
  # when verification_failed spikes relative to asserted" invariant holds for
  # all registration failure paths, not just the Wax-rejected ones. `reason`
  # distinguishes the paths in telemetry metadata.
  defp verification_failed(reason) do
    emit([:passkey, :verification_failed], %{reason: reason})
    {:error, :verification_failed}
  end

  defp decode_field(payload, field) do
    with value when is_binary(value) <- Map.get(payload, field),
         {:ok, decoded} <- Base.url_decode64(value, padding: false) do
      {:ok, decoded}
    else
      _invalid -> {:error, :invalid_payload}
    end
  end

  defp credential_descriptor(credential_id) do
    %{type: "public-key", id: Base.url_encode64(credential_id, padding: false)}
  end

  defp emit(event_suffix, metadata) do
    :telemetry.execute(
      [:template_phoenix, :accounts | event_suffix],
      %{count: 1},
      metadata
    )
  end
end
