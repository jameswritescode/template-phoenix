defmodule TemplatePhoenix.DropPartitionScriptTest do
  use ExUnit.Case, async: true

  @script Path.expand("../../bin/drop-partition.sh", __DIR__)

  describe "bin/drop-partition.sh refuses anything but one snake_case partition" do
    for {label, args} <- [
          {"no argument", []},
          {"an empty name (would target the shared databases)", [""]},
          {"a path-like name", ["../template_phoenix"]},
          {"uppercase and dashes", ["My-Branch"]},
          {"more than one argument", ["one", "two"]}
        ] do
      test "rejects #{label}" do
        {output, status} = System.cmd(@script, unquote(args), stderr_to_stdout: true)

        assert status == 1
        assert output =~ "Usage: bin/drop-partition.sh <partition>"
        refute output =~ "dropped"
      end
    end
  end
end
