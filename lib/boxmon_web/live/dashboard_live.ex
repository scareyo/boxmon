defmodule BoxmonWeb.DashboardLive do
  use BoxmonWeb, :live_view

  alias Boxmon.Monitor

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Monitor.subscribe()
    {:ok, assign(socket, snap: Monitor.snapshot())}
  end

  @impl true
  def handle_info({:monitor, snap}, socket), do: {:noreply, assign(socket, snap: snap)}

  @impl true
  def handle_event("poll", _params, socket) do
    Monitor.poll_now()
    {:noreply, socket}
  end

  def handle_event("retry", %{"hash" => hash}, socket) do
    Monitor.retry(hash)
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="flex items-end justify-between gap-4">
        <div>
          <h1 class="text-2xl font-semibold tracking-tight">Torrents</h1>
          <p class="text-sm opacity-60">
            <%= if @snap.polled_at do %>
              Last checked {Calendar.strftime(@snap.polled_at, "%H:%M:%S")} UTC
            <% else %>
              Not checked yet
            <% end %>
          </p>
        </div>
        <button
          id="poll-now"
          phx-click="poll"
          class="inline-flex items-center gap-1.5 rounded-lg border border-base-300 px-3 py-1.5 text-sm font-medium transition hover:bg-base-200 active:scale-95"
        >
          <.icon name="hero-arrow-path" class="size-4 phx-click-loading:animate-spin" /> Check now
        </button>
      </div>

      <div
        :if={@snap.error}
        id="seedbox-error"
        class="flex items-start gap-2 rounded-lg border border-error/30 bg-error/10 px-4 py-3 text-sm text-error"
      >
        <.icon name="hero-exclamation-triangle" class="mt-0.5 size-4 shrink-0" />
        <span>Can't reach the seedbox: {@snap.error}</span>
      </div>

      <ul id="torrents" class="divide-y divide-base-300 rounded-xl border border-base-300">
        <li :if={@snap.torrents == []} class="px-4 py-10 text-center text-sm opacity-60">
          No torrents on the seedbox.
        </li>
        <li
          :for={t <- @snap.torrents}
          id={"torrent-#{t.hash}"}
          class="space-y-2 px-4 py-3 transition hover:bg-base-200/50"
        >
          <div class="flex items-center justify-between gap-3">
            <p class="truncate font-medium" title={t.name}>{t.name}</p>
            <.badge status={Map.get(@snap.status, t.hash)} torrent={t} />
          </div>

          <.bar
            label="Seedbox"
            value={t.progress}
            class={if(t.progress == 1, do: "bg-success", else: "bg-info")}
          />
          <.bar
            :if={Map.get(@snap.status, t.hash) == :downloading}
            label="Local"
            value={Map.get(@snap.progress, t.hash, 0) / max(t.size, 1)}
            class="bg-primary"
          />

          <%= case Map.get(@snap.status, t.hash) do %>
            <% {:failed, reason} -> %>
              <div class="flex items-center justify-between gap-3 text-sm">
                <span class="truncate text-error" title={reason}>{reason}</span>
                <button
                  id={"retry-#{t.hash}"}
                  phx-click="retry"
                  phx-value-hash={t.hash}
                  class="shrink-0 rounded-md px-2 py-1 font-medium text-primary transition hover:bg-primary/10"
                >
                  Retry
                </button>
              </div>
            <% _ -> %>
          <% end %>

          <p class="text-xs opacity-60">{format_size(t.size)} · {t.state}</p>
        </li>
      </ul>
    </Layouts.app>
    """
  end

  attr :status, :any, required: true
  attr :torrent, :map, required: true

  defp badge(assigns) do
    {text, class} =
      case assigns.status do
        :done -> {"Downloaded", "bg-success/15 text-success"}
        :downloading -> {"Downloading", "bg-primary/15 text-primary"}
        {:failed, _} -> {"Failed", "bg-error/15 text-error"}
        nil when assigns.torrent.progress == 1 -> {"Queued", "bg-base-300"}
        nil -> {"On seedbox", "bg-base-300 opacity-70"}
      end

    assigns = assign(assigns, text: text, class: class)

    ~H"""
    <span class={["shrink-0 rounded-full px-2.5 py-0.5 text-xs font-medium", @class]}>{@text}</span>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :class, :string, required: true

  defp bar(assigns) do
    assigns = assign(assigns, :pct, min(round(assigns.value * 100), 100))

    ~H"""
    <div class="flex items-center gap-3 text-xs">
      <span class="w-14 opacity-60">{@label}</span>
      <div class="h-1.5 flex-1 overflow-hidden rounded-full bg-base-300">
        <div
          class={["h-full rounded-full transition-all duration-500", @class]}
          style={"width: #{@pct}%"}
        />
      </div>
      <span class="w-10 text-right tabular-nums">{@pct}%</span>
    </div>
    """
  end

  defp format_size(bytes) do
    cond do
      bytes >= 1_000_000_000 -> "#{Float.round(bytes / 1_000_000_000, 2)} GB"
      bytes >= 1_000_000 -> "#{Float.round(bytes / 1_000_000, 1)} MB"
      bytes >= 1_000 -> "#{Float.round(bytes / 1_000, 1)} KB"
      true -> "#{bytes} B"
    end
  end
end
