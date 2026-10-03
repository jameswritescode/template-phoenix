defmodule TemplatePhoenixWeb.UserLive.Passkeys do
  @moduledoc """
  Passkey management (list / add / rename / delete), behind sudo mode so a
  stolen session cannot strip an account's second factor.
  """
  use TemplatePhoenixWeb, :live_view

  require Logger

  alias TemplatePhoenix.Accounts
  alias TemplatePhoenix.Accounts.Passkeys

  @sudo_events ["add", "webauthn:registered", "rename", "delete"]

  on_mount {TemplatePhoenixWeb.UserAuth, :require_sudo_mode}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-2xl space-y-8" id="passkeys-hook" phx-hook="Passkey">
        <.header>
          Passkeys
          <:subtitle>
            <%= if @passkeys == [] do %>
              Add a passkey and signing in to this account will always require it
              (or another passkey you add later), on every sign-in method.
            <% else %>
              Sign-in to this account requires one of these passkeys as a second factor.
            <% end %>
          </:subtitle>
          <:actions>
            <.button
              :if={@webauthn_supported}
              id="add-passkey"
              phx-click="add"
              class="btn btn-primary"
            >
              <.icon name="hero-finger-print" class="size-5" /> Add a passkey
            </.button>
          </:actions>
        </.header>

        <p :if={!@webauthn_supported} class="text-sm opacity-75" id="webauthn-unsupported">
          This browser doesn't support passkeys.
        </p>

        <.table
          :if={@passkeys != []}
          id="passkeys-table"
          rows={@passkeys}
          row_id={&"passkey-#{&1.id}"}
        >
          <:col :let={passkey} label="Name">
            <p class="font-medium">{passkey.name}</p>
            <details class="mt-1">
              <summary class="cursor-pointer text-sm text-base-content/70 hover:text-base-content">
                Rename
              </summary>
              <.form
                for={to_form(%{"name" => passkey.name}, as: :passkey)}
                id={"rename-passkey-#{passkey.id}"}
                phx-submit="rename"
                class="mt-2 flex items-center gap-2"
              >
                <.input
                  type="text"
                  name="passkey[name]"
                  value={passkey.name}
                  class="input input-sm w-40"
                />
                <input
                  type="hidden"
                  id={"rename-passkey-#{passkey.id}-id"}
                  name="passkey_id"
                  value={passkey.id}
                />
                <button type="submit" class="btn btn-sm btn-primary">Save</button>
              </.form>
            </details>
          </:col>
          <:col :let={passkey} label="Added">
            {Calendar.strftime(passkey.inserted_at, "%b %-d, %Y")}
          </:col>
          <:col :let={passkey} label="Last used">
            {if passkey.last_used_at,
              do: Calendar.strftime(passkey.last_used_at, "%b %-d, %Y"),
              else: "Never"}
          </:col>
          <:action :let={passkey}>
            <.link
              id={"delete-passkey-#{passkey.id}"}
              phx-click="delete"
              phx-value-id={passkey.id}
              data-confirm={delete_confirmation(@passkeys)}
            >
              Delete
            </.link>
          </:action>
        </.table>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, session, socket) do
    {:ok,
     socket
     |> assign(:user_token, session["user_token"])
     |> assign(:webauthn_supported, true)
     |> assign(:registration_challenge, nil)
     |> assign(:passkeys, Passkeys.list_passkeys(socket.assigns.current_scope))}
  end

  @impl true
  def handle_event(event, params, socket) when event in @sudo_events do
    if sudo_fresh?(socket) do
      handle_sudo_event(event, params, socket)
    else
      Logger.info(
        "passkey management blocked: sudo expired " <>
          "user_id=#{socket.assigns.current_scope.user.id} event=#{event}"
      )

      {:noreply,
       socket
       |> put_flash(:error, "You must re-authenticate to manage passkeys.")
       |> redirect(to: ~p"/users/log-in")}
    end
  end

  def handle_event("webauthn:unsupported", _params, socket) do
    {:noreply, assign(socket, :webauthn_supported, false)}
  end

  def handle_event("webauthn:error", %{"name" => name}, socket) do
    message =
      case name do
        "NotAllowedError" -> "Cancelled or timed out — try again."
        "InvalidStateError" -> "This device is already registered as a passkey."
        _other -> "Something went wrong with the passkey prompt. Try again."
      end

    {:noreply, put_flash(socket, :error, message)}
  end

  def handle_event("webauthn:error", _params, socket) do
    {:noreply,
     put_flash(socket, :error, "Something went wrong with the passkey prompt. Try again.")}
  end

  # The on_mount gate only checks sudo once; a tab left open (or anything
  # riding its socket) must not add or strip a second factor hours later.
  # Re-reads the session token so a stamp that aged — or a token revoked —
  # since mount is seen. 20-minute grace mirrors the Settings LiveView.
  defp sudo_fresh?(%{assigns: %{user_token: token, current_scope: scope}})
       when is_binary(token) do
    case Accounts.get_user_by_session_token(token) do
      {%Accounts.User{id: id} = user, _inserted_at} when id == scope.user.id ->
        Accounts.sudo_mode?(user)

      _other ->
        false
    end
  end

  defp sudo_fresh?(_socket), do: false

  defp handle_sudo_event("add", _params, socket) do
    {challenge, user, exclude_ids} =
      Passkeys.new_registration_challenge(socket.assigns.current_scope)

    {:noreply,
     socket
     |> assign(:registration_challenge, challenge)
     |> push_event(
       "webauthn:register",
       Passkeys.client_registration_options(challenge, user, exclude_ids)
     )}
  end

  defp handle_sudo_event("webauthn:registered", payload, socket) do
    case socket.assigns.registration_challenge do
      nil -> {:noreply, put_flash(socket, :error, "No registration in progress — try again.")}
      challenge -> finish_registration(socket, challenge, payload)
    end
  end

  defp handle_sudo_event("rename", %{"passkey_id" => id, "passkey" => %{"name" => name}}, socket) do
    case Passkeys.rename_passkey(socket.assigns.current_scope, id, name) do
      {:ok, _passkey} ->
        {:noreply,
         assign(socket, :passkeys, Passkeys.list_passkeys(socket.assigns.current_scope))}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Names must be 1–80 characters.")}
    end
  end

  defp handle_sudo_event("delete", %{"id" => id}, socket) do
    {:ok, _deleted, remaining} = Passkeys.delete_passkey(socket.assigns.current_scope, id)

    flash =
      if remaining == 0,
        do: "Passkey deleted — passkey sign-in and two-factor is now off for this account.",
        else: "Passkey deleted."

    {:noreply,
     socket
     |> assign(:passkeys, Passkeys.list_passkeys(socket.assigns.current_scope))
     |> put_flash(:info, flash)}
  end

  defp finish_registration(socket, challenge, payload) do
    # The challenge is discarded before calling `register_passkey/4` — on
    # every outcome — per that function's single-use contract: it cannot
    # make the challenge itself single-use, so the caller must.
    socket = assign(socket, :registration_challenge, nil)

    case Passkeys.register_passkey(
           socket.assigns.current_scope,
           challenge,
           payload,
           default_name()
         ) do
      {:ok, _passkey} ->
        passkeys = Passkeys.list_passkeys(socket.assigns.current_scope)

        flash =
          if length(passkeys) == 1,
            do:
              "Passkey added. From now on, signing in to this account always requires a passkey.",
            else: "Passkey added."

        {:noreply, socket |> assign(:passkeys, passkeys) |> put_flash(:info, flash)}

      {:error, :already_registered} ->
        {:noreply, put_flash(socket, :error, "That passkey is already registered.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "We couldn't verify that passkey. Try again.")}
    end
  end

  @spec default_name() :: String.t()
  defp default_name, do: "Passkey (#{Calendar.strftime(Date.utc_today(), "%b %-d, %Y")})"

  @spec delete_confirmation([TemplatePhoenix.Accounts.UserPasskey.t()]) :: String.t()
  defp delete_confirmation(passkeys) when length(passkeys) == 1 do
    "This is your last passkey. Deleting it turns off passkey sign-in and two-factor for this account. Continue?"
  end

  defp delete_confirmation(_passkeys), do: "Delete this passkey?"
end
