defmodule TemplatePhoenix.AuthMarkersTest do
  @moduledoc false
  use ExUnit.Case, async: true

  @roots ~w(lib test config priv assets/js assets/test bin .github)
  @single_files ~w(mix.exs README.md AGENTS.md)

  test "auth markers are balanced and never nested in every file" do
    for path <- marker_candidate_files() do
      content = File.read!(path)

      depth =
        content
        |> String.split("\n")
        |> Enum.reduce(0, fn line, depth ->
          cond do
            String.contains?(line, "auth:begin") ->
              assert depth == 0, "#{path}: nested auth:begin"
              1

            String.contains?(line, "auth:end") ->
              assert depth == 1, "#{path}: auth:end without auth:begin"
              0

            true ->
              depth
          end
        end)

      assert depth == 0, "#{path}: unterminated auth:begin"
    end
  end

  test "the removal script's MARKED_FILES matches the files that carry markers" do
    script = File.read!("bin/remove-auth.sh")

    # A regex split on `MARKED_FILES=\(|^\)$` is brittle here: DELETE_PATHS=(
    # is declared first and closes with its own "^)$" line, so the naive
    # split grabs the gap between DELETE_PATHS's close and MARKED_FILES=(
    # instead of the MARKED_FILES body. Scan lines directly instead.
    marked_block =
      script
      |> String.split("\n")
      |> Enum.drop_while(&(&1 != "MARKED_FILES=("))
      |> Enum.drop(1)
      |> Enum.take_while(&(&1 != ")"))
      |> Enum.join("\n")

    script_files =
      ~r/"([^"]+)"/
      |> Regex.scan(marked_block, capture: :all_but_first)
      |> List.flatten()
      |> Enum.map(&String.replace(&1, "${APP}", "template_phoenix"))
      |> Enum.map(&String.replace(&1, "$APP", "template_phoenix"))
      |> MapSet.new()

    actual_files =
      marker_candidate_files()
      |> Enum.filter(fn path ->
        path not in ["bin/remove-auth.sh", "bin/test-remove-auth.sh"] and
          File.read!(path) =~ "auth:begin"
      end)
      |> MapSet.new()

    assert MapSet.equal?(script_files, actual_files),
           "MARKED_FILES drift.\nOnly in script: #{inspect(MapSet.difference(script_files, actual_files) |> Enum.sort())}\n" <>
             "Only on disk: #{inspect(MapSet.difference(actual_files, script_files) |> Enum.sort())}"
  end

  @spec marker_candidate_files() :: [Path.t()]
  defp marker_candidate_files do
    # This test's own source necessarily contains the literal substrings
    # "auth:begin"/"auth:end" (in the String.contains?/2 calls and assertion
    # messages above), which would trip the balance check against itself.
    this_file = Path.absname(__ENV__.file)

    # bin/remove-auth.sh (and bin/test-remove-auth.sh, added alongside it)
    # implement the marker stripping/removal logic itself, so their source
    # necessarily contains the literal tokens (grep patterns, awk scripts,
    # comments) without those being real marked regions.
    excluded_scripts = ~w(bin/remove-auth.sh bin/test-remove-auth.sh)

    files =
      @roots
      |> Enum.flat_map(&Path.wildcard("#{&1}/**/*", match_dot: true))
      |> Enum.filter(&File.regular?/1)
      |> Enum.reject(
        # priv/static is esbuild/tailwind's gitignored build output; it
        # mirrors assets/js/app.js's marked regions but isn't source.
        &(Path.extname(&1) in ~w(.beam .gz .png .ico .svg) or
            Path.absname(&1) == this_file or
            &1 in excluded_scripts or
            String.starts_with?(&1, "priv/static/"))
      )

    files ++ Enum.filter(@single_files, &File.regular?/1)
  end
end
