#!/usr/bin/env python3
"""Install the local Hermes Discord thread-routing safety patch.

Upstream remembers every thread a profile has participated in and, by
default, treats every remembered thread as an automatic-reply conversation.
For multiple specialist Bots that is unsafe: a past mention in one Bot's
workspace must not make every Bot keep responding there.  The patch introduces
``DISCORD_AUTO_REPLY_THREAD_PARENTS``; leaving it unset retains upstream
behaviour, while dcli scopes automatic follow-ups to a Bot's own channel and
the shared agent-work forum. It also permits explicitly selected free-response
channels to create task threads, which upstream otherwise suppresses.
"""

from __future__ import annotations

from pathlib import Path

ADAPTER = Path.home() / ".hermes" / "hermes-agent" / "plugins" / "platforms" / "discord" / "adapter.py"


def replace_once(source: str, old: str, new: str, label: str) -> str:
    if new in source:
        return source
    if old not in source:
        raise SystemExit(f"Hermes Discord adapter changed; cannot safely apply {label} patch")
    return source.replace(old, new, 1)


def main() -> int:
    if not ADAPTER.is_file():
        raise SystemExit(f"Hermes Discord adapter not found: {ADAPTER}")
    source = ADAPTER.read_text(encoding="utf-8")
    if (
        '"DISCORD_AUTO_REPLY_THREAD_PARENTS"' in source
        and '"DISCORD_AUTO_THREAD_FREE_RESPONSE_CHANNELS"' in source
        and "def _is_auto_reply_bot_thread" in source
        and "def _is_auto_thread_free_response_channel" in source
        and "self._is_auto_reply_bot_thread(message.channel, parent_channel_id)" in source
        and "self._is_auto_reply_bot_thread(message.channel, parent_id)" in source
        and "allow_free_response_thread = self._is_auto_thread_free_response_channel(channel_keys)" in source
    ):
        print("Hermes Discord thread-routing patch is already installed")
        return 0
    source = replace_once(
        source,
        '    "DISCORD_FREE_RESPONSE_CHANNELS",\n    "DISCORD_MISSED_MESSAGE_BACKFILL_CHANNELS",',
        '    "DISCORD_FREE_RESPONSE_CHANNELS",\n    "DISCORD_AUTO_REPLY_THREAD_PARENTS",\n    "DISCORD_MISSED_MESSAGE_BACKFILL_CHANNELS",',
        "thread parent gate snapshot",
    )
    source = replace_once(
        source,
        '    "DISCORD_AUTO_REPLY_THREAD_PARENTS",\n    "DISCORD_MISSED_MESSAGE_BACKFILL_CHANNELS",',
        '    "DISCORD_AUTO_REPLY_THREAD_PARENTS",\n    "DISCORD_AUTO_THREAD_FREE_RESPONSE_CHANNELS",\n    "DISCORD_MISSED_MESSAGE_BACKFILL_CHANNELS",',
        "free-response thread gate snapshot",
    )
    old_method_end = '''        return os.getenv("DISCORD_THREAD_REQUIRE_MENTION", "false").lower() in {"true", "1", "yes", "on"}\n\n    def _discord_history_backfill(self) -> bool:'''
    new_method_end = '''        return os.getenv("DISCORD_THREAD_REQUIRE_MENTION", "false").lower() in {"true", "1", "yes", "on"}\n\n    def _is_auto_reply_bot_thread(self, channel: Any, parent_channel_id: str | None = None) -> bool:\n        """Whether remembered thread participation may bypass @mention."""\n        if not isinstance(channel, discord.Thread):\n            return False\n        if str(channel.id) not in self._threads or self._discord_thread_require_mention():\n            return False\n        allowed_parents = self._gate_csv_set(\n            self._gate_raw("auto_reply_thread_parents", "DISCORD_AUTO_REPLY_THREAD_PARENTS")\n        )\n        if not allowed_parents or "*" in allowed_parents:\n            return True\n        parent_id = parent_channel_id or self._get_parent_channel_id(channel)\n        return bool(parent_id and str(parent_id) in allowed_parents)\n\n    def _discord_history_backfill(self) -> bool:'''
    if "def _is_auto_reply_bot_thread" not in source:
        source = replace_once(source, old_method_end, new_method_end, "thread parent guard")
    old_history_method = '''\n    def _discord_history_backfill(self) -> bool:'''
    new_history_method = '''\n    def _is_auto_thread_free_response_channel(self, channel_keys: set[str]) -> bool:
        """Whether a free-response channel should still create task threads."""
        channels = self._gate_csv_set(
            self._gate_raw(
                "auto_thread_free_response_channels",
                "DISCORD_AUTO_THREAD_FREE_RESPONSE_CHANNELS",
            )
        )
        return "*" in channels or bool(channel_keys & channels)

    def _discord_history_backfill(self) -> bool:'''
    source = replace_once(source, old_history_method, new_history_method, "free-response thread guard")
    old_direct_gate = '''            in_bot_thread = (\n                is_thread\n                and thread_id in self._threads\n                and not self._discord_thread_require_mention()\n            )'''
    if "self._is_auto_reply_bot_thread(message.channel, parent_channel_id)" not in source:
        source = replace_once(
            source,
            old_direct_gate,
            "            in_bot_thread = self._is_auto_reply_bot_thread(message.channel, parent_channel_id)",
            "live message gate",
        )
    old_recovery_gate = '''            in_bot_thread = (\n                isinstance(message.channel, discord.Thread)\n                and str(message.channel.id) in self._threads\n                and not self._discord_thread_require_mention()\n            )'''
    if "self._is_auto_reply_bot_thread(message.channel, parent_id)" not in source:
        source = replace_once(
            source,
            old_recovery_gate,
            "            in_bot_thread = self._is_auto_reply_bot_thread(message.channel, parent_id)",
            "recovery message gate",
        )
    source = replace_once(
        source,
        '''            skip_thread = bool(channel_keys & no_thread_channels) or is_free_channel''',
        '''            allow_free_response_thread = self._is_auto_thread_free_response_channel(channel_keys)
            skip_thread = bool(channel_keys & no_thread_channels) or (
                is_free_channel and not allow_free_response_thread
            )''',
        "free-response auto-thread gate",
    )
    ADAPTER.write_text(source, encoding="utf-8")
    print("Hermes Discord thread-routing patch is installed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
