defmodule Boxmon.Qbit do
  @moduledoc """
  Minimal qBittorrent WebUI API v2 client.
  """

  def login do
    config = config()

    case Req.post(req(config),
           url: "/api/v2/auth/login",
           form: [username: config[:qbit_user], password: config[:qbit_pass]]
         ) do
      {:ok, %{status: 200, body: "Ok."} = resp} ->
        case Regex.run(~r/SID=([^;]+)/, Enum.join(Req.Response.get_header(resp, "set-cookie"))) do
          [_, sid] -> {:ok, sid}
          nil -> {:error, "qBittorrent login returned no SID cookie"}
        end

      {:ok, %{status: 200}} ->
        {:error, "qBittorrent login failed: bad credentials"}

      {:ok, resp} ->
        {:error, "qBittorrent login failed: HTTP #{resp.status}"}

      {:error, exception} ->
        {:error, "qBittorrent: #{Exception.message(exception)}"}
    end
  end

  def torrents(sid) do
    with {:ok, torrents} <- get(sid, "/api/v2/torrents/info", []) do
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

  def files(sid, hash) do
    with {:ok, files} <- get(sid, "/api/v2/torrents/files", hash: hash) do
      # Priority 0 means "do not download", so the file won't exist on the seedbox.
      {:ok,
       for f <- files, f["priority"] != 0 do
         %{name: f["name"], size: f["size"]}
       end}
    end
  end

  # qBittorrent answers 403 when the SID has expired.
  defp get(sid, url, params) do
    case Req.get(req(config()), url: url, params: params, headers: [cookie: "SID=#{sid}"]) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: 403}} -> {:error, :forbidden}
      {:ok, resp} -> {:error, "qBittorrent #{url}: HTTP #{resp.status}"}
      {:error, exception} -> {:error, "qBittorrent: #{Exception.message(exception)}"}
    end
  end

  defp req(config) do
    Req.new(base_url: config[:qbit_url])
    |> Req.merge(Keyword.get(config, :req_options, []))
  end

  defp config, do: Application.fetch_env!(:boxmon, :seedbox)
end
