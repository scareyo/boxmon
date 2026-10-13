defmodule Boxmon.MonitorTest do
  use ExUnit.Case, async: false

  alias Boxmon.{FakeSeedbox, Monitor}

  @moduletag :tmp_dir
  @moduletag :capture_log

  setup :set_req_test_to_shared

  setup %{tmp_dir: dir} do
    FakeSeedbox.put_download_dir(dir)
    Monitor.subscribe()
    :ok
  end

  defp torrent(hash, progress) do
    %{
      "hash" => hash,
      "name" => hash,
      "size" => 2,
      "progress" => progress,
      "state" => "uploading",
      "save_path" => "/data"
    }
  end

  test "downloads completed torrents and leaves incomplete ones", %{tmp_dir: dir} do
    FakeSeedbox.stub(
      torrents: [torrent("partial", 0.5), torrent("done", 1)],
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
      torrents: [torrent("bad", 1)],
      files: %{"bad" => [%{"name" => "missing.txt", "size" => 2, "priority" => 1}]}
    )

    start_supervised!(Monitor)
    assert_receive {:monitor, %{status: %{"bad" => {:failed, "missing.txt: HTTP 404"}}}}

    Monitor.retry("bad")
    assert_receive {:monitor, %{status: %{"bad" => :downloading}}}
    assert_receive {:monitor, %{status: %{"bad" => {:failed, _}}}}
  end

  test "shows an error when qBittorrent is unreachable" do
    Req.Test.stub(Boxmon.Seedbox, &Req.Test.transport_error(&1, :econnrefused))

    start_supervised!(Monitor)
    assert_receive {:monitor, %{error: error}} when is_binary(error)
  end

  defp set_req_test_to_shared(context), do: Req.Test.set_req_test_to_shared(context)
end
