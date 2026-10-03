defmodule TemplatePhoenix.Accounts.WebAuthn.WaxAdapter do
  @moduledoc "Production `TemplatePhoenix.Accounts.WebAuthn` implementation, delegating to `Wax`."

  @behaviour TemplatePhoenix.Accounts.WebAuthn

  @impl true
  defdelegate new_registration_challenge(opts), to: Wax

  @impl true
  defdelegate register(attestation_object, client_data_json, challenge), to: Wax

  @impl true
  defdelegate new_authentication_challenge(opts), to: Wax

  @impl true
  defdelegate authenticate(
                credential_id,
                authenticator_data,
                signature,
                client_data_json,
                challenge,
                credentials
              ),
              to: Wax
end
