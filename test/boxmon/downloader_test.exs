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

    test_pid = self()
    assert :ok = Downloader.download(@torrent, @files, &send(test_pid, {:bytes, &1}))
    assert File.read!(Path.join(dir, "My Show/ep 1.mkv")) == "hello"
    assert File.read!(Path.join(dir, "My Show/ep2.mkv")) == "abc"
    assert received_bytes() == 8
  end

  # chunk_size is 4 in test, so these 26 bytes arrive as 7 parallel ranges.
  test "assembles large files from parallel ranged chunks", %{tmp_dir: dir} do
    body = "abcdefghijklmnopqrstuvwxyz"
    FakeSeedbox.stub(content: %{"/dl/big.bin" => body})

    assert :ok = Downloader.download(@torrent, [%{name: "big.bin", size: 26}], fn _ -> :ok end)
    assert File.read!(Path.join(dir, "big.bin")) == body
  end

  test "streams the whole file when the server doesn't support ranges", %{tmp_dir: dir} do
    body = "abcdefghijklmnopqrstuvwxyz"
    FakeSeedbox.stub(content: %{"/dl/big.bin" => body}, ranges: false)

    assert :ok = Downloader.download(@torrent, [%{name: "big.bin", size: 26}], fn _ -> :ok end)
    assert File.read!(Path.join(dir, "big.bin")) == body
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

  defp received_bytes(total \\ 0) do
    receive do
      {:bytes, n} -> received_bytes(total + n)
    after
      0 -> total
    end
  end
end
