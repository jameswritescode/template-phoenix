ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(TemplatePhoenix.Repo, :manual)

# auth:begin — removed by bin/remove-auth.sh
Mox.defmock(TemplatePhoenix.MockWebAuthn, for: TemplatePhoenix.Accounts.WebAuthn)
# auth:end
