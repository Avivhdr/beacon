#!/usr/bin/env bash
#
# notes-to-html.sh — turn one CHANGELOG.md section (stdin) into the HTML that
# Sparkle shows in the update window (stdout).
#
# Sparkle reads the feed's description as HTML, so plain line breaks collapse
# and a list of changes turns into one long line. "- " lines become a real list
# and every other line becomes its own paragraph.
set -euo pipefail

sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g' | awk '
  function end_list() { if (in_list) { print "</ul>"; in_list = 0 } }
  /^- / {
    if (!in_list) { print "<ul>"; in_list = 1 }
    print "<li>" substr($0, 3) "</li>"
    next
  }
  /^[[:space:]]*$/ { end_list(); next }
  { end_list(); print "<p>" $0 "</p>" }
  END { end_list() }
'
