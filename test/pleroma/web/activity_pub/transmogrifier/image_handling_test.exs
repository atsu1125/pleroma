# Pleroma: A lightweight social networking server
# Copyright © 2017-2021 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.Transmogrifier.ImageHandlingTest do
  use Oban.Testing, repo: Pleroma.Repo
  use Pleroma.DataCase

  alias Pleroma.Activity
  alias Pleroma.Object
  alias Pleroma.Object.Fetcher
  alias Pleroma.Web.ActivityPub.Transmogrifier

  test "Zap Image object" do
    Tesla.Mock.mock(fn
      %{url: "https://p3.macgirvin.com/channel/otest"} ->
        %Tesla.Env{
          status: 200,
          body:
            File.read!("test/fixtures/tesla_mock/https___p3.macgirvin.com_channel_otest.json"),
          headers: HttpRequestMock.activitypub_object_headers()
        }
    end)

    data = File.read!("test/fixtures/tesla_mock/zap-create-image.json") |> Poison.decode!()

    {:ok, %Activity{local: false} = activity} = Transmogrifier.handle_incoming(data)

    assert object = Object.normalize(activity, false)

    assert object.data["to"] == ["https://www.w3.org/ns/activitystreams#Public"]

    assert object.data["cc"] == ["https://p3.macgirvin.com/followers/otest"]

    assert object.data["url"] ==
             "https://p3.macgirvin.com/photos/otest/image/cf7b64a3-8a90-4414-87bc-4d5a8cb0c313"

    assert object.data["attachment"] == [
             %{
               "mediaType" => "image/jpeg",
               "type" => "Link",
               "name" => nil,
               "blurhash" => nil,
               "url" => [
                 %{
                   "href" =>
                     "https://p3.macgirvin.com/photo/cf7b64a3-8a90-4414-87bc-4d5a8cb0c313-0.jpg",
                   "mediaType" => "image/jpeg",
                   "type" => "Link"
                 }
               ]
             }
           ]
  end

  test "Hubzilla Image object" do
    Tesla.Mock.mock(fn
      %{url: "https://hub.netzgemeinde.eu/item/340631d2-d1c2-4ac4-97e9-a9620f850f9b"} ->
        %Tesla.Env{
          status: 200,
          body: File.read!("test/fixtures/tesla_mock/hubzilla-image.json"),
          headers: HttpRequestMock.activitypub_object_headers()
        }

      %{url: "https://hub.netzgemeinde.eu/channel/emaxmax"} ->
        %Tesla.Env{
          status: 200,
          body:
            File.read!("test/fixtures/tesla_mock/https__hub.netzgemeinde.eu_channel_emaxmax.json"),
          headers: HttpRequestMock.activitypub_object_headers()
        }
    end)

    {:ok, object} =
      Fetcher.fetch_object_from_id(
        "https://hub.netzgemeinde.eu/item/340631d2-d1c2-4ac4-97e9-a9620f850f9b"
      )

    assert object.data["to"] == ["https://www.w3.org/ns/activitystreams#Public"]

    assert object.data["cc"] == ["https://hub.netzgemeinde.eu/followers/emaxmax"]

    assert object.data["attachment"] == [
             %{
               "mediaType" => "text/html",
               "type" => "Link",
               "name" => nil,
               "blurhash" => nil,
               "url" => [
                 %{
                   "href" =>
                     "https://hub.netzgemeinde.eu/photo/25f94d19-f1ef-4a00-8c21-c1aebf74c9d8-0.png",
                   "mediaType" => "text/html",
                   "type" => "Link"
                 }
               ]
             }
           ]
  end
end
