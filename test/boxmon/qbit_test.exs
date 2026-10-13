defmodule Boxmon.QbitTest do
  use ExUnit.Case, async: true

  alias Boxmon.{FakeSeedbox, Qbit}

  test "logs in and lists torrents and files" do
    FakeSeedbox.stub(
      torrents: [
        %{
          "hash" => "h1",
          "name" => "Show",
          "size" => 10,
          "progress" => 1,
          "state" => "uploading",
          "save_path" => "/data/"
        }
      ],
      files: %{
        "h1" => [
          %{"name" => "Show/a.mkv", "size" => 10, "priority" => 1},
          %{"name" => "Show/skip.nfo", "size" => 3, "priority" => 0}
        ]
      }
    )

    assert {:ok, "abc123"} = Qbit.login()

    assert {:ok, [%{hash: "h1", name: "Show", progress: 1, save_path: "/data/"}]} =
             Qbit.torrents("abc123")

    assert {:ok, [%{name: "Show/a.mkv", size: 10}]} = Qbit.files("abc123", "h1")
  end

  test "reports bad credentials" do
    Req.Test.stub(Boxmon.Seedbox, &Plug.Conn.send_resp(&1, 200, "Fails."))
    assert {:error, "qBittorrent login failed: bad credentials"} = Qbit.login()
  end

  test "treats 403 as an expired session and reports other HTTP errors" do
    Req.Test.stub(Boxmon.Seedbox, &Plug.Conn.send_resp(&1, 403, "Forbidden"))
    assert {:error, :forbidden} = Qbit.torrents("expired")

    Req.Test.stub(Boxmon.Seedbox, &Plug.Conn.send_resp(&1, 500, "oops"))
    assert {:error, "qBittorrent /api/v2/torrents/info: HTTP 500"} = Qbit.torrents("abc")
  end
end
