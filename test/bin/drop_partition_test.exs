defmodule TemplatePhoenix.DropPartitionScriptTest do
  # A stub `mise` first on PATH records its arguments instead of running
  # anything, so these tests never invoke a real `mix ecto.drop` — even if
  # the script's guard regressed.
  use ExUnit.Case, async: true

  @moduletag :tmp_dir

  @script Path.expand("../../bin/drop-partition.sh", __DIR__)

  setup %{tmp_dir: tmp_dir} do
    log = Path.join(tmp_dir, "mise.log")
    stub = Path.join(tmp_dir, "mise")

    File.write!(stub, """
    #!/usr/bin/env bash
    printf '%s\\n' "$*" >> "#{log}"
    """)

    File.chmod!(stub, 0o755)

    %{log: log, path: tmp_dir <> ":" <> System.get_env("PATH")}
  end

  describe "valid partitions" do
    for partition <- ["my_branch", "_123_bug_fix_x7k"] do
      test "drops exactly the dev and test databases for #{partition}", ctx do
        {_output, status} = run_script([unquote(partition)], ctx)

        assert status == 0

        assert File.read!(ctx.log) == """
               exec -- env MIX_ENV=dev DB_PARTITION=#{unquote(partition)} mix ecto.drop
               exec -- env MIX_ENV=test MIX_TEST_PARTITION=#{unquote(partition)} mix ecto.drop
               """
      end
    end
  end

  describe "refusals" do
    for {label, args} <- [
          {"no argument", []},
          {"an empty name (would target the shared databases)", [""]},
          {"a path-like name", ["../evil"]},
          {"uppercase and dashes", ["My-Branch"]},
          {"more than one argument", ["one", "two"]}
        ] do
      test "rejects #{label} without running anything", ctx do
        {output, status} = run_script(unquote(args), ctx)

        assert status == 1
        assert output =~ "Usage: bin/drop-partition.sh <partition>"
        refute File.exists?(ctx.log)
      end
    end

    for database <- ["template_phoenix_dev_my_branch", "template_phoenix_test_my_branch"] do
      test "rejects the full database name #{database}", ctx do
        {output, status} = run_script([unquote(database)], ctx)

        assert status == 1
        assert output =~ "full database name"
        assert output =~ "e.g. my_branch"
        refute File.exists?(ctx.log)
      end
    end
  end

  @spec run_script([String.t()], map()) :: {String.t(), non_neg_integer()}
  defp run_script(args, %{path: path}) do
    System.cmd(@script, args, env: [{"PATH", path}], stderr_to_stdout: true)
  end
end
