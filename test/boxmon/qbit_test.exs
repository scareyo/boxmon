defmodule Boxmon.QbitTest do
  use ExUnit.Case, async: false

  alias Boxmon.{FakeSeedbox, Qbit}

  test "lists torrents and the files to download" do
    FakeSeedbox.stub(
      torrents: [FakeSeedbox.torrent("h1", 1)],
      files: %{
        "h1" => [
          %{"name" => "h1/a.mkv", "size" => 2, "priority" => 1},
          %{"name" => "h1/skip.nfo", "size" => 3, "priority" => 0}
        ]
      }
    )

    assert {:ok, [%{hash: "h1", progress: 1, save_path: "/data"}]} = Qbit.torrents()
    assert {:ok, [%{name: "h1/a.mkv", size: 2}]} = Qbit.files("h1")
  end

  test "only lists torrents in the configured categories" do
    FakeSeedbox.stub(
      torrents: [
        FakeSeedbox.torrent("h1", 1),
        %{FakeSeedbox.torrent("h2", 1) | "category" => "movies"},
        %{FakeSeedbox.torrent("h3", 1) | "category" => ""}
      ]
    )

    assert {:ok, [%{hash: "h1"}]} = Qbit.torrents()

    FakeSeedbox.put_config(:categories, [])
    assert {:ok, []} = Qbit.torrents()
  end

  test "sends the API key as a bearer token" do
    Req.Test.stub(Boxmon.Seedbox, fn conn ->
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer qbt_test"]
      Req.Test.json(conn, [])
    end)

    assert {:ok, []} = Qbit.torrents()
  end

  test "reports auth failures and other HTTP errors" do
    for status <- [401, 403] do
      Req.Test.stub(Boxmon.Seedbox, &Plug.Conn.send_resp(&1, status, "Forbidden"))
      assert {:error, :unauthorized} = Qbit.torrents()
    end

    Req.Test.stub(Boxmon.Seedbox, &Plug.Conn.send_resp(&1, 500, "oops"))
    assert {:error, "qBittorrent /api/v2/torrents/info: HTTP 500"} = Qbit.torrents()
  end
end
