# Pleroma: A lightweight social networking server
# Copyright © 2017-2021 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.InstallerWeb.Forms.ConfigForm do
  use Ecto.Schema

  import Ecto.Changeset

  alias Pleroma.Config
  alias Pleroma.User

  @to_file [
    :endpoint_url_scheme,
    :endpoint_url_host,
    :endpoint_url_port,
    :endpoint_http_ip,
    :endpoint_http_port,
    :endpoint_secret_key_base,
    :endpoint_signing_salt,
    :joken_default_signer,
    :configurable_from_database
  ]

  @primary_key false
  @repo Config.get([:installer, :repo], Pleroma.Installer.InstallerRepo)
  @admin_user_keys [:admin_email, :admin_nickname, :admin_password]

  embedded_schema do
    field(:instance_name)
    field(:instance_email)
    field(:instance_notify_email)
    field(:instance_static_dir, :string)

    field(:endpoint_url)
    field(:endpoint_url_host)
    field(:endpoint_url_port, :integer)
    field(:endpoint_url_scheme, :string)
    field(:endpoint_http_ip)
    field(:endpoint_http_port, :integer)
    field(:endpoint_secret_key_base)
    field(:endpoint_signing_salt)

    field(:local_uploads_dir)

    field(:joken_default_signer)

    field(:web_push_encryption_public_key)
    field(:web_push_encryption_private_key)

    field(:configurable_from_database, :boolean, default: true)
    field(:indexable, :boolean, default: true)

    field(:create_admin_user, :boolean, default: true)
    field(:admin_nickname)
    field(:admin_email)
    field(:admin_password)
  end

  @spec changeset(map()) :: Ecto.Changeset.t()
  def changeset(attrs \\ %{}) do
    keys = [
      :instance_name,
      :instance_email,
      :instance_notify_email,
      :instance_static_dir,
      :endpoint_url,
      :endpoint_http_ip,
      :endpoint_http_port,
      :local_uploads_dir,
      :configurable_from_database,
      :indexable,
      :create_admin_user
    ]

    %__MODULE__{}
    |> cast(
      attrs,
      keys ++ @admin_user_keys
    )
    |> validate_change(:endpoint_url, fn :endpoint_url, url ->
      case URI.parse(url) do
        %{scheme: nil} -> [endpoint_url: "url must have scheme"]
        %{host: nil} -> [endpoint_url: "url bad format"]
        _ -> []
      end
    end)
    |> set_url_fields()
    |> add_endpoint_secret()
    |> add_endpoint_signing_salt()
    |> add_joken_default_signer()
    |> add_web_push_keys()
    |> validate_required(keys)
    |> validate_format(:instance_email, User.email_regex())
    |> validate_format(:instance_notify_email, User.email_regex())
    |> maybe_validate_admin_user_fields()
  end

  defp set_url_fields(%{changes: %{endpoint_url: url}} = changeset) do
    uri = URI.parse(url)

    change(changeset,
      endpoint_url_host: uri.host,
      endpoint_url_port: uri.port,
      endpoint_url_scheme: uri.scheme
    )
  end

  defp set_url_fields(changeset), do: changeset

  defp add_endpoint_secret(changeset) do
    change(changeset, endpoint_secret_key_base: crypt(64))
  end

  defp add_endpoint_signing_salt(changeset) do
    change(changeset, endpoint_signing_salt: crypt(8))
  end

  defp add_joken_default_signer(changeset) do
    change(changeset, joken_default_signer: crypt(64))
  end

  defp crypt(bytes) do
    bytes
    |> :crypto.strong_rand_bytes()
    |> Base.encode64()
    |> binary_part(0, bytes)
  end

  defp add_web_push_keys(changeset) do
    {web_push_public_key, web_push_private_key} = :crypto.generate_key(:ecdh, :prime256v1)

    change(changeset,
      web_push_encryption_public_key: Base.url_encode64(web_push_public_key, padding: false),
      web_push_encryption_private_key: Base.url_encode64(web_push_private_key, padding: false)
    )
  end

  defp maybe_validate_admin_user_fields(%{changes: %{create_admin_user: false}} = changeset) do
    changeset
  end

  defp maybe_validate_admin_user_fields(changeset) do
    changeset
    |> validate_required(@admin_user_keys)
    |> validate_format(:admin_email, User.email_regex())
  end

  @spec save(Ecto.Changeset.t()) ::
          :ok
          | {:error, Ecto.Changeset.t()}
          | {:error, :config_file_not_found}
          | {:error, :file.posix()}
  def save(changeset) do
    with {:ok, struct} <- apply_action(changeset, :insert) do
      # we expect that config file was already created and contains database credentials,
      # so if file doesn't exist we return error
      config_path = Pleroma.Application.config_path()

      if File.exists?(config_path) do
        config =
          struct
          |> Map.from_struct()
          |> Map.to_list()

        with :ok <- do_save(config, config_path) do
          if config[:create_admin_user] do
            # in tests is always started
            if !Process.whereis(Pleroma.Web.Endpoint) do
              {:ok, _} = Pleroma.Web.Endpoint.start_link()
            end

            params = %{
              nickname: config[:admin_nickname],
              email: config[:admin_email],
              password: config[:admin_password],
              password_confirmation: config[:admin_password],
              name: config[:admin_nickname],
              bio: ""
            }

            changeset = User.register_changeset(%User{}, params, need_confirmation: false)

            with {:ok, user} <- User.register(changeset) do
              {:ok, _user} = User.admin_api_update(user, %{is_admin: true})
            end
          end

          generate_robots_txt(config)
        end
      else
        {:error, :config_file_not_found}
      end
    end
  end

  defp do_save(config, config_path) do
    config
    |> save_to_file(config_path)
    |> maybe_save_to_database()
  end

  defp save_to_file(config, config_path) do
    {keys, template} =
      if config[:configurable_from_database] do
        {@to_file, "installer/templates/config_part.eex"}
      else
        keys =
          [
            :local_uploads_dir,
            :web_push_encryption_public_key,
            :web_push_encryption_private_key,
            :instance_name,
            :instance_email,
            :instance_notify_email,
            :instance_static_dir
          ] ++ @to_file

        {keys, "installer/templates/config_full.eex"}
      end

    assigns = Keyword.take(config, keys)

    content = EEx.eval_file(template, assigns)

    file_mod = Config.get([:installer, :file], Pleroma.Installer.File)

    with :ok <- file_mod.write(config_path, ["\n", content], [:append]) do
      config
    end
  end

  defp maybe_save_to_database(config) when is_list(config) do
    if config[:configurable_from_database] do
      web_push = [
        subject: "mailto:" <> config[:instance_email],
        public_key: config[:web_push_encryption_public_key],
        private_key: config[:web_push_encryption_private_key]
      ]

      changes = [
        %{
          group: :pleroma,
          key: :instance,
          value:
            Keyword.take(
              config,
              [:instance_name, :instance_email, :instance_notify_email, :instance_static_dir]
            )
        },
        %{
          group: :web_push_encryption,
          key: :vapid_details,
          value: web_push
        },
        %{
          group: :pleroma,
          key: Pleroma.Uploaders.Local,
          value: [uploads: config[:local_uploads_dir]]
        }
      ]

      config = Config.get(:credentials)

      with {:ok, _} <- @repo.start_repo(config),
           {:ok, _} <- Config.Versioning.new_version(changes) do
        Config.delete(:credentials)
      end
    else
      :ok
    end
  end

  defp maybe_save_to_database(result), do: result

  defp generate_robots_txt(config) do
    templates_dir = Application.app_dir(:pleroma, "priv") <> "/templates"

    Mix.Tasks.Pleroma.Instance.write_robots_txt(
      config[:instance_static_dir],
      config[:indexable],
      templates_dir
    )
  end
end
