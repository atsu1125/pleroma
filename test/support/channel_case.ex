# Pleroma: A lightweight social networking server
# Copyright © 2017-2021 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ChannelCase do
  @moduledoc """
  This module defines the test case to be used by
  channel tests.

  Such tests rely on `Phoenix.ChannelTest` and also
  import other functionality to make it easier
  to build common datastructures and query the data layer.

  Finally, if the test case interacts with the database,
  it cannot be async. For this reason, every test runs
  inside a transaction which is reset at the beginning
  of the test unless the test case is marked as async.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # Import conveniences for testing with channels
      import Phoenix.ChannelTest
      use Pleroma.Tests.Helpers

      # The default endpoint for testing
      @endpoint Pleroma.Web.Endpoint
    end
  end

  setup tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Pleroma.Repo)

    if tags[:async] do
      Mox.stub_with(Pleroma.CachexMock, Pleroma.NullCache)
      Mox.set_mox_private()
    else
      Ecto.Adapters.SQL.Sandbox.mode(Pleroma.Repo, {:shared, self()})
      Mox.stub_with(Pleroma.CachexMock, Pleroma.CachexProxy)
      Mox.set_mox_global()
      Pleroma.DataCase.clear_cachex()
    end

    :ok
  end
end
