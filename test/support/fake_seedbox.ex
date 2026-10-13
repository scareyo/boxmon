defmodule Boxmon.FakeSeedbox do
  @moduledoc """
  Stubs qBittorrent and the seedbox file server with `Req.Test`.

  Options:
    * `:torrents` - qBittorrent `/torrents/info` JSON
    * `:files` - map of hash => qBittorrent `/torrents/files` JSON
    * `:content` - map of encoded request path => file body
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
      "save_path" => "/data"
    }
  end

  @doc "Points downloads at `dir` for the rest of the test."
  def put_download_dir(dir) do
    config = Application.fetch_env!(:boxmon, :seedbox)
    Application.put_env(:boxmon, :seedbox, Keyword.put(config, :download_dir, dir))
    ExUnit.Callbacks.on_exit(fn -> Application.put_env(:boxmon, :seedbox, config) end)
  end

  defp handle(%{request_path: "/api/v2/auth/login"} = conn, _opts) do
    conn
    |> put_resp_header("set-cookie", "SID=abc123; HttpOnly; path=/")
    |> send_resp(200, "Ok.")
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
      body -> send_resp(conn, 200, body)
    end
  end
end
