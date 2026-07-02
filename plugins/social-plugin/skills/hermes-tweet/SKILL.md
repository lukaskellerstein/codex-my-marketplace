---
name: hermes-tweet
description: Use Hermes Tweet for X/Twitter search, reading, and explicitly approved posting workflows in Hermes Agent-compatible environments.
---

# Hermes Tweet

Use this skill when a Codex or Hermes Agent workflow needs X/Twitter context or
an approved path for social account actions through Hermes Tweet.

## Triggers

Use Hermes Tweet when the user asks to:

- Search X/Twitter for posts, profiles, topics, or account context.
- Gather public social context before drafting a report, reply, or update.
- Prepare an X/Twitter post that will be reviewed before publishing.
- Verify whether the Hermes Tweet plugin is installed and configured.

## Setup Check

Hermes Tweet is distributed from:

```text
https://github.com/Xquik-dev/hermes-tweet
```

For Hermes Agent, install and enable the plugin explicitly:

```sh
hermes plugins install Xquik-dev/hermes-tweet --no-enable
hermes plugins enable hermes-tweet
```

`XQUIK_API_KEY` is required for read and action tools. Account actions also
require `HERMES_TWEET_ENABLE_ACTIONS=true`.

## Operating Rules

1. Prefer read-only exploration before any account action.
2. Treat generated post text as a draft until the user approves it.
3. Never publish, like, repost, follow, unfollow, or message unless the user
   explicitly requested that action in the current task.
4. If action gating is disabled, stop after the draft or read result and report
   the missing gate.
5. Do not store keys, cookies, screenshots, or private account data in the repo.
