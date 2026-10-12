---
name: github_releases_and_branches
when: Reading a GitHub repository's releases, tags, branches or branch protection, writing, editing or publishing a release, or making or deleting a branch
tools: [list_releases, release_lookup, list_tags, create_draft_release, update_release, publish_release, list_branches, branch_protection, create_branch, delete_branch, ref_checks]
references: [releases/managing-releases.md, branches/about-protected-branches.md, branches/about-rulesets.md]
---
1. `list_releases` and `release_lookup` with a `tag`, or without one for the latest, say what was released and when, with the notes. `list_releases` also shows drafts, with each one's id. `list_tags` names the commit each tag points at.
2. `list_branches` lists branches, and `branch_protection` says what protects one: its rulesets, required reviews and checks, and whether it can be force pushed or deleted. `ref_checks` reads the checks and statuses on a branch, tag or commit.
3. These change GitHub, so none is done while investigating. Say what each does and call it in a chat once the person agrees.
4. `create_draft_release` writes a draft for a `tag` on a `target`, with a `body` or with `generate_notes`, for a person to review. Its tag is made only when it is published.
5. `update_release` changes a release's notes, title or prerelease flag, by `tag` or `id`. To fill in a placeholder a release workflow left in a draft's notes, give `replace` and `with` rather than rewriting the whole notes. Show the person the notes it answers with.
6. `publish_release` publishes a draft, only when the person asks for it or a runbook step says to. Publishing makes the notes public, marks it the latest release unless `make_latest` is false, makes its tag if there is none yet, notifies the repository's watchers and starts any workflow that runs on a published release. Before asking, say which release, tag and commit it is, and that a release already published is left as it is.
7. `create_branch` makes a branch under halon/ from `from`, such as for a revert. `delete_branch` deletes only such a branch, never the default branch, a protected one or one an open pull request comes from.
8. Give the person the link each answer carries.
