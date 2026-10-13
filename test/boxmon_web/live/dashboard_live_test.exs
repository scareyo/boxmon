defmodule BoxmonWeb.DashboardLiveTest do
  use BoxmonWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Boxmon.{FakeSeedbox, Monitor}

  @moduletag :tmp_dir
  @moduletag :capture_log

  setup {Req.Test, :set_req_test_to_shared}

  setup %{tmp_dir: dir} do
    FakeSeedbox.put_download_dir(dir)

    FakeSeedbox.stub(
      torrents: [
        FakeSeedbox.torrent("abc", 1)
      ],
      files: %{"abc" => [%{"name" => "show.mkv", "size" => 2, "priority" => 1}]}
    )

    Monitor.subscribe()
    start_supervised!(Monitor)
    assert_receive {:monitor, %{status: %{"abc" => {:failed, _}}}}
    :ok
  end

  test "lists torrents with a retry button for failures", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#torrent-abc")
    assert has_element?(view, "#retry-abc")

    view |> element("#retry-abc") |> render_click()
    assert_receive {:monitor, %{status: %{"abc" => {:failed, _}}}}
    assert has_element?(view, "#retry-abc")
  end

  test "can poll on demand", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view |> element("#poll-now") |> render_click()
    assert_receive {:monitor, %{polled_at: %DateTime{}}}
    assert has_element?(view, "#torrent-abc")
  end
end
