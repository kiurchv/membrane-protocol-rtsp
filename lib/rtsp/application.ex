defmodule Membrane.Protocol.RTSP.Application do
  @moduledoc false
  use Application

  alias Membrane.Protocol.RTSP

  def start(_type, _args) do
    children = [
      %{
        id: TransportRegistry,
        start: {Registry, :start_link, [:unique, TransportRegistry]}
      },
      %{
        id: RTSP.Supervisor,
        start: {RTSP.Supervisor, :start_link, []}
      }
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
