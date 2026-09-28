defmodule TemplatePhoenix.Repo.Migrations.AddUsersPasskeys do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :webauthn_user_handle, :binary
    end

    create unique_index(:users, [:webauthn_user_handle])

    create table(:users_passkeys) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :credential_id, :binary, null: false
      add :public_key, :binary, null: false
      add :name, :string, null: false
      add :sign_count, :bigint, null: false, default: 0
      add :aaguid, :binary
      add :backup_eligible, :boolean, null: false, default: false
      add :backup_state, :boolean, null: false, default: false
      add :last_used_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:users_passkeys, [:credential_id])
    create index(:users_passkeys, [:user_id])
  end
end
