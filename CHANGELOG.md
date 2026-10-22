# Changelog

## 1.1.0

- The Unread tab groups each day's items by pull request. A group header folds. On hover, it opens the pull request or marks all of its items read.
- Each row shows a link button on hover and has "Copy Link" in its right-click menu. Unread items copy the link to the comment or review. Group headers copy the link to the pull request.
- Each group header in the Mine tab has a control that folds all of its repositories. When all are folded, it unfolds them.

## 1.0.0

First public release of Beacon.

Beacon is a macOS menu bar app. It shows unread GitHub activity, pull requests that need your review, and your own open pull requests.

- The token comes from `gh` and stays on the Mac. Beacon talks only to `api.github.com`.
- Review filters live in the panel. The config file is `~/.config/beacon/config.json`.
- Signed updates. The app checks for them once a day.
