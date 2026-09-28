defmodule TemplatePhoenix.Accounts.UserPasskey.COSEKey do
  @moduledoc """
  Stores a COSE public key (the Erlang map `Wax.register/3` produces) in a
  binary column.

  Values are written only from `Wax` output inside
  `TemplatePhoenix.Accounts.Passkeys` and read back only from our own
  database, so `:erlang.binary_to_term/1` never sees external input.
  """
  use Ecto.Type

  @impl true
  def type, do: :binary

  @impl true
  def cast(%{} = cose_key), do: {:ok, cose_key}
  def cast(_other), do: :error

  @impl true
  def dump(%{} = cose_key), do: {:ok, :erlang.term_to_binary(cose_key)}
  def dump(_other), do: :error

  @impl true
  def load(binary) when is_binary(binary), do: {:ok, :erlang.binary_to_term(binary)}
  def load(_other), do: :error
end
