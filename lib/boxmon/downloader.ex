defmodule Boxmon.Downloader do
  @moduledoc """
  Downloads a torrent's files from the seedbox's HTTP server.

  A torrent file at `<save_path>/<name>` on the seedbox is fetched from
  `<http_url>/<path relative to remote_root>` and saved under `download_dir`
  at that same relative path. Files that already exist locally with the
  right size are skipped, so the local disk is the record of what's done.
  """

  @doc """
  Downloads every file, calling `on_progress.(bytes)` as bytes arrive.
  """
  def download(torrent, files, on_progress) do
    Enum.reduce_while(files, :ok, fn file, :ok ->
      case download_file(torrent, file, on_progress) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp download_file(torrent, file, on_progress) do
    config = config()

    with {:ok, rel} <- relative_path(Path.join(torrent.save_path, file.name), config) do
      dest = Path.join(config[:download_dir], rel)

      if already_downloaded?(dest, file.size) do
        on_progress.(file.size)
        :ok
      else
        fetch(url(rel, config), dest, file.size, on_progress)
      end
    end
  end

  defp fetch(url, dest, size, on_progress) do
    part = dest <> ".part"
    File.mkdir_p!(Path.dirname(dest))

    result =
      File.open!(part, [:write, :binary], fn io ->
        Req.get(req(),
          url: url,
          into: fn {:data, data}, {req, resp} ->
            if resp.status == 200 do
              IO.binwrite(io, data)
              on_progress.(byte_size(data))
              {:cont, {req, resp}}
            else
              {:halt, {req, resp}}
            end
          end
        )
      end)

    case result do
      {:ok, %{status: 200}} ->
        case File.stat!(part).size do
          ^size -> File.rename!(part, dest)
          got -> {:error, "#{Path.basename(dest)}: expected #{size} bytes, got #{got}"}
        end

      {:ok, resp} ->
        {:error, "#{Path.basename(dest)}: HTTP #{resp.status}"}

      {:error, exception} ->
        {:error, "#{Path.basename(dest)}: #{Exception.message(exception)}"}
    end
  end

  defp already_downloaded?(path, size) do
    match?({:ok, %{size: ^size}}, File.stat(path))
  end

  defp relative_path(remote_path, config) do
    rel = Path.relative_to(remote_path, config[:remote_root])

    if Path.type(rel) == :relative and ".." not in Path.split(rel) do
      {:ok, rel}
    else
      {:error, "#{remote_path} is not inside REMOTE_ROOT (#{config[:remote_root]})"}
    end
  end

  defp url(rel, config) do
    encoded =
      rel
      |> Path.split()
      |> Enum.map_join("/", &URI.encode(&1, fn c -> URI.char_unreserved?(c) end))

    String.trim_trailing(config[:http_url], "/") <> "/" <> encoded
  end

  defp req do
    config = config()

    Req.new(auth: {:basic, "#{config[:http_user]}:#{config[:http_pass]}"}, retry: false)
    |> Req.merge(config[:req_options] || [])
  end

  defp config, do: Application.fetch_env!(:boxmon, :seedbox)
end
