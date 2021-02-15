# Pleroma: A lightweight social networking server
# Copyright © 2017-2021 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Upload.Filter.Heif do
  @behaviour Pleroma.Upload.Filter
  alias Pleroma.Upload

  @type conversion :: action :: String.t() | {action :: String.t(), opts :: String.t()}
  @type conversions :: conversion() | [conversion()]

  @spec filter(Pleroma.Upload.t()) :: {:ok, :atom} | {:error, String.t()}
  def filter(
        %Pleroma.Upload{name: name, path: path, tempfile: tempfile, content_type: "image/heic"} =
          upload
      ) do
    try do
      name = name |> String.replace_suffix(".heic", ".jpg")
      path = path |> String.replace_suffix(".heic", ".jpg")
      convert(tempfile)

      {:ok, :filtered, %Upload{upload | name: name, path: path, content_type: "image/jpeg"}}
    rescue
      e in ErlangError ->
        {:error, "mogrify error: #{inspect(e)}"}
    end
  end

  def filter(_), do: {:ok, :noop}

  def convert(tempfile) do
    # cannot save in place when changing format, so we have to use a tmp file
    # https://github.com/route/mogrify/issues/77
    # also need a valid extension or it gets confused

    original = tempfile <> ".heic"
    File.rename!(tempfile, original)

    %{path: converted} =
      original
      |> Mogrify.open()
      |> Mogrify.format("jpg")
      |> Mogrify.save()

    File.rename!(converted, tempfile)
  end
end