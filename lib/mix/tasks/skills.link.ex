defmodule Mix.Tasks.Skills.Link do
  @shortdoc "Ensures every skill in .agents/skills is symlinked into .claude/skills"

  @moduledoc """
  Keeps `.claude/skills/` in sync with the canonical skills directory,
  `.agents/skills/`.

      mix skills.link          # create/repoint/prune per-skill symlinks
      mix skills.link --check  # fail if anything would change (runs in precommit)

  Skills live canonically in `.agents/skills/` (read natively by Codex, and
  where `mix usage_rules.sync` writes generated skills). Claude Code follows
  per-skill symlinks but does not discover skills through a symlinked skills
  directory (anthropics/claude-code#38051), so `.claude/skills/` must be a real
  directory containing one relative symlink per skill.

  Syncing creates a symlink for every `.agents/skills/<name>/` containing a
  `SKILL.md`, repoints symlinks that resolve to the wrong location, prunes
  dangling symlinks left behind by removed skills, and leaves real
  (non-symlink) entries alone so Claude-only skills can coexist.
  """
  use Mix.Task

  @source ".agents/skills"
  @target ".claude/skills"

  @impl Mix.Task
  def run(args) do
    case args do
      [] ->
        summary = sync(@source, @target)

        Enum.each(summary.created, &Mix.shell().info("linked #{&1}"))
        Enum.each(summary.pruned, &Mix.shell().info("pruned #{&1}"))

        Mix.shell().info(
          "skills.link: #{length(summary.ok)} ok, " <>
            "#{length(summary.created)} linked, #{length(summary.pruned)} pruned"
        )

      ["--check"] ->
        check!(@source, @target)
        Mix.shell().info("skills.link: all skills linked")

      _ ->
        Mix.raise("Usage: mix skills.link [--check]")
    end
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
    %{ok: ok, to_link: to_link, dangling: dangling} = plan(source, target)

    Enum.each(to_link, fn name -> link!(source, target, name) end)
    Enum.each(dangling, fn name -> File.rm!(Path.join(target, name)) end)

    %{ok: ok, created: to_link, pruned: dangling}
  end

  @doc """
  Raises `Mix.Error` when `mix skills.link` would change anything.
  """
  @spec check!(Path.t(), Path.t()) :: :ok
  def check!(source, target) do
    case plan(source, target) do
      %{to_link: [], dangling: []} ->
        :ok

      %{to_link: to_link, dangling: dangling} ->
        problems =
          Enum.map(to_link, &"  missing or wrong link: #{&1}") ++
            Enum.map(dangling, &"  dangling link: #{&1}")

        Mix.raise(
          "Skill links out of sync — run `mix skills.link`:\n" <> Enum.join(problems, "\n")
        )
    end
  end

  @doc """
  Computes what `sync/2` would do without changing anything.
  """
  @spec plan(Path.t(), Path.t()) :: %{
          ok: [String.t()],
          to_link: [String.t()],
          dangling: [String.t()]
        }
  def plan(source, target) do
    skills = skill_names(source)

    {ok, to_link} =
      Enum.split_with(skills, fn name ->
        linked?(source, target, name) or real_entry?(target, name)
      end)

    # A broken symlink that carries a current skill's name is repointed by
    # sync, not pruned — only links for removed skills are dangling.
    dangling = target |> dangling() |> Enum.reject(&(&1 in skills))

    %{ok: Enum.sort(ok), to_link: Enum.sort(to_link), dangling: Enum.sort(dangling)}
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
    case File.read_link(Path.join(target, name)) do
      {:ok, dest} -> dest == expected_link_dest(source, target, name)
      {:error, _} -> false
    end
  end

  # A real file/directory with a skill's name (a Claude-only skill): left alone.
  defp real_entry?(target, name) do
    case File.lstat(Path.join(target, name)) do
      {:ok, %File.Stat{type: type}} -> type != :symlink
      {:error, _} -> false
    end
  end

  defp dangling(target) do
    case File.ls(target) do
      {:ok, entries} ->
        Enum.filter(entries, fn name ->
          link = Path.join(target, name)

          match?({:ok, %File.Stat{type: :symlink}}, File.lstat(link)) and
            not File.exists?(link)
        end)

      {:error, _} ->
        []
    end
  end

  defp link!(source, target, name) do
    link = Path.join(target, name)

    case File.lstat(link) do
      {:ok, %File.Stat{type: :symlink}} -> File.rm!(link)
      _ -> :ok
    end

    File.ln_s!(expected_link_dest(source, target, name), link)
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
