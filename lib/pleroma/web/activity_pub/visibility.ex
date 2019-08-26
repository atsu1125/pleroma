# Pleroma: A lightweight social networking server
# Copyright © 2017-2019 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.Visibility do
  alias Pleroma.Activity
  alias Pleroma.Object
  alias Pleroma.User

  require Pleroma.Constants

  @spec is_public?(Object.t() | Activity.t() | map()) :: boolean()
  def is_public?(%Object{data: %{"type" => "Tombstone"}}), do: false
  def is_public?(%Object{data: data}), do: is_public?(data)
  def is_public?(%Activity{data: data}), do: is_public?(data)
  def is_public?(%{"directMessage" => true}), do: false
  def is_public?(%{"to" => to} = data), do: Pleroma.Constants.as_public() in (to ++ (data["cc"] || []))
  def is_public?(%{"type" => "Create"}), do: false
  def is_public?(%{"type" => _}), do: true
  def is_public?(_), do: false

  def is_private?(activity) do
    with false <- is_public?(activity),
         %User{follower_address: follower_address} <-
           User.get_cached_by_ap_id(activity.data["actor"]) do
      follower_address in activity.data["to"]
    else
      _ -> false
    end
  end

  def is_direct?(%Activity{data: %{"directMessage" => true}}), do: true
  def is_direct?(%Object{data: %{"directMessage" => true}}), do: true

  def is_direct?(activity) do
    !is_public?(activity) && !is_private?(activity)
  end

  def is_list?(%{data: %{"listMessage" => _}}), do: true
  def is_list?(_), do: false

  def visible_for_user?(%{actor: ap_id}, %User{ap_id: ap_id}), do: true

  def visible_for_user?(%{data: %{"listMessage" => list_ap_id}} = activity, %User{} = user) do
    user.ap_id in activity.data["to"] ||
      list_ap_id
      |> Pleroma.List.get_by_ap_id()
      |> Pleroma.List.member?(user)
  end

  def visible_for_user?(%{data: %{"listMessage" => _}}, nil), do: false

  def visible_for_user?(activity, nil) do
    is_public?(activity)
  end

  def visible_for_user?(activity, user) do
    x = [user.ap_id | user.following]
    y = [activity.actor] ++ activity.recipients
    visible_for_user?(activity, nil) || Enum.any?(x, &(&1 in y))
  end

  # XXX: Probably even more inefficient than the previous implementation intended to be a placeholder untill https://git.pleroma.social/pleroma/pleroma/merge_requests/971 is in develop
  # credo:disable-for-previous-line Credo.Check.Readability.MaxLineLength
  def entire_thread_visible_for_user?(
        %Activity{} = tail,
        # %Activity{data: %{"object" => %{"inReplyTo" => parent_id}}} = tail,
        user
      ) do
    case Object.normalize(tail) do
      %{data: %{"inReplyTo" => parent_id}} when is_binary(parent_id) ->
        parent = Activity.get_in_reply_to_activity(tail)
        visible_for_user?(tail, user) && entire_thread_visible_for_user?(parent, user)

      _ ->
        visible_for_user?(tail, user)
    end
  end

  def get_visibility(object) do
    to = object.data["to"] || []
    cc = object.data["cc"] || []

    cond do
      Pleroma.Constants.as_public() in to ->
        "public"

      Pleroma.Constants.as_public() in cc ->
        "unlisted"

      # this should use the sql for the object's activity
      Enum.any?(to, &String.contains?(&1, "/followers")) ->
        "private"

      object.data["directMessage"] == true ->
        "direct"

      is_binary(object.data["listMessage"]) ->
        "list"

      length(cc) > 0 ->
        "private"

      true ->
        "direct"
    end
  end
end
