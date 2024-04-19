Mix.install([
  {:req, "~> 0.4.0"}
])

defmodule RicohGR.CameraFile do
  defstruct [:dir, :file]

  alias __MODULE__

  def filetype(%CameraFile{file: file}) do
    cond do
      String.ends_with?(file, ".JPG") -> :jpg
      String.ends_with?(file, ".DNG") -> :dng
      String.ends_with?(file, ".MOV") -> :mov
    end
  end

  def path(%CameraFile{dir: dir, file: file}), do: Path.join(dir, file)
end

defmodule RicohGR.Api do
  defstruct [:_base_req]

  alias RicohGR.Api
  alias RicohGR.CameraFile

  def new() do
    %Api{_base_req: Req.new(base_url: "http://192.168.0.1/v1")}
  end

  def list_all_photos!(%Api{} = api) do
    collect_all_photos(api, nil, [])
  end

  defp collect_all_photos(api, last_image, result) do
    case api |> list_photos!(after: last_image) do
      [] ->
        List.flatten(result)

      list ->
        api
        |> collect_all_photos(
          list
          |> Enum.max_by(&CameraFile.path(&1))
          |> RicohGR.CameraFile.path(),
          [result | list]
        )
    end
  end

  def list_photos!(%Api{} = api, opts \\ []) do
    params =
      Enum.reduce(opts, [], fn
        {:limit, q_limit}, params -> [{:limit, q_limit} | params]
        {:after, nil}, params -> params
        {:after, q_after}, params -> [{:after, q_after} | params]
        invalid, _params -> raise "Invalid option: #{invalid}"
      end)

    %{status: 200, body: body} = api._base_req |> Req.get!(url: "/photos", params: params)

    %{"errCode" => 200, "dirs" => dirs} = body

    for %{"files" => files, "name" => dir} <- dirs,
        file <- files do
      %CameraFile{dir: dir, file: file}
    end
  end

  def download_photo(%Api{} = api, %CameraFile{} = camerafile, size) do
    photo_url = "/photos/#{camerafile.dir}/#{camerafile.file}"

    params =
      case size do
        :full -> []
        :view -> [size: "view"]
        :thumb -> [size: "thumb"]
        :xs -> [size: "xs"]
      end

    case Req.get(api._base_req, url: photo_url, params: params) do
      {:ok, response} ->
        case response do
          %{status: 200, body: %{"errCode" => _errCode, "errMsg" => errMsg}} ->
            {:error, errMsg}

          %{status: 200, body: data} when is_binary(data) ->
            {:ok, data}

          _ ->
            {:error, "Unexpected response"}
        end

      err ->
        IO.puts("ERROR: #{inspect(err)}")
        {:error, inspect(err)}
    end
  end
end

defmodule Main do
  alias RicohGR.Api
  alias RicohGR.CameraFile

  def sync_all_photos(out_dir, include_filetypes, size) do
    api = Api.new()

    Api.list_all_photos!(api)
    |> Enum.filter(&(include_filetypes == :all or CameraFile.filetype(&1) in include_filetypes))
    |> Enum.reject(&File.exists?(Path.join(out_dir, CameraFile.path(&1))))
    |> Enum.sort_by(& &1.file, :desc)
    |> Stream.each(fn camerafile ->
      IO.inspect([CameraFile.filetype(camerafile), size])
      localfile = Path.join(out_dir, CameraFile.path(camerafile))
      IO.puts("Downloading #{camerafile.dir}/#{camerafile.file} to #{localfile}")

      case Api.download_photo(api, camerafile, size) do
        {:ok, data} ->
          File.mkdir_p!(Path.dirname(localfile))
          File.write!(localfile, data)

        {:error, err} ->
          IO.puts("ERROR: #{err}")
      end
    end)
    |> Stream.run()
  end
end

Main.sync_all_photos(Path.expand("~/.cache/grsync/thumbs"), :all, :thumb)
Main.sync_all_photos(Path.expand("~/.cache/grsync/previews"), :all, :view)
Main.sync_all_photos(Path.expand("~/RicohGRIII"), :all, :full)
