if match?({:module, Socket.TCP}, Code.ensure_compiled(Socket.TCP)) do
  defmodule EmailChecker.Check.SMTP do
    @moduledoc """
    Check if an emails server is aknowledging an email address.
    """

    require Logger

    @behaviour EmailChecker.Check

    alias EmailChecker.Tools
    alias Socket.TCP
    alias Socket.Stream

    @doc """
    Check if an emails server is aknowledging an email address.

    ## Parameters

      * `email` - `binary` - the email to check
      * `retries` - `non_neg_integer` - max retries (default from config)

    ## Example

        iex> EmailChecker.Check.SMTP.valid?("test@gmail.com")
        false

    """
    @spec valid?(String.t(), non_neg_integer) :: boolean
    def valid?(email, retries \\ max_retries())
    def valid?(_, 0), do: false

    def valid?(email, retries) do
      case smtp_reply(email) do
        nil ->
          Logger.info("No respnse.")
          false

        response ->
          Logger.info("Checking for 250.")
          Regex.match?(~r/^250 /, response)
      end
    rescue
      Socket.Error ->
        Logger.info("Socket error. Retrying.")
        valid?(email, retries - 1)

      _ ->
        Logger.info("Address doesnt exist.")
        false
    end

    defp mx_address(email) do
      email
      |> Tools.domain_name()
      |> Tools.lookup()
    end

    defp timeout_opt do
      case max_timeout() do
        :infinity ->
          :infinity

        t when is_integer(t) ->
          t |> div(max_retries()) |> abs
      end
    end

    defp smtp_reply(email) do
      opts = [packet: :line, timeout: timeout_opt()]
      Logger.info("Starting TCP conn.")

      socket =
        email
        |> mx_address
        |> TCP.connect!(25, opts)

      socket |> Stream.recv!()
      Logger.info("TCP opened.")
      socket |> Stream.send!("HELO #{Tools.domain_name(email)}\r\n")
      socket |> Stream.recv!()
      Logger.info("HELO sent.")

      socket |> Stream.send!("mail from:<#{Tools.default_from()}>\r\n")
      socket |> Stream.recv!()

      Logger.info("Mail From set.")
      Logger.info("Checking RCPT.")
      socket |> Stream.send!("rcpt to:<#{email}>\r\n")
      socket |> Stream.recv!()
    end

    defp max_retries, do: Application.get_env(:email_checker, :smtp_retries, 2)
    defp max_timeout, do: Application.get_env(:email_checker, :timeout_milliseconds, 2000)
  end
end
