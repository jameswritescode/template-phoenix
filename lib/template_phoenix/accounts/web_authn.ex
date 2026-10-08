defmodule TemplatePhoenix.Accounts.WebAuthn do
  @moduledoc """
  Boundary for WebAuthn ceremony verification — the only place `Wax` is
  called. Swapped for a Mox mock in tests via `:webauthn_module`.

  Ceremony options are derived at runtime from the endpoint so per-worktree
  dev hosts (`SUBDOMAIN=foo` → `http://foo.localhost:PORT`) work unchanged.
  Passkeys are scoped to the RP ID, so a credential enrolled on
  `foo.localhost` will not be offered on `bar.localhost` — expected.
  """

  @callback new_registration_challenge(keyword()) :: Wax.Challenge.t()
  @callback register(binary(), binary(), Wax.Challenge.t()) ::
              {:ok, {Wax.AuthenticatorData.t(), term()}} | {:error, Exception.t()}
  @callback new_authentication_challenge(keyword()) :: Wax.Challenge.t()
  @callback authenticate(binary(), binary(), binary(), binary(), Wax.Challenge.t(), [
              {binary(), map()}
            ]) ::
              {:ok, Wax.AuthenticatorData.t()} | {:error, Exception.t()}

  @spec impl() :: module()
  def impl do
    Application.get_env(
      :template_phoenix,
      :webauthn_module,
      TemplatePhoenix.Accounts.WebAuthn.WaxAdapter
    )
  end

  @spec ceremony_opts() :: keyword()
  def ceremony_opts do
    endpoint = Application.fetch_env!(:template_phoenix, :webauthn)[:endpoint]

    [
      origin: endpoint.url(),
      rp_id: endpoint.host(),
      user_verification: "required",
      timeout: 120
    ]
  end
end
