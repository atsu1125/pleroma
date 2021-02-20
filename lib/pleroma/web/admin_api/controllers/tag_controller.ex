# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.AdminAPI.TagController do
  use Pleroma.Web, :controller

  import Pleroma.Web.ControllerHelper, only: [json_response: 3]

  alias Pleroma.ModerationLog
  alias Pleroma.User
  alias Pleroma.Web.AdminAPI
  alias Pleroma.Web.ApiSpec
  alias Pleroma.Web.Plugs.OAuthScopesPlug

  plug(
    OAuthScopesPlug,
    %{scopes: ["admin:write:accounts"]} when action in [:update, :append, :delete]
  )

  plug(
    OAuthScopesPlug,
    %{scopes: ["admin:read:accounts"]} when action == :index
  )

  plug(ApiSpec.CastAndValidate)

  action_fallback(AdminAPI.FallbackController)

  defdelegate open_api_operation(action), to: ApiSpec.Admin.TagOperation

  def index(%{assigns: %{user: _admin}} = conn, _) do
    tags = Pleroma.Tag.list_tags()

    json(conn, tags)
  end

  def update(conn, params), do: append(conn, params)

  def append(
        %{assigns: %{user: admin}, body_params: %{nicknames: nicknames, tags: tags}} = conn,
        _
      ) do
    with {:ok, _} <- User.tag(nicknames, tags) do
      ModerationLog.insert_log(%{
        actor: admin,
        nicknames: nicknames,
        tags: tags,
        action: "tag"
      })

      json_response(conn, :no_content, "")
    end
  end

  def delete(
        %{assigns: %{user: admin}, body_params: %{nicknames: nicknames, tags: tags}} = conn,
        _
      ) do
    with {:ok, _} <- User.untag(nicknames, tags) do
      ModerationLog.insert_log(%{
        actor: admin,
        nicknames: nicknames,
        tags: tags,
        action: "untag"
      })

      json_response(conn, :no_content, "")
    end
  end
end
