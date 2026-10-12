defmodule BoxmonWeb.PageController do
  use BoxmonWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
