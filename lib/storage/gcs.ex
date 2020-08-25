defmodule ExTus.Storage.Gcp do
  use ExTus.Storage
  alias ExTus.UploadCache
  alias Goth.Token

  def filename(file_name) do
    base_name = Path.basename(file_name, Path.extname(file_name))
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    "#{base_name}_#{timestamp}"
  end

  def initiate_file(%{file_name: file_name} = info) do
    body = %{name: "#{base_dir()}/#{info.path}/#{filename(file_name)}"}
    name = URI.encode("#{base_dir()}/#{info.path}/#{filename(file_name)}")
    # meta = [{:name, name}, {:body, %{size: chunk_size()}}]
    {:ok, token} = Token.for_scope("https://www.googleapis.com/auth/cloud-platform")

    headers = [
      {"Authorization", "Bearer #{token.token}"},
      {"Content-Type", "application/json; charset=UTF-8"},
      {"X-Upload-Content-Length", info.upload_length}
    ]

    upload =
      HTTPoison.post(
        "https://storage.googleapis.com/upload/storage/v1/b/#{bucket}/o?uploadType=resumable&name=#{
          name
        }",
        # Jason.encode!(body),
        "",
        headers,
        []
      )

    # IO.inspect(res, label: "INIT")
    # conn = GoogleApi.Storage.V1.Connection.new(token.token)

    # upload =
    #   GoogleApi.Storage.V1.Api.Objects.storage_objects_insert_resumable(
    #     conn,
    #     bucket(),
    #     "resumable",
    #     meta
    #   )

    IO.inspect(upload, label: "UP")

    case upload do
      {:error, err} ->
        {:error, err}

      {:ok, %{headers: headers}} ->
        h = Enum.into(headers, %{}, fn {k, v} -> {String.to_atom(k), v} end)

        {:ok,
         %{identifier: h[:"X-GUploader-UploadID"], filename: body.name, location: h[:Location]}}
    end
  end

  def put_file(%{filename: _file_path}, _destination) do
  end

  def append_data(%{identifier: upload_id, filename: file, options: opts} = info, data) do
    IO.inspect(byte_size(data), label: "DATA_SIZE")

    range_high =
      if info.offset + byte_size(data) >= info.size do
        info.size
      else
        info.offset + byte_size(data) - 1
      end

    append =
      HTTPoison.put(
        opts.store_url,
        IO.iodata_to_binary(data),
        [
          {"Content-Length", "#{byte_size(data)}"},
          {"Content-Range", "bytes #{info.offset}-#{range_high}/#{info.size}"}
        ],
        [{:timeout, 50_000}, {:recv_timeout, 50_000}]
      )

    IO.inspect(opts.store_url, label: "STORE")
    IO.inspect(append, label: "APPEND")

    case append do
      {:ok, %{headers: headers, status_code: code} = res} ->
        h = Enum.into(headers, %{}, fn {k, v} -> {String.to_atom(String.downcase(k)), v} end)

        case code do
          308 ->
            offset =
              String.split(h[:range], "-")
              |> tl()
              |> hd()
              |> String.to_integer()

            {:ok, Map.merge(info, %{offset: offset + 1})}

          400 ->
            IO.inspect(res, label: "XXXXXXXX")
        end

      # res = Jason.decode!(body)
      # {:ok, Map.merge(info, %{offset: String.to_integer(res["size"])})}

      {:error, err} ->
        {:error, err}
    end
  end

  # {:ok, token} = Token.for_scope("https://www.googleapis.com/auth/cloud-platform")
  # conn = GoogleApi.Storage.V1.Connection.new(token.token)

  # upload =
  #   GoogleApi.Storage.V1.Api.Objects.storage_objects_insert_iodata(
  #     conn,
  #     bucket(),
  #     "multipart",
  #     %{id: upload_id, name: file},
  #     data,
  #     [{:body, %{id: upload_id, name: file}}]
  #   )

  # IO.inspect(upload, label: "UPL")

  # # div(info.offset, 5 * 1024 * 1024) + 1 # 5MB each part
  # part_id = (options[:current_part] || 0) + 1

  # ""
  # |> ExAws.S3.upload_part(file, upload_id, part_id, data, "Content-Length": byte_size(data))
  # |> ExAws.request(host: endpoint(bucket()))
  # |> case do
  #   {:ok, response} ->
  #     %{headers: headers} = response

  #     {_, etag} =
  #       Enum.find(headers, fn {k, _v} ->
  #         String.downcase(k) == "etag"
  #       end)

  #     parts = options[:parts] || []
  #     parts = parts ++ [{part_id, etag}]

  #     info = %{info | options: %{parts: parts, current_part: part_id}}

  #     {:ok, info}

  #   err ->
  #     err
  # end
  # end

  def complete_file(%{filename: file, identifier: upload_id, options: options} = info) do
    IO.inspect(info, label: "COMPL")
    # parts = options[:parts] || []

    # ""
    # |> ExAws.S3.complete_multipart_upload(
    #   file,
    #   upload_id,
    #   Enum.sort_by(parts, &elem(&1, 0))
    # )
    # |> ExAws.request(host: endpoint(bucket()))
  end

  def url(file) do
    Path.join(asset_host(), file)
  end

  def abort_upload(%{identifier: upload_id, filename: file}) do
    # ""
    # |> ExAws.S3.abort_multipart_upload(file, upload_id)
    # |> ExAws.request(host: endpoint(bucket()))
  end

  def delete(file) do
    # ""
    # |> ExAws.S3.delete_object(file)
    # |> ExAws.request(host: endpoint(bucket()))
  end

  defp base_dir() do
    Application.get_env(:extus, :base_dir)
  end

  defp chunk_size do
    Application.get_env(:extus, :gcp, [])
    |> Keyword.get(:chunk_size, 7 * 1024 * 1024)
  end

  defp bucket do
    Application.get_env(:extus, :gcp, [])
    |> Keyword.get(:bucket)
  end

  defp endpoint(bucket) do
    "#{bucket}.s3.amazonaws.com"
  end

  # defp host(bucket) do
  #   case virtual_host() do
  #     true -> "https://#{bucket}.s3.amazonaws.com"
  #     _ -> "https://s3.amazonaws.com/#{bucket}"
  #   end
  # end

  defp asset_host do
    # Application.get_env(:extus, :asset_host, host(bucket()))
  end
end
