---
name: bitbucket_code
when: Reading or exploring a Bitbucket repository's code as it was running during an incident, such as the lines in a stack trace, where something is defined, or how a part of it works across many files
tools: [running_commit, run_shell, code_search, ask_language_server, find_definition, git_log, fetch_file, blame]
---
1. Call `running_commit` for the commit that was running, and pass it as `ref` to every read, so the code is what ran rather than what is on the main branch now.
2. To answer a question that spans more than one or two files, inspect one checkout broadly with `run_shell` at that `ref`: grep -rn, ls, find, cat and git log in one command or a few, rather than fetching files one at a time. `code_search` with a `pattern` finds an error's text or a name across the repository, `ask_language_server` and `find_definition` find where a `symbol` is defined and every reference to it, and `git_log` with `added_or_removed` says when a line appeared or went.
3. Call `fetch_file` only for one or two files you already know, with the file's `path` and the failing line as `start_line`, which brings the lines around it.
4. Call `blame` with `start_line` and `end_line` for the commits and pull requests that last touched those lines. It runs git in the code sandbox, since Bitbucket's API has no blame.
5. Quote the lines that matter with their link, which is pinned to the commit.
