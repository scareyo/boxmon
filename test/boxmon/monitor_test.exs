defmodule Boxmon.MonitorTest do
  use ExUnit.Case, async: false

  alias Boxmon.{FakeSeedbox, Monitor}

  @moduletag :tmp_dir
  @moduletag :capture_log

  setup {Req.Test, :set_req_test_to_shared}

  setup %{tmp_dir: dir} do
    FakeSeedbox.put_config(:download_dir, dir)
    Monitor.subscribe()
    :ok
  end

  test "downloads completed torrents and leaves incomplete ones", %{tmp_dir: dir} do
    FakeSeedbox.stub(
      torrents: [FakeSeedbox.torrent("partial", 0.5), FakeSeedbox.torrent("done", 1)],
      files: %{"done" => [%{"name" => "done.txt", "size" => 2, "priority" => 1}]},
      content: %{"/dl/done.txt" => "ok"}
    )

    start_supervised!(Monitor)

    assert_receive {:monitor, %{status: %{"done" => :done} = status}}
    refute Map.has_key?(status, "partial")
    assert File.read!(Path.join(dir, "done.txt")) == "ok"
  end

  test "marks failed downloads and retries on request" do
    FakeSeedbox.stub(
      torrents: [FakeSeedbox.torrent("bad", 1)],
      files: %{"bad" => [%{"name" => "missing.txt", "size" => 2, "priority" => 1}]}
    )

    start_supervised!(Monitor)
    assert_receive {:monitor, %{status: %{"bad" => {:failed, "missing.txt: HTTP 404"}}}}

    Monitor.retry("bad")
    assert_receive {:monitor, %{status: %{"bad" => :downloading}}}
    assert_receive {:monitor, %{status: %{"bad" => {:failed, _}}}}
  end

  test "stops polling after repeated auth failures until checked manually" do
    Req.Test.stub(Boxmon.Seedbox, &Plug.Conn.send_resp(&1, 403, "Forbidden"))
    start_supervised!(Monitor)
    assert_receive {:monitor, %{error: "qBittorrent rejected the API key (attempt 1 of 3)"}}

    Monitor.poll_now()
    assert_receive {:monitor, %{error: "qBittorrent rejected the API key (attempt 2 of 3)"}}

    Monitor.poll_now()
    assert_receive {:monitor, %{error: "qBittorrent rejected the API key 3 times" <> _}}
    assert %{timer: nil, auth_failures: 3} = :sys.get_state(Monitor)

    FakeSeedbox.stub(torrents: [])
    Monitor.poll_now()
    assert_receive {:monitor, %{error: nil}}
    assert %{auth_failures: 0, timer: timer} = :sys.get_state(Monitor)
    assert is_reference(timer)
  end

  test "shows an error when qBittorrent is unreachable" do
    Req.Test.stub(Boxmon.Seedbox, &Req.Test.transport_error(&1, :econnrefused))

    start_supervised!(Monitor)
    assert_receive {:monitor, %{error: error}} when is_binary(error)
  end
end
