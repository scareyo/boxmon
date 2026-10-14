defmodule Boxmon.FakeSeedbox do
  @moduledoc """
  Stubs qBittorrent and the seedbox file server with `Req.Test`.

  Options:
    * `:torrents` - qBittorrent `/torrents/info` JSON
    * `:files` - map of hash => qBittorrent `/torrents/files` JSON
    * `:content` - map of encoded request path => file body
    * `:ranges` - whether the file server supports byte ranges (default true)
  """
  import Plug.Conn

  def stub(opts) do
    Req.Test.stub(Boxmon.Seedbox, &handle(&1, opts))
  end

  @doc "A qBittorrent `/torrents/info` entry."
  def torrent(hash, progress) do
    %{
      "hash" => hash,
      "name" => hash,
      "size" => 2,
      "progress" => progress,
      "state" => "uploading",
      "save_path" => "/data",
      "category" => "tv"
    }
  end

  @doc "Overrides a `:seedbox` config key for the rest of the test."
  def put_config(key, value) do
    config = Application.fetch_env!(:boxmon, :seedbox)
    Application.put_env(:boxmon, :seedbox, Keyword.put(config, key, value))
    ExUnit.Callbacks.on_exit(fn -> Application.put_env(:boxmon, :seedbox, config) end)
  end

  defp handle(%{request_path: "/api/v2/torrents/info"} = conn, opts) do
    Req.Test.json(conn, Keyword.get(opts, :torrents, []))
  end

  defp handle(%{request_path: "/api/v2/torrents/files"} = conn, opts) do
    conn = fetch_query_params(conn)
    Req.Test.json(conn, Map.get(Keyword.get(opts, :files, %{}), conn.query_params["hash"], []))
  end

  defp handle(conn, opts) do
    case Map.get(Keyword.get(opts, :content, %{}), conn.request_path) do
      nil -> send_resp(conn, 404, "not found")
      body -> serve(conn, body, Keyword.get(opts, :ranges, true))
    end
  end

  defp serve(%{method: "HEAD"} = conn, _body, ranges) do
    conn
    |> put_resp_header("accept-ranges", if(ranges, do: "bytes", else: "none"))
    |> send_resp(200, "")
  end

  defp serve(conn, body, true) do
    case get_req_header(conn, "range") do
      ["bytes=" <> range] ->
        [from, to] = range |> String.split("-") |> Enum.map(&String.to_integer/1)
        send_resp(conn, 206, binary_part(body, from, to - from + 1))

      [] ->
        send_resp(conn, 200, body)
    end
  end

  defp serve(conn, body, false), do: send_resp(conn, 200, body)
end
