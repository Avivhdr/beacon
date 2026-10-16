# Changelog

## 1.0.0

First public release of Beacon.

Beacon is a macOS menu bar app. It shows unread GitHub activity, pull requests that need your review, and your own open pull requests.

- The token comes from `gh` and stays on the Mac. Beacon talks only to `api.github.com`.
- Review filters live in the panel. The config file is `~/.config/beacon/config.json`.
- Signed updates. The app checks for them once a day.
