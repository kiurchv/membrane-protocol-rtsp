defmodule Membrane.Protocol.RTSP.Session.Manager do
  @moduledoc false
  use GenServer

  alias Membrane.Protocol.RTSP.{Request, Response, Transport}

  @user_agent "MembraneRTSP/#{Mix.Project.config()[:version]} (Membrane Framework RTSP Client)"

  defmodule State do
    @moduledoc false
    @enforce_keys [:transport, :uri]
    defstruct @enforce_keys ++ [:session_id, cseq: 0, execution_options: []]

    @type t :: %__MODULE__{
            transport: Transport.t(),
            cseq: non_neg_integer(),
            uri: URI.t(),
            session_id: binary() | nil,
            execution_options: Keyword.t()
          }
  end

  @doc """
  Starts and links session process.

  Sets following properties of Session:
    * transport - information for executing request over the network. For
    reference see `Membrane.Protocol.RTSP.Transport`
    * url - a base path for requests
    * options - a keyword list that shall be passed when executing request over
    transport
  """
  @spec start_link(Transport.t(), binary(), Keyword.t()) :: GenServer.on_start()
  def start_link(transport, url, options) do
    GenServer.start_link(__MODULE__, %{
      transport: transport,
      url: url,
      options: options
    })
  end

  @spec request(pid(), Request.t(), non_neg_integer()) :: {:ok, Response.t()} | {:error, atom()}
  def request(session, request, timeout \\ 5000) do
    GenServer.call(session, {:execute, request}, timeout)
  end

  @impl true
  def init(%{transport: transport, url: url, options: options}) do
    state = %State{
      transport: transport,
      uri: url,
      execution_options: options
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:execute, request}, _from, %State{cseq: cseq} = state) do
    with {:ok, raw_response} <- execute(request, state),
         {:ok, parsed_response} <- Response.parse(raw_response),
         {:ok, state} <- handle_session_id(parsed_response, state) do
      state = %State{state | cseq: cseq + 1}
      {:reply, {:ok, parsed_response}, state}
    else
      {:error, _} = error -> {:reply, error, state}
    end
  end

  defp execute(request, state) do
    %State{cseq: cseq, transport: transport, uri: uri, execution_options: options} = state

    request
    |> Request.with_header("CSeq", cseq |> to_string())
    |> Request.with_header("User-Agent", @user_agent)
    |> apply_credentials(uri)
    |> Request.stringify(uri)
    |> transport.module.execute(transport.key, options)
  end

  defp apply_credentials(request, %URI{userinfo: nil}), do: request

  defp apply_credentials(%Request{headers: headers} = request, %URI{userinfo: info}) do
    case List.keyfind(headers, "Authorization", 0) do
      {"Authorization", _} ->
        request

      _ ->
        encoded = Base.encode64(info)
        Request.with_header(request, "Authorization", "Basic " <> encoded)
    end
  end

  # Some responses do not have to return the Session ID
  # If it does return one, it needs to match one stored in the state.
  defp handle_session_id(%Response{} = response, state) do
    with {:ok, session_value} <- Response.get_header(response, "Session") do
      [session_id | _] = String.split(session_value, ";")

      case state do
        %State{session_id: nil} -> {:ok, %State{state | session_id: session_id}}
        %State{session_id: ^session_id} -> {:ok, state}
        _ -> {:error, :invalid_session_id}
      end
    else
      {:error, :no_such_header} -> {:ok, state}
    end
  end
end
