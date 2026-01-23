# Hooks for automatic validation

Use this file when hooks are supported and you want `dcli validate` to run after edits.

## Recommended hook

Configure a PostToolUse hook that runs after Edit/Write actions:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "cd \"$CLAUDE_PROJECT_DIR\" && dcli validate"
          }
        ]
      }
    ]
  }
}
```

Notes:
- Use the `/hooks` slash command to create or update hooks interactively, then select `PostToolUse`.
- `PostToolUse` runs after tool calls; `PreToolUse` runs before and can block; `Notification` runs on notifications.
- See the hooks guide for details: https://code.claude.com/docs/fr/hooks-guide
