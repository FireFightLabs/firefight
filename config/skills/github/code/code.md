---
name: github_code
when: Reading a GitHub repository's code as it was running during an incident, such as the lines in a stack trace or where something is defined
tools: [running_commit, fetch_file, blame, code_search, find_definition, git_log]
---
1. Call `running_commit` for the commit that was running, and pass it as `ref` to every read, so the code is what ran rather than what is on the default branch now.
2. Call `fetch_file` with the file's `path` and the failing line as `start_line`, which brings the lines around it.
3. Call `blame` with `start_line` and `end_line` for the commits and pull requests that last touched those lines.
4. Call `code_search` with a `pattern` for an error's text, `find_definition` for a `symbol` a frame names, and `git_log` with `added_or_removed` for when a line appeared or went.
5. Quote the lines that matter with their link, which is pinned to the commit.
