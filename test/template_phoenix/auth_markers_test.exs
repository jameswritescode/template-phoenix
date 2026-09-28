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

  @spec marker_candidate_files() :: [Path.t()]
  defp marker_candidate_files do
    # This test's own source necessarily contains the literal substrings
    # "auth:begin"/"auth:end" (in the String.contains?/2 calls and assertion
    # messages above), which would trip the balance check against itself.
    this_file = Path.absname(__ENV__.file)

    files =
      @roots
      |> Enum.flat_map(&Path.wildcard("#{&1}/**/*", match_dot: true))
      |> Enum.filter(&File.regular?/1)
      |> Enum.reject(&(Path.extname(&1) in ~w(.beam .gz .png .ico .svg)))
      |> Enum.reject(&(Path.absname(&1) == this_file))

    files ++ Enum.filter(@single_files, &File.regular?/1)
  end
end
