defmodule Mix.Tasks.Skills.LinkTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Skills.Link

  @moduletag :tmp_dir

  defp make_skill(source, name) do
    dir = Path.join(source, name)
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "SKILL.md"), "---\nname: #{name}\n---\n")
  end

  setup %{tmp_dir: tmp} do
    source = Path.join(tmp, ".agents/skills")
    target = Path.join(tmp, ".claude/skills")
    File.mkdir_p!(source)
    %{source: source, target: target}
  end

  test "creates relative symlinks for skills with SKILL.md", %{source: source, target: target} do
    make_skill(source, "tophat")
    File.mkdir_p!(Path.join(source, "not-a-skill"))

    assert %{created: ["tophat"], ok: [], pruned: []} = Link.sync(source, target)

    link = Path.join(target, "tophat")
    assert {:ok, dest} = File.read_link(link)
    assert dest == "../../.agents/skills/tophat"
    assert File.exists?(Path.join(link, "SKILL.md"))
    refute File.exists?(Path.join(target, "not-a-skill"))
  end

  test "is idempotent", %{source: source, target: target} do
    make_skill(source, "tophat")

    assert %{created: ["tophat"]} = Link.sync(source, target)
    assert %{ok: ["tophat"], created: [], pruned: []} = Link.sync(source, target)
  end

  test "repoints symlinks that resolve elsewhere", %{source: source, target: target} do
    make_skill(source, "tophat")
    File.mkdir_p!(target)
    File.ln_s!("../../somewhere/else", Path.join(target, "tophat"))

    assert %{created: ["tophat"]} = Link.sync(source, target)
    assert {:ok, "../../.agents/skills/tophat"} = File.read_link(Path.join(target, "tophat"))
  end

  test "prunes dangling symlinks", %{source: source, target: target} do
    make_skill(source, "tophat")
    Link.sync(source, target)
    File.rm_rf!(Path.join(source, "tophat"))

    assert %{ok: [], created: [], pruned: ["tophat"]} = Link.sync(source, target)
    assert {:error, :enoent} = File.lstat(Path.join(target, "tophat"))
  end

  test "leaves real directories in target alone", %{source: source, target: target} do
    make_skill(source, "tophat")
    claude_only = Path.join(target, "tophat")
    File.mkdir_p!(claude_only)
    File.write!(Path.join(claude_only, "SKILL.md"), "claude-only")

    Link.sync(source, target)

    assert {:error, :einval} = File.read_link(claude_only)
    assert File.read!(Path.join(claude_only, "SKILL.md")) == "claude-only"
  end
end
