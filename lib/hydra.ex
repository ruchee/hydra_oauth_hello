alias OAuth2.Strategy.AuthCode
alias OAuth2.{AccessToken, Client, Error, Request, Response}

defmodule Hydra do
  use OAuth2.Strategy

  defp config do
    [
      strategy: Hydra,
      site: "http://127.0.0.1:4000",
      authorize_url: "http://127.0.0.1:4444/oauth2/auth",
      token_url: "http://127.0.0.1:4444/oauth2/token"
    ]
  end

  # Public API

  def client do
    Application.get_env(:hello, Hydra)
    |> Keyword.merge(config())
    |> OAuth2.Client.new()
  end

  def authorize_url!(params \\ []) do
    OAuth2.Client.authorize_url!(client(), params) <> "&state=" <> random_state(20)
  end

  def get_token!(params \\ [], _headers \\ []) do
    get_token_dup!(client(), Keyword.merge(params, client_secret: client().client_secret))
  end

  def get_user!(code) do
    resp = try do
      [code: code]
      |> Hydra.get_token!()
      |> OAuth2.Client.get!("/oauth/v2/user")
    rescue
      e ->
        raise e
    end

    resp.body
  end

  # Strategy Callbacks

  def authorize_url(client, params) do
    AuthCode.authorize_url(client, params)
  end

  def get_token(client, params, headers) do
    client
    |> put_header("Accept", "application/json")
    |> AuthCode.get_token(params, headers)
  end

  # Utils

  defp get_token_dup!(client, params \\ [], headers \\ [], opts \\ []) do
    case get_token_dup(client, params, headers, opts) do
      {:ok, client} ->
        client

      {:error, %Response{status_code: code, headers: headers, body: body}} ->
        raise %Error{
          reason: """
          Server responded with status: #{code}

          Headers:

          #{Enum.reduce(headers, "", fn {k, v}, acc -> acc <> "#{k}: #{v}\n" end)}
          Body:

          #{inspect(body)}
          """
        }

      {:error, error} ->
        raise error
    end
  end

  def get_token_dup(%{token_method: method} = client, params \\ [], headers \\ [], opts \\ []) do
    {client, url} = token_url(client, params, headers)

    client = delete_header(client, "authorization")

    case Request.request(method, client, url, client.params, client.headers, opts) do
      {:ok, response} ->
        token = AccessToken.new(response.body)
        {:ok, %{client | headers: [], params: %{}, token: token}}

      {:error, error} ->
        {:error, error}
    end
  end

  defp to_url(%Client{token_method: :post} = client, :token_url) do
    {client, endpoint(client, client.token_url)}
  end

  defp to_url(client, endpoint) do
    endpoint = Map.get(client, endpoint)
    url = endpoint(client, endpoint) <> "?" <> URI.encode_query(client.params)
    {client, url}
  end

  defp token_url(client, params, headers) do
    client
    |> token_post_header()
    |> client.strategy.get_token(params, headers)
    |> to_url(:token_url)
  end

  defp token_post_header(%Client{token_method: :post} = client) do
    client
    |> put_header("content-type", "application/x-www-form-urlencoded")
    |> put_header("accept", "application/json")
  end

  defp token_post_header(%Client{} = client), do: client

  defp endpoint(client, <<"/"::utf8, _::binary>> = endpoint),
    do: client.site <> endpoint

  defp endpoint(_client, endpoint), do: endpoint

  defp delete_header(%{headers: headers} = client, key) do
    %{client | headers: List.keydelete(headers, "#{key}", 0)}
  end

  defp random_state(len \\ 8) do
    symbols =
            [?0..?9, ?a..?z, ?A..?Z]
            |> Enum.map(&Enum.to_list/1)
            |> Enum.concat()
            |> Enum.filter(fn char -> char not in '1lI0O' end)

    symbols_count = Enum.count(symbols)

    for _ <- 1..len, into: "", do: <<Enum.at(symbols, Enum.random(0..(symbols_count - 1)))>>
  end
end
