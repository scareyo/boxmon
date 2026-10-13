defmodule Boxmon.Downloader do
  @moduledoc """
  Downloads a torrent's files from the seedbox's HTTP server.

  A torrent file at `<save_path>/<name>` on the seedbox is fetched from
  `<http_url>/<path relative to remote_root>` and saved under `download_dir`
  at that same relative path. Files that already exist locally with the
  right size are skipped, so the local disk is the record of what's done.

  When the server supports byte ranges, large files are fetched in chunks
  over several parallel connections.
  """

  @chunk_size 16 * 1024 * 1024
  @connections 4

  @doc """
  Downloads every file, calling `on_progress.(bytes)` as bytes arrive.
  """
  def download(torrent, files, on_progress) do
    config = config()

    Enum.reduce_while(files, :ok, fn file, :ok ->
      case download_file(torrent, file, config, on_progress) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp download_file(torrent, file, config, on_progress) do
    with {:ok, rel} <- relative_path(Path.join(torrent.save_path, file.name), config) do
      dest = Path.join(config[:download_dir], rel)

      if already_downloaded?(dest, file.size) do
        on_progress.(file.size)
        :ok
      else
        fetch(
          req(config),
          url(rel, config),
          dest,
          file.size,
          Keyword.get(config, :chunk_size, @chunk_size),
          on_progress
        )
      end
    end
  end

  defp fetch(req, url, dest, size, chunk_size, on_progress) do
    part = dest <> ".part"
    File.mkdir_p!(Path.dirname(dest))
    File.write!(part, "")

    result =
      if size > chunk_size and ranges?(req, url) do
        fetch_chunks(req, url, part, size, chunk_size, on_progress)
      else
        fetch_range(req, url, part, nil, on_progress)
      end

    with :ok <- result,
         %{size: ^size} <- File.stat!(part) do
      File.rename!(part, dest)
    else
      {:error, reason} -> {:error, "#{Path.basename(dest)}: #{reason}"}
      %{size: got} -> {:error, "#{Path.basename(dest)}: expected #{size} bytes, got #{got}"}
    end
  end

  defp ranges?(req, url) do
    case Req.head(req, url: url) do
      {:ok, %{status: 200} = resp} -> Req.Response.get_header(resp, "accept-ranges") == ["bytes"]
      _ -> false
    end
  end

  # Fetches `chunk_size` ranges over @connections parallel connections,
  # each writing its range at the right offset in the .part file.
  defp fetch_chunks(req, url, part, size, chunk_size, on_progress) do
    0..(size - 1)//chunk_size
    |> Task.async_stream(
      fn from ->
        fetch_range(req, url, part, {from, min(from + chunk_size, size) - 1}, on_progress)
      end,
      max_concurrency: @connections,
      ordered: false,
      timeout: :infinity
    )
    |> Enum.find_value(:ok, fn {:ok, result} -> if result != :ok, do: result end)
  end

  # Streams the whole file (range nil) or one {from, to} byte range into `part`.
  defp fetch_range(req, url, part, range, on_progress) do
    {headers, offset, expected_status} =
      case range do
        nil -> {[], 0, 200}
        {from, to} -> {[range: "bytes=#{from}-#{to}"], from, 206}
      end

    result =
      File.open!(part, [:read, :write, :binary], fn io ->
        {:ok, _} = :file.position(io, offset)

        Req.get(req,
          url: url,
          headers: headers,
          into: fn {:data, data}, {req, resp} ->
            if resp.status == expected_status do
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
      {:ok, %{status: ^expected_status}} -> :ok
      {:ok, resp} -> {:error, "HTTP #{resp.status}"}
      {:error, exception} -> {:error, Exception.message(exception)}
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
      |> Enum.map_join("/", fn segment -> URI.encode(segment, &URI.char_unreserved?/1) end)

    String.trim_trailing(config[:http_url], "/") <> "/" <> encoded
  end

  # No retries: a retry would append the body to the .part file a second time.
  defp req(config) do
    Req.new(auth: {:basic, "#{config[:http_user]}:#{config[:http_pass]}"}, retry: false)
    |> Req.merge(Keyword.get(config, :req_options, []))
  end

  defp config, do: Application.fetch_env!(:boxmon, :seedbox)
end
