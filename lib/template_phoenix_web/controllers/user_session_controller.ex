defmodule TemplatePhoenixWeb.UserSessionController do
  use TemplatePhoenixWeb, :controller

  alias TemplatePhoenix.Accounts
  alias TemplatePhoenixWeb.UserAuth

  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, %{"_action" => "confirmed"} = params) do
    create(conn, params, "User confirmed successfully.")
  end

  def create(conn, params) do
    create(conn, params, "Welcome back!")
  end

  # magic link login
  defp create(conn, %{"user" => %{"token" => token} = user_params}, info) do
    case Accounts.login_user_by_magic_link(token) do
      {:ok, {user, tokens_to_disconnect}} ->
        UserAuth.disconnect_sessions(tokens_to_disconnect)

        conn
        |> put_flash(:info, info)
        |> UserAuth.log_in_user(user, Map.put(user_params, "_login_method", "magic_link"))

      _ ->
        :telemetry.execute(
          [:template_phoenix, :accounts, :login],
          %{count: 1},
          %{result: :failure, method: "magic_link"}
        )

        conn
        |> put_flash(:error, "The link is invalid or it has expired.")
        |> redirect(to: ~p"/users/log-in")
    end
  end

  # email + password login
  defp create(conn, %{"user" => user_params}, info) do
    %{"email" => email, "password" => password} = user_params

    if user = Accounts.get_user_by_email_and_password(email, password) do
      conn
      |> put_flash(:info, info)
      |> UserAuth.log_in_user(user, Map.put(user_params, "_login_method", "password"))
    else
      :telemetry.execute(
        [:template_phoenix, :accounts, :login],
        %{count: 1},
        %{result: :failure, method: "password"}
      )

      # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
      conn
      |> put_flash(:error, "Invalid email or password")
      |> put_flash(:email, String.slice(email, 0, 160))
      |> redirect(to: ~p"/users/log-in")
    end
  end

  @spec create_passkey(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create_passkey(conn, %{"user" => %{"token" => token} = user_params}) do
    case Accounts.consume_webauthn_login_token(token) do
      {:ok, user, method} ->
        params =
          case get_session(conn, :passkey_2fa_remember_me) do
            nil -> Map.take(user_params, ["remember_me"])
            value -> %{"remember_me" => to_string(value)}
          end
          |> Map.put("_login_method", "passkey_#{method}")

        conn
        |> put_flash(:info, "Welcome back!")
        |> UserAuth.log_in_user_after_webauthn(user, params)

      :error ->
        conn
        |> put_flash(:error, "We couldn't complete passkey sign-in. Please try again.")
        |> redirect(to: ~p"/users/log-in")
    end
  end

  @spec update_password(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def update_password(conn, %{"user" => user_params} = params) do
    user = conn.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)
    {:ok, {_user, expired_tokens}} = Accounts.update_user_password(user, user_params)

    # disconnect all existing LiveViews with old sessions
    UserAuth.disconnect_sessions(expired_tokens)

    conn
    |> put_session(:user_return_to, ~p"/users/settings")
    |> create(params, "Password updated successfully!")
  end

  @spec delete(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end
end
