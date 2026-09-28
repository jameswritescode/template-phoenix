defmodule TemplatePhoenixWeb.UserLive.TwoFactor do
  @moduledoc """
  Mandatory passkey step for accounts that have passkeys. Reached only via
  the gate in `UserAuth.log_in_user/3` after a verified first factor; the
  pending state is a 10-minute single-purpose token in the session.
  """
  use TemplatePhoenixWeb, :live_view

  alias TemplatePhoenix.Accounts
  alias TemplatePhoenix.Accounts.Passkeys

  on_mount {TemplatePhoenixWeb.UserAuth, :require_pending_second_factor}

  @max_attempts 5

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-sm space-y-6 text-center" id="two-factor" phx-hook="Passkey">
        <.header>
          Confirm it's you
          <:subtitle>
            This account is protected by a passkey. Use it to finish signing in.
            If you arrived by email link: that link has been used — if you can't
            finish here, request a new one.
          </:subtitle>
        </.header>

        <.button id="two-factor-retry" phx-click="retry" class="btn btn-primary w-full">
          <.icon name="hero-finger-print" class="size-5" /> Use my passkey
        </.button>

        <p :if={!@webauthn_supported} class="text-sm" id="two-factor-unsupported">
          This browser can't use passkeys, and this account requires one.
          Switch to a browser or device with passkey support to sign in.
        </p>

        <.form
          for={@trigger_form}
          id="two-factor-complete-form"
          action={~p"/users/log-in/passkey"}
          method="post"
          phx-trigger-action={@trigger_submit}
        >
          <input type="hidden" name="user[token]" value={@login_token} />
          <input type="hidden" name="user[remember_me]" value={to_string(@pending_remember_me)} />
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:webauthn_supported, true)
      |> assign(:challenge, nil)
      |> assign(:attempts, 0)
      |> assign(:login_token, nil)
      |> assign(:trigger_submit, false)
      |> assign(:trigger_form, to_form(%{}, as: "user"))

    {:ok, if(connected?(socket), do: push_challenge(socket), else: socket)}
  end

  @impl true
  def handle_event("retry", _params, socket) do
    {:noreply, push_challenge(socket)}
  end

  def handle_event("webauthn:asserted", payload, socket) do
    case socket.assigns.challenge do
      nil ->
        {:noreply, put_flash(socket, :error, "We couldn't verify that passkey. Try again.")}

      challenge ->
        # Single-use challenge: cleared before verification so a replayed or
        # double-submitted assertion can never be verified twice.
        socket = assign(socket, :challenge, nil)

        case Passkeys.verify_second_factor_and_issue_login_token(
               socket.assigns.pending_user,
               challenge,
               payload
             ) do
          {:ok, _user, login_token} ->
            {:noreply,
             socket
             |> assign(:login_token, login_token)
             |> assign(:trigger_submit, true)}

          {:error, _reason} ->
            fail_attempt(socket)
        end
    end
  end

  def handle_event("webauthn:unsupported", _params, socket) do
    {:noreply, assign(socket, :webauthn_supported, false)}
  end

  def handle_event("webauthn:error", params, socket) do
    message =
      case params do
        %{"name" => "NotAllowedError"} -> "Cancelled or timed out — try again."
        _other -> "Something went wrong with the passkey prompt. Try again."
      end

    {:noreply, put_flash(socket, :error, message)}
  end

  defp push_challenge(socket) do
    {challenge, allow_ids} =
      Passkeys.new_authentication_challenge_for_user(socket.assigns.pending_user)

    socket
    |> assign(:challenge, challenge)
    |> push_event(
      "webauthn:authenticate",
      Passkeys.client_authentication_options(challenge, allow_ids)
    )
  end

  defp fail_attempt(socket) do
    attempts = socket.assigns.attempts + 1

    if attempts >= @max_attempts do
      :telemetry.execute(
        [:template_phoenix, :accounts, :login],
        %{count: 1},
        %{result: :two_factor_abandoned, reason: :attempts_exhausted}
      )

      Accounts.delete_pending_second_factor_tokens_for_user(socket.assigns.pending_user)

      {:noreply,
       socket
       |> put_flash(:error, "Too many failed attempts. Please sign in again.")
       |> redirect(to: ~p"/users/log-in")}
    else
      {:noreply,
       socket
       |> assign(:attempts, attempts)
       |> put_flash(:error, "We couldn't verify that passkey. Try again.")}
    end
  end
end
