defmodule TemplatePhoenix.Accounts.FakeWebAuthn do
  @moduledoc """
  Happy-path `WebAuthn` stub for tests (installed via `Mox.stub_with/2`).

  Contract with fixtures: `register/3` succeeds and echoes the decoded
  `attestation_object` bytes back as the credential id, so a test chooses
  its credential id through the payload. `authenticate/6` succeeds only
  when the asserted credential id is present in the `credentials` list
  (which is how cross-user rejection stays observable), with `sign_count: 0`.
  Use `Mox.expect` on `TemplatePhoenix.MockWebAuthn` for failures,
  sign-count scenarios, or specific flags.
  """

  @behaviour TemplatePhoenix.Accounts.WebAuthn

  alias TemplatePhoenix.Accounts.WebAuthn.WaxAdapter

  @impl true
  defdelegate new_registration_challenge(opts), to: WaxAdapter

  @impl true
  defdelegate new_authentication_challenge(opts), to: WaxAdapter

  @impl true
  def register(attestation_object, _client_data_json, _challenge) do
    {:ok, {auth_data(credential_id: attestation_object), :none}}
  end

  @impl true
  def authenticate(credential_id, _auth_data, _sig, _client_data_json, _challenge, credentials) do
    if List.keymember?(credentials, credential_id, 0) do
      {:ok, auth_data(credential_id: credential_id)}
    else
      {:error, %RuntimeError{message: "unknown credential"}}
    end
  end

  @spec auth_data(keyword()) :: Wax.AuthenticatorData.t()
  def auth_data(opts \\ []) do
    credential_id = Keyword.get(opts, :credential_id, "cred")
    sign_count = Keyword.get(opts, :sign_count, 0)

    attested =
      struct!(Wax.AttestedCredentialData,
        aaguid: <<0::128>>,
        credential_id: credential_id,
        credential_public_key: %{1 => 1, 3 => -8, -1 => credential_id}
      )

    defaults = [
      rp_id_hash: :crypto.hash(:sha256, "localhost"),
      flag_user_present: true,
      flag_user_verified: true,
      flag_backup_eligible: false,
      flag_credential_backed_up: false,
      flag_attested_credential_data: true,
      flag_extension_data_included: false,
      sign_count: sign_count,
      attested_credential_data: attested,
      raw_bytes: <<>>
    ]

    overrides = Keyword.drop(opts, [:credential_id, :sign_count])

    struct!(Wax.AuthenticatorData, Keyword.merge(defaults, overrides))
  end
end
