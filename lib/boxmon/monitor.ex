defmodule Boxmon.Monitor do
  @moduledoc """
  Polls qBittorrent and downloads completed torrents, one at a time.

  All state lives here and is broadcast to `subscribe/0`rs as
  `{:monitor, snapshot}` whenever it changes.
  """
  use GenServer
  require Logger

  alias Boxmon.{Downloader, Qbit}

  @interval :timer.seconds(30)
  @topic "monitor"

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  def subscribe, do: Phoenix.PubSub.subscribe(Boxmon.PubSub, @topic)
  def snapshot, do: GenServer.call(__MODULE__, :snapshot)
  def poll_now, do: send(__MODULE__, :poll)
  def retry(hash), do: GenServer.cast(__MODULE__, {:retry, hash})

  @impl true
  def init(nil) do
    send(self(), :poll)

    {:ok,
     %{
       sid: nil,
       timer: nil,
       current: nil,
       broadcast_at: 0,
       # what the UI sees:
       torrents: [],
       status: %{},
       progress: %{},
       error: nil,
       polled_at: nil
     }}
  end

  @impl true
  def handle_call(:snapshot, _from, state), do: {:reply, snapshot(state), state}

  @impl true
  def handle_cast({:retry, hash}, state) do
    state = %{state | status: Map.delete(state.status, hash)}
    {:noreply, state |> maybe_start_download() |> broadcast()}
  end

  @impl true
  def handle_info(:poll, state) do
    if state.timer, do: Process.cancel_timer(state.timer)
    state = %{state | timer: Process.send_after(self(), :poll, @interval)}

    state =
      case fetch_torrents(state.sid) do
        {:ok, sid, torrents} ->
          %{state | sid: sid, torrents: torrents, error: nil, polled_at: DateTime.utc_now()}

        {:error, reason} ->
          Logger.warning("Polling qBittorrent failed: #{reason}")
          %{state | sid: nil, error: reason}
      end

    {:noreply, state |> maybe_start_download() |> broadcast()}
  end

  def handle_info({:progress, hash, bytes}, state) do
    state = %{state | progress: Map.update(state.progress, hash, bytes, &(&1 + bytes))}

    # Progress arrives per chunk, so only tell the UI about once a second.
    if System.monotonic_time(:millisecond) - state.broadcast_at >= 1000 do
      {:noreply, broadcast(state)}
    else
      {:noreply, state}
    end
  end

  def handle_info({ref, result}, %{current: {hash, ref}} = state) do
    Process.demonitor(ref, [:flush])

    status =
      case result do
        :ok ->
          :done

        {:error, reason} ->
          Logger.warning("Download of #{hash} failed: #{reason}")
          {:failed, reason}
      end

    finish(state, hash, status)
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %{current: {hash, ref}} = state) do
    Logger.error("Download of #{hash} crashed: #{inspect(reason)}")
    finish(state, hash, {:failed, "crashed: #{inspect(reason)}"})
  end

  defp finish(state, hash, status) do
    state = %{state | current: nil, status: Map.put(state.status, hash, status)}
    {:noreply, state |> maybe_start_download() |> broadcast()}
  end

  # Logs in when there's no session, or once more if the session expired.
  defp fetch_torrents(nil) do
    with {:ok, sid} <- Qbit.login(),
         {:ok, torrents} <- Qbit.torrents(sid) do
      {:ok, sid, torrents}
    end
  end

  defp fetch_torrents(sid) do
    case Qbit.torrents(sid) do
      {:ok, torrents} -> {:ok, sid, torrents}
      {:error, _} -> fetch_torrents(nil)
    end
  end

  defp maybe_start_download(%{current: nil, sid: sid} = state) when sid != nil do
    case Enum.find(
           state.torrents,
           &(&1.progress == 1 and not Map.has_key?(state.status, &1.hash))
         ) do
      nil ->
        state

      torrent ->
        monitor = self()

        task =
          Task.Supervisor.async_nolink(Boxmon.TaskSup, fn ->
            with {:ok, files} <- Qbit.files(sid, torrent.hash) do
              Downloader.download(torrent, files, &send(monitor, {:progress, torrent.hash, &1}))
            end
          end)

        %{
          state
          | current: {torrent.hash, task.ref},
            status: Map.put(state.status, torrent.hash, :downloading),
            progress: Map.put(state.progress, torrent.hash, 0)
        }
    end
  end

  defp maybe_start_download(state), do: state

  defp broadcast(state) do
    Phoenix.PubSub.broadcast(Boxmon.PubSub, @topic, {:monitor, snapshot(state)})
    %{state | broadcast_at: System.monotonic_time(:millisecond)}
  end

  defp snapshot(state), do: Map.take(state, [:torrents, :status, :progress, :error, :polled_at])
end
