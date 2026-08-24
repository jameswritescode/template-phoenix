defmodule Mix.Tasks.Skills.Link do
  @shortdoc "Ensures every skill in .agents/skills is symlinked into .claude/skills"

  @moduledoc """
  Keeps `.claude/skills/` in sync with the canonical skills directory,
  `.agents/skills/`.

      mix skills.link

  Skills live canonically in `.agents/skills/` (read natively by Codex, and
  where `mix usage_rules.sync` writes generated skills). Claude Code follows
  per-skill symlinks but does not discover skills through a symlinked skills
  directory (anthropics/claude-code#38051), so `.claude/skills/` must be a real
  directory containing one relative symlink per skill.

  This task:

    * creates a symlink for every `.agents/skills/<name>/` containing a
      `SKILL.md`
    * repoints symlinks that resolve to the wrong location
    * prunes dangling symlinks left behind by removed skills
    * leaves real (non-symlink) entries alone, so Claude-only skills can
      coexist

  Run it after adding a skill by hand or after `mix usage_rules.sync`
  generates a new one.
  """
  use Mix.Task

  @source ".agents/skills"
  @target ".claude/skills"

  @impl Mix.Task
  def run(args) do
    if args != [] do
      Mix.raise("mix skills.link takes no arguments, got: #{Enum.join(args, " ")}")
    end

    summary = sync(@source, @target)

    Enum.each(summary.created, &Mix.shell().info("linked #{&1}"))
    Enum.each(summary.pruned, &Mix.shell().info("pruned #{&1}"))

    Mix.shell().info(
      "skills.link: #{length(summary.ok)} ok, " <>
        "#{length(summary.created)} linked, #{length(summary.pruned)} pruned"
    )
  end

  @doc """
  Synchronizes per-skill symlinks in `target` against skills found in `source`.

  Returns a summary of skill names: `%{ok: [...], created: [...], pruned: [...]}`.
  """
  @spec sync(Path.t(), Path.t()) :: %{
          ok: [String.t()],
          created: [String.t()],
          pruned: [String.t()]
        }
  def sync(source, target) do
    File.mkdir_p!(target)
    skills = skill_names(source)

    {ok, created} =
      Enum.split_with(skills, fn name -> linked?(source, target, name) end)

    Enum.each(created, fn name -> link!(source, target, name) end)
    pruned = prune_dangling(target)

    %{ok: Enum.sort(ok), created: Enum.sort(created), pruned: Enum.sort(pruned)}
  end

  defp skill_names(source) do
    source
    |> Path.join("*")
    |> Path.wildcard()
    |> Enum.filter(fn dir ->
      File.dir?(dir) and File.exists?(Path.join(dir, "SKILL.md"))
    end)
    |> Enum.map(&Path.basename/1)
  end

  defp linked?(source, target, name) do
    link = Path.join(target, name)

    case File.read_link(link) do
      {:ok, dest} -> dest == expected_link_dest(source, target, name)
      {:error, _} -> false
    end
  end

  defp link!(source, target, name) do
    link = Path.join(target, name)

    case File.lstat(link) do
      # Existing symlink pointing elsewhere: repoint it
      {:ok, %File.Stat{type: :symlink}} -> File.rm!(link)
      # Real file/dir with the same name: leave it, skip (Claude-only skill)
      {:ok, _stat} -> throw({:exists, name})
      {:error, _} -> :ok
    end

    File.ln_s!(expected_link_dest(source, target, name), link)
  catch
    {:exists, ^name} -> :ok
  end

  defp prune_dangling(target) do
    target
    |> File.ls!()
    |> Enum.filter(fn name ->
      link = Path.join(target, name)

      with {:ok, %File.Stat{type: :symlink}} <- File.lstat(link),
           false <- File.exists?(link) do
        File.rm!(link)
        true
      else
        _ -> false
      end
    end)
  end

  # Relative path from inside `target` to `source`/`name`, so links survive
  # cloning and directory moves.
  defp expected_link_dest(source, target, name) do
    from = target |> Path.expand() |> Path.split()
    to = source |> Path.expand() |> Path.split()
    {from_rest, to_rest} = strip_common_prefix(from, to)

    (List.duplicate("..", length(from_rest)) ++ to_rest ++ [name]) |> Path.join()
  end

  defp strip_common_prefix([h | from], [h | to]), do: strip_common_prefix(from, to)
  defp strip_common_prefix(from, to), do: {from, to}
end
