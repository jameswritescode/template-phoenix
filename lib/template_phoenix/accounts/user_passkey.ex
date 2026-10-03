defmodule TemplatePhoenix.Accounts.UserPasskey do
  @moduledoc """
  A WebAuthn credential (passkey) registered to a user.

  `credential_id` is globally unique per the WebAuthn spec; the unique index
  is what makes the discoverable-credential login lookup unambiguous.
  Internal fields (`credential_id`, `public_key`, `sign_count`, flags) are
  set programmatically from verified ceremony output — only `name` is ever
  cast from user input.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias TemplatePhoenix.Accounts.User
  alias TemplatePhoenix.Accounts.UserPasskey.COSEKey

  @type t :: %__MODULE__{}

  schema "users_passkeys" do
    field :credential_id, :binary
    field :public_key, COSEKey
    field :name, :string
    field :sign_count, :integer, default: 0
    field :aaguid, :binary
    field :backup_eligible, :boolean, default: false
    field :backup_state, :boolean, default: false
    field :last_used_at, :utc_datetime

    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  @spec register_changeset(t(), map()) :: Ecto.Changeset.t()
  def register_changeset(passkey, attrs) do
    passkey
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 80)
    |> unique_constraint(:credential_id)
  end

  @spec rename_changeset(t(), map()) :: Ecto.Changeset.t()
  def rename_changeset(passkey, attrs) do
    passkey
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 80)
  end
end
