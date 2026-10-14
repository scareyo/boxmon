defmodule Boxmon.Qbit do
  @moduledoc """
  Minimal qBittorrent WebUI API v2 client, authenticated with an API key
  (qBittorrent 5.2+, generated under Options → WebUI).
  """

  def torrents do
    with {:ok, torrents} <- get("/api/v2/torrents/info", []) do
      {:ok,
       Enum.map(torrents, fn t ->
         %{
           hash: t["hash"],
           name: t["name"],
           size: t["size"],
           progress: t["progress"],
           state: t["state"],
           save_path: t["save_path"]
         }
       end)}
    end
  end

  def files(hash) do
    with {:ok, files} <- get("/api/v2/torrents/files", hash: hash) do
      # Priority 0 means "do not download", so the file won't exist on the seedbox.
      {:ok,
       for f <- files, f["priority"] != 0 do
         %{name: f["name"], size: f["size"]}
       end}
    end
  end

  # 401/403 means a bad API key. Callers must not keep retrying those: qBittorrent
  # bans the IP after a few failed auth attempts.
  defp get(url, params) do
    case Req.get(req(), url: url, params: params) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status}} when status in [401, 403] -> {:error, :unauthorized}
      {:ok, resp} -> {:error, "qBittorrent #{url}: HTTP #{resp.status}"}
      {:error, exception} -> {:error, "qBittorrent: #{Exception.message(exception)}"}
    end
  end

  defp req do
    config = Application.fetch_env!(:boxmon, :seedbox)

    Req.new(base_url: config[:qbit_url], auth: {:bearer, config[:qbit_api_key]})
    |> Req.merge(Keyword.get(config, :req_options, []))
  end
end
