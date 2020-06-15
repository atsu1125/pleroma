# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

# Code based on CreateChatMessageValidator
# NOTES
# - Can probably be a generic create validator
# - doesn't embed, will only get the object id
defmodule Pleroma.Web.ActivityPub.ObjectValidators.CreateQuestionValidator do
  use Ecto.Schema

  alias Pleroma.Object
  alias Pleroma.Web.ActivityPub.ObjectValidators.Types

  import Ecto.Changeset
  import Pleroma.Web.ActivityPub.ObjectValidators.CommonValidations

  @primary_key false

  embedded_schema do
    field(:id, Types.ObjectID, primary_key: true)
    field(:actor, Types.ObjectID)
    field(:type, :string)
    field(:to, Types.Recipients, default: [])
    field(:cc, Types.Recipients, default: [])
    field(:object, Types.ObjectID)
  end

  def cast_and_apply(data) do
    data
    |> cast_data
    |> apply_action(:insert)
  end

  def cast_data(data) do
    cast(%__MODULE__{}, data, __schema__(:fields))
  end

  def cast_and_validate(data, meta \\ []) do
    cast_data(data)
    |> validate_data(meta)
  end

  def validate_data(cng, meta \\ []) do
    cng
    |> validate_required([:actor, :type, :object])
    |> validate_inclusion(:type, ["Create"])
    |> validate_actor_presence()
    |> validate_any_presence([:to, :cc])
    |> validate_actors_match(meta)
    |> validate_object_nonexistence()
  end

  def validate_object_nonexistence(cng) do
    cng
    |> validate_change(:object, fn :object, object_id ->
      if Object.get_cached_by_ap_id(object_id) do
        [{:object, "The object to create already exists"}]
      else
        []
      end
    end)
  end

  def validate_actors_match(cng, meta) do
    object_actor = meta[:object_data]["actor"]

    cng
    |> validate_change(:actor, fn :actor, actor ->
      if actor == object_actor do
        []
      else
        [{:actor, "Actor doesn't match with object actor"}]
      end
    end)
  end
end
