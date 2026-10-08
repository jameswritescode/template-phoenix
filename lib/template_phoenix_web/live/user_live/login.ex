defmodule TemplatePhoenixWeb.UserLive.Login do
  @moduledoc "Log-in page: password, magic link, and discoverable passkey sign-in."

  use TemplatePhoenixWeb, :live_view

  alias TemplatePhoenix.Accounts
  alias TemplatePhoenix.Accounts.Passkeys
  alias TemplatePhoenix.Accounts.Scope
  alias TemplatePhoenix.Accounts.User

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-sm space-y-4">
        <div class="text-center">
          <.header>
            <p>Log in</p>
            <:subtitle>
              <%= if @current_scope do %>
                You need to reauthenticate to perform sensitive actions on your account.
              <% else %>
                Don't have an account? <.link
                  navigate={~p"/users/register"}
                  class="font-semibold text-brand hover:underline"
                  phx-no-format
                >Sign up</.link> for an account now.
              <% end %>
            </:subtitle>
          </.header>
        </div>

        <div :if={local_mail_adapter?()} class="alert alert-info">
          <.icon name="hero-information-circle" class="size-6 shrink-0" />
          <div>
            <p>You are running the local mail adapter.</p>
            <p>
              To see sent emails, visit <.link href="/dev/mailbox" class="underline">the mailbox page</.link>.
            </p>
          </div>
        </div>

        <div id="passkey-login" phx-hook="Passkey">
          <.button
            :if={@webauthn_supported}
            id="passkey-login-button"
            phx-click="passkey_login"
            class="btn btn-primary w-full"
          >
            <.icon name="hero-finger-print" class="size-5" /> Sign in with a passkey
          </.button>

          <.form
            for={@passkey_form}
            id="passkey-complete-form"
            action={~p"/users/log-in/passkey"}
            method="post"
            phx-trigger-action={@trigger_passkey_submit}
          >
            <input type="hidden" name="user[token]" value={@passkey_login_token} />
            <input type="hidden" name="user[remember_me]" value="false" />
          </.form>

          <div class="divider">or</div>
        </div>

        <.form
          :let={f}
          for={@form}
          id="login_form_magic"
          action={~p"/users/log-in"}
          phx-submit="submit_magic"
        >
          <.input
            readonly={!!@current_scope}
            field={f[:email]}
            type="email"
            label="Email"
            autocomplete="username"
            spellcheck="false"
            required
            phx-mounted={JS.focus()}
          />
          <.button class="btn btn-primary w-full">
            Log in with email <span aria-hidden="true">→</span>
          </.button>
        </.form>

        <div class="divider">or</div>

        <.form
          :let={f}
          for={@form}
          id="login_form_password"
          action={~p"/users/log-in"}
          phx-submit="submit_password"
          phx-trigger-action={@trigger_submit}
        >
          <.input
            readonly={!!@current_scope}
            field={f[:email]}
            type="email"
            label="Email"
            autocomplete="username"
            spellcheck="false"
            required
          />
          <.input
            field={@form[:password]}
            type="password"
            label="Password"
            autocomplete="current-password"
            spellcheck="false"
          />
          <.button class="btn btn-primary w-full" name={@form[:remember_me].name} value="true">
            Log in and stay logged in <span aria-hidden="true">→</span>
          </.button>
          <.button class="btn btn-primary btn-soft w-full mt-2">
            Log in only this time
          </.button>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    email =
      Phoenix.Flash.get(socket.assigns.flash, :email) ||
        get_in(socket.assigns, [:current_scope, Access.key(:user), Access.key(:email)])

    form = to_form(%{"email" => email}, as: "user")

    {:ok,
     socket
     |> assign(form: form, trigger_submit: false)
     |> assign(:webauthn_supported, true)
     |> assign(:passkey_challenge, nil)
     |> assign(:passkey_login_token, nil)
     |> assign(:trigger_passkey_submit, false)
     |> assign(:passkey_form, to_form(%{}, as: "user"))}
  end

  @impl true
  def handle_event("submit_password", _params, socket) do
    {:noreply, assign(socket, :trigger_submit, true)}
  end

  def handle_event("passkey_login", _params, socket) do
    {challenge, options} =
      case socket.assigns.current_scope do
        %Scope{user: %User{} = user} ->
          {challenge, allow_ids} = Passkeys.new_authentication_challenge_for_user(user)
          {challenge, Passkeys.client_authentication_options(challenge, allow_ids)}

        _anonymous ->
          challenge = Passkeys.new_discoverable_authentication_challenge()
          {challenge, Passkeys.client_authentication_options(challenge, [])}
      end

    {:noreply,
     socket
     |> assign(:passkey_challenge, challenge)
     |> push_event("webauthn:authenticate", options)}
  end

  def handle_event("webauthn:asserted", payload, socket) do
    # The challenge is discarded before calling any verify function — on
    # every outcome — per the Passkeys module's single-use contract: it
    # cannot make the challenge itself single-use, so the caller must.
    challenge = socket.assigns.passkey_challenge
    socket = assign(socket, :passkey_challenge, nil)

    result =
      case {challenge, socket.assigns.current_scope} do
        {nil, _scope} ->
          {:error, :verification_failed}

        {challenge, %Scope{user: %User{} = user}} ->
          Passkeys.verify_second_factor_and_issue_login_token(user, challenge, payload)

        {challenge, _anonymous} ->
          Passkeys.verify_assertion_and_issue_login_token(challenge, payload)
      end

    case result do
      {:ok, _user, login_token} ->
        {:noreply,
         socket
         |> assign(:passkey_login_token, login_token)
         |> assign(:trigger_passkey_submit, true)}

      {:error, :invalid_payload} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "That passkey couldn't be used here — use email and password, then your passkey."
         )}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "We couldn't verify that passkey. Try again.")}
    end
  end

  def handle_event("webauthn:unsupported", _params, socket) do
    {:noreply, assign(socket, :webauthn_supported, false)}
  end

  def handle_event("webauthn:error", %{"name" => name}, socket) do
    message =
      case name do
        "NotAllowedError" -> "Cancelled or timed out — try again."
        _other -> "Something went wrong with the passkey prompt. Try again."
      end

    {:noreply, put_flash(socket, :error, message)}
  end

  def handle_event("webauthn:error", _params, socket) do
    {:noreply,
     put_flash(socket, :error, "Something went wrong with the passkey prompt. Try again.")}
  end

  def handle_event("submit_magic", %{"user" => %{"email" => email}}, socket) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_login_instructions(
        user,
        &url(~p"/users/log-in/#{&1}")
      )
    end

    info =
      "If your email is in our system, you will receive instructions for logging in shortly."

    {:noreply,
     socket
     |> put_flash(:info, info)
     |> push_navigate(to: ~p"/users/log-in")}
  end

  defp local_mail_adapter? do
    Application.get_env(:template_phoenix, TemplatePhoenix.Mailer)[:adapter] ==
      Swoosh.Adapters.Local
  end
end
