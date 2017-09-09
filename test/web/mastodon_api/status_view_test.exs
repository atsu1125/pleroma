defmodule Pleroma.Web.MastodonAPI.StatusViewTest do
  use Pleroma.DataCase

  alias Pleroma.Web.MastodonAPI.{StatusView, AccountView}
  alias Pleroma.User
  alias Pleroma.Web.OStatus
  import Pleroma.Factory

  test "a note activity" do
    note = insert(:note_activity)
    user = User.get_cached_by_ap_id(note.data["actor"])

    status = StatusView.render("status.json", %{activity: note})

    expected = %{
      id: note.id,
      uri: note.data["object"]["id"],
      url: note.data["object"]["external_id"],
      account: AccountView.render("account.json", %{user: user}),
      in_reply_to_id: nil,
      in_reply_to_account_id: nil,
      reblog: nil,
      content: HtmlSanitizeEx.basic_html(note.data["object"]["content"]),
      created_at: note.data["object"]["published"],
      reblogs_count: 0,
      favourites_count: 0,
      reblogged: false,
      favourited: false,
      muted: false,
      sensitive: false,
      spoiler_text: "",
      visibility: "public",
      media_attachments: [],
      mentions: [],
      tags: [],
      application: nil,
      language: nil
    }

    assert status == expected
  end

  test "contains mentions" do
    incoming = File.read!("test/fixtures/incoming_reply_mastodon.xml")
    user = insert(:user, %{ap_id: "https://pleroma.soykaf.com/users/lain"})

    {:ok, [activity]} = OStatus.handle_incoming(incoming)

    status = StatusView.render("status.json", %{activity: activity})

    assert status.mentions == [AccountView.render("mention.json", %{user: user})]
  end
end
