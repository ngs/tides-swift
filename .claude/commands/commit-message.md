Generate commit message in English from git diff.

CRITICAL RULES:
1. Output ONLY the commit message itself
2. Do NOT include any preambles, introductions, meta-commentary
3. Do NOT include phrases like "Based on the git diff", "Here's the commit message"
4. NEVER add AI signatures like "🤖 Generated with [Claude Code]" or "Co-Authored-By: Claude"
5. Start directly with the commit message content

Format:
- First line should be summary of changes
- Details follow after a empty line
  - Do not quote with code block
  - Plain text format, no markdown decoration

