defmodule Boxmon.DownloaderTest do
  use ExUnit.Case, async: false

  alias Boxmon.{Downloader, FakeSeedbox}

  @moduletag :tmp_dir

  @torrent %{hash: "h1", name: "My Show", save_path: "/data/"}
  @files [%{name: "My Show/ep 1.mkv", size: 5}, %{name: "My Show/ep2.mkv", size: 3}]

  setup %{tmp_dir: dir} do
    FakeSeedbox.put_download_dir(dir)
  end

  test "downloads every file to the same relative path", %{tmp_dir: dir} do
    FakeSeedbox.stub(
      content: %{"/dl/My%20Show/ep%201.mkv" => "hello", "/dl/My%20Show/ep2.mkv" => "abc"}
    )

    assert :ok = Downloader.download(@torrent, @files, &send(self(), {:bytes, &1}))
    assert File.read!(Path.join(dir, "My Show/ep 1.mkv")) == "hello"
    assert File.read!(Path.join(dir, "My Show/ep2.mkv")) == "abc"
    assert_received {:bytes, 5}
    assert_received {:bytes, 3}
  end

  test "skips files already on disk", %{tmp_dir: dir} do
    FakeSeedbox.stub(content: %{})
    File.mkdir_p!(Path.join(dir, "My Show"))
    File.write!(Path.join(dir, "My Show/ep 1.mkv"), "hello")
    File.write!(Path.join(dir, "My Show/ep2.mkv"), "abc")

    assert :ok = Downloader.download(@torrent, @files, fn _ -> :ok end)
  end

  test "fails on HTTP errors and leaves no final file", %{tmp_dir: dir} do
    FakeSeedbox.stub(content: %{})

    assert {:error, "ep 1.mkv: HTTP 404"} = Downloader.download(@torrent, @files, fn _ -> :ok end)
    refute File.exists?(Path.join(dir, "My Show/ep 1.mkv"))
  end

  test "rejects files outside the remote root" do
    torrent = %{@torrent | save_path: "/elsewhere"}
    assert {:error, _} = Downloader.download(torrent, @files, fn _ -> :ok end)

    torrent = %{@torrent | save_path: "/data/../etc"}
    assert {:error, _} = Downloader.download(torrent, @files, fn _ -> :ok end)
  end
end
