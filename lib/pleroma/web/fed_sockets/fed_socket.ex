# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.FedSockets.FedSocket do
  @moduledoc """
  The FedSocket module abstracts the actions to be taken taken on connections regardless of
  whether the connection started as inbound or outbound.


  Normally outside modules will have no need to call the FedSocket module directly.
  """

  alias Pleroma.Object
  alias Pleroma.Object.Containment
  alias Pleroma.User
  alias Pleroma.Web.ActivityPub.ObjectView
  alias Pleroma.Web.ActivityPub.UserView
  alias Pleroma.Web.ActivityPub.Visibility
  alias Pleroma.Web.FedSockets.IngesterWorker
  alias Pleroma.Web.FedSockets.OutgoingHandler
  alias Pleroma.Web.FedSockets.SocketInfo

  require Logger

  @shake "61dd18f7-f1e6-49a4-939a-a749fcdc1103"

  def connect_to_host(uri) do
    case OutgoingHandler.start_link(uri) do
      {:ok, pid} ->
        {:ok, pid}

      error ->
        {:error, error}
    end
  end

  def close(%SocketInfo{pid: socket_pid}),
    do: Process.send(socket_pid, :close, [])

  def publish(%SocketInfo{pid: socket_pid}, json) do
    %{action: :publish, data: json}
    |> Jason.encode!()
    |> send_packet(socket_pid)
  end

  def fetch(%SocketInfo{pid: socket_pid}, data) do
    _timeout = Pleroma.Config.get([:fed_sockets, :fetch_timeout], 12_000)
    OutgoingHandler.fetch(socket_pid, data)
  end

  def receive_package(%SocketInfo{} = fed_socket, json) do
    json
    |> Jason.decode!()
    |> process_package(fed_socket)
  end

  defp process_package(%{"action" => "publish", "data" => data}, %{origin: origin} = _fed_socket) do
    if Containment.contain_origin(origin, data) do
      IngesterWorker.enqueue("ingest", %{"object" => data})
    end

    {:reply, %{"action" => "publish_reply", "status" => "processed"}}
  end

  defp process_package(%{"action" => "fetch", "uuid" => uuid, "data" => ap_id}, _fed_socket) do
    {:ok, data} = render_fetched_data(ap_id, uuid)
    {:reply, data}
  end

  defp process_package(other, _fed_socket) do
    Logger.warn("unknown json packages received #{inspect(other)}")
    {:noreply, nil}
  end

  defp render_fetched_data(ap_id, uuid) do
    {:ok,
     %{
       "action" => "fetch_reply",
       "status" => "processed",
       "uuid" => uuid,
       "data" => represent_item(ap_id)
     }}
  end

  defp represent_item(ap_id) do
    case User.get_by_ap_id(ap_id) do
      nil ->
        object = Object.get_cached_by_ap_id(ap_id)

        if Visibility.is_public?(object) do
          Phoenix.View.render_to_string(ObjectView, "object.json", object: object)
        else
          nil
        end

      user ->
        Phoenix.View.render_to_string(UserView, "user.json", user: user)
    end
  end

  @spec send_packet(binary(), pid()) :: :ok
  def send_packet(data, socket_pid) do
    Process.send(socket_pid, {:send, data}, [])
  end

  def shake, do: @shake
end
