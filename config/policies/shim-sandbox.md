TOOL RESTRICTIONS (gemini-shim orchestrator — sandbox/read-only):
PERMITTED: read_file, view_file, grep_search, search_web, read_url
FORBIDDEN: run_shell_command, run_command, write_file, write_to_file,
  replace_file_content, multi_replace_file_content,
  invoke_subagent, spawn_agent, define_subagent, manage_subagents, schedule
