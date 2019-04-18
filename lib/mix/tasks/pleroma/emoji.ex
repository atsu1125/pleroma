# Pleroma: A lightweight social networking server
# Copyright © 2017-2018 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Mix.Tasks.Pleroma.Emoji do
  use Mix.Task

  @shortdoc "Manages Pleroma instance"
  @moduledoc """
  """

  @default_manifest "https://git.pleroma.social/vaartis/emoji-index/raw/master/index.json"

  def run(["ls-packs" | args]) do
    Application.ensure_all_started(:hackney)

    {options, [], []} = parse_global_opts(args)

    manifest =
      fetch_manifest(if options[:manifest], do: options[:manifest], else: @default_manifest)

    Enum.each(manifest, fn {name, info} ->
      to_print = [
        {"Name", name},
        {"Homepage", info["homepage"]},
        {"Description", info["description"]},
        {"License", info["license"]},
        {"Source", info["src"]}
      ]

      for {param, value} <- to_print do
        IO.puts(IO.ANSI.format([:bright, param, :normal, ": ", value]))
      end
    end)
  end

  def run(["get-packs" | args]) do
    Application.ensure_all_started(:hackney)

    {options, pack_names, []} = parse_global_opts(args)

    manifest_url = if options[:manifest], do: options[:manifest], else: @default_manifest

    manifest = fetch_manifest(manifest_url)

    for pack_name <- pack_names do
      if Map.has_key?(manifest, pack_name) do
        pack = manifest[pack_name]
        src_url = pack["src"]

        IO.puts(
          IO.ANSI.format([
            "Downloading ",
            :bright,
            pack_name,
            :normal,
            " from ",
            :underline,
            src_url
          ])
        )

        binary_archive = Tesla.get!(src_url).body
        archive_md5 = :crypto.hash(:md5, binary_archive) |> Base.encode16()

        md5_status_text = ["MD5 of ", :bright, pack_name, :normal, " source file is ", :bright]
        if archive_md5 == String.upcase(pack["src_md5"]) do
          IO.puts(IO.ANSI.format(md5_status_text ++ [:green, "OK"]))
        else
          IO.puts(IO.ANSI.format(md5_status_text ++ [:red, "BAD"]))

          raise "Bad MD5 for #{pack_name}"
        end

        # The url specified in files should be in the same directory
        files_url = Path.join(Path.dirname(manifest_url), pack["files"])

        IO.puts(
          IO.ANSI.format([
            "Fetching the file list for ",
            :bright,
            pack_name,
            :normal,
            " from ",
            :underline,
            files_url
          ])
        )

        files = Tesla.get!(files_url).body |> Poison.decode!()

        IO.puts(IO.ANSI.format(["Unpacking ", :bright, pack_name]))

        static_path = Path.join(:code.priv_dir(:pleroma), "static")

        pack_path =
          Path.join([
            static_path,
            Pleroma.Config.get!([:instance, :static_dir]),
            "emoji",
            pack_name
          ])

        files_to_unzip =
          Enum.map(
            files,
            fn {_, f} -> to_charlist(f) end
          )

        {:ok, _} =
          :zip.unzip(binary_archive,
            cwd: pack_path,
            file_list: files_to_unzip
          )

        IO.puts(IO.ANSI.format(["Writing emoji.txt for ", :bright, pack_name]))

        common_pack_path = Path.join([
          "/", Pleroma.Config.get!([:instance, :static_dir]), "emoji", pack_name
        ])
        emoji_txt_str =
          Enum.map(
            files,
            fn {shortcode, path} ->
              "#{shortcode}, #{Path.join(common_pack_path, path)}"
            end
          )
          |> Enum.join("\n")

        File.write!(Path.join(pack_path, "emoji.txt"), emoji_txt_str)
      else
        IO.puts(IO.ANSI.format([:bright, :red, "No pack named \"#{pack_name}\" found"]))
      end
    end
  end

  def run(["gen-pack", src]) do
    Application.ensure_all_started(:hackney)

    proposed_name = Path.basename(src) |> Path.rootname()
    name = String.trim(IO.gets("Pack name [#{proposed_name}]: "))
    # If there's no name, use the default one
    name = if String.length(name) > 0, do: name, else: proposed_name

    license = String.trim(IO.gets("License: "))
    homepage = String.trim(IO.gets("Homepage: "))
    description = String.trim(IO.gets("Description: "))

    proposed_files_name = "#{name}.json"
    files_name = String.trim(IO.gets("Save file list to [#{proposed_files_name}]: "))
    files_name = if String.length(files_name) > 0, do: files_name, else: proposed_files_name

    default_exts = [".png", ".gif"]
    default_exts_str = Enum.join(default_exts, " ")
    exts =
      String.trim(IO.gets("Emoji file extensions (separated with spaces) [#{default_exts_str}]: "))
    exts = if String.length(exts) > 0 do
      String.split(exts, " ") |> Enum.filter(fn e -> (e |> String.trim() |> String.length()) > 0 end)
    else
      default_exts
    end

    IO.puts "Downloading the pack and generating MD5"

    binary_archive = Tesla.get!(src).body
    archive_md5 = :crypto.hash(:md5, binary_archive) |> Base.encode16()

    IO.puts "MD5 is #{archive_md5}"

    pack_json = %{
      name => %{
        license: license,
        homepage: homepage,
        description: description,
        src: src,
        src_md5: archive_md5,
        files: files_name
      }
    }

    tmp_pack_dir = Path.join(System.tmp_dir!(), "emoji-pack-#{name}")
    {:ok, _} =
      :zip.unzip(
        binary_archive,
        cwd: tmp_pack_dir
      )

    emoji_map = Pleroma.Emoji.make_shortcode_to_file_map(tmp_pack_dir, exts)


    File.write!(files_name, Poison.encode!(emoji_map, pretty: true))

    IO.puts """

    #{files_name} has been created and contains the list of all found emojis in the pack.
    Please review the files in the remove those not needed.
    """

    if File.exists?("index.json") do
      existing_data = File.read!("index.json") |> Poison.decode!()

      File.write!(
        "index.json",
        Poison.encode!(
          Map.merge(
            existing_data,
            pack_json
          ),
          pretty: true
        )
      )

      IO.puts "index.json file has been update with the #{name} pack"
    else
      File.write!("index.json", Poison.encode!(pack_json, pretty: true))

      IO.puts "index.json has been created with the #{name} pack"
    end

  end

  defp fetch_manifest(from) do
    Tesla.get!(from).body |> Poison.decode!()
  end

  defp parse_global_opts(args) do
    OptionParser.parse(
      args,
      strict: [
        manifest: :string
      ],
      aliases: [
        m: :manifest
      ]
    )
  end
end
