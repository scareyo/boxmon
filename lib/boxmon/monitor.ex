defmodule Boxmon.Monitor do
  @moduledoc """
  Polls qBittorrent and downloads completed torrents, one at a time.

  All state lives here and is broadcast to `subscribe/0`rs as
  `{:monitor, snapshot}` whenever it changes. HTTP work runs in tasks so
  `snapshot/0` never waits on a slow seedbox.
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
       timer: nil,
       polling: nil,
       current: nil,
       broadcast_at: 0,
       broadcast_bytes: 0,
       # what the UI sees:
       torrents: [],
       status: %{},
       bytes: 0,
       speed: 0,
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
  def handle_info(:poll, %{polling: nil} = state) do
    if state.timer, do: Process.cancel_timer(state.timer)
    task = Task.Supervisor.async_nolink(Boxmon.TaskSup, &Qbit.torrents/0)
    {:noreply, %{state | timer: nil, polling: task.ref}}
  end

  def handle_info(:poll, state), do: {:noreply, state}

  def handle_info({ref, result}, %{polling: ref} = state) do
    Process.demonitor(ref, [:flush])
    polled(state, result)
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %{polling: ref} = state) do
    polled(state, {:error, "poll crashed: #{inspect(reason)}"})
  end

  def handle_info({:progress, bytes}, state) do
    state = %{state | bytes: state.bytes + bytes}
    elapsed = System.monotonic_time(:millisecond) - state.broadcast_at

    # Progress arrives per chunk, so only tell the UI about once a second.
    if elapsed >= 1000 do
      speed = div((state.bytes - state.broadcast_bytes) * 1000, elapsed)
      {:noreply, broadcast(%{state | speed: speed})}
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

  defp polled(state, result) do
    state = %{state | polling: nil, timer: Process.send_after(self(), :poll, @interval)}

    state =
      case result do
        {:ok, torrents} ->
          %{state | torrents: torrents, error: nil, polled_at: DateTime.utc_now()}

        {:error, reason} ->
          Logger.warning("Polling qBittorrent failed: #{reason}")
          %{state | error: reason}
      end

    {:noreply, state |> maybe_start_download() |> broadcast()}
  end

  defp finish(state, hash, status) do
    state = %{state | current: nil, status: Map.put(state.status, hash, status)}
    {:noreply, state |> maybe_start_download() |> broadcast()}
  end

  defp maybe_start_download(%{current: nil, error: nil} = state) do
    case next_torrent(state) do
      nil ->
        state

      torrent ->
        monitor = self()

        task =
          Task.Supervisor.async_nolink(Boxmon.TaskSup, fn ->
            with {:ok, files} <- Qbit.files(torrent.hash) do
              Downloader.download(torrent, files, &send(monitor, {:progress, &1}))
            end
          end)

        %{
          state
          | current: {torrent.hash, task.ref},
            status: Map.put(state.status, torrent.hash, :downloading),
            bytes: 0,
            speed: 0
        }
    end
  end

  defp maybe_start_download(state), do: state

  defp next_torrent(state) do
    Enum.find(state.torrents, &(&1.progress == 1 and not Map.has_key?(state.status, &1.hash)))
  end

  defp broadcast(state) do
    Phoenix.PubSub.broadcast(Boxmon.PubSub, @topic, {:monitor, snapshot(state)})
    %{state | broadcast_at: System.monotonic_time(:millisecond), broadcast_bytes: state.bytes}
  end

  defp snapshot(state),
    do: Map.take(state, [:torrents, :status, :bytes, :speed, :error, :polled_at])
end
