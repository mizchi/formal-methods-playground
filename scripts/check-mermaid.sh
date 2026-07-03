#!/usr/bin/env bash
set -euo pipefail

if ! command -v mmdc >/dev/null 2>&1; then
  echo "mmdc not found. Enter the nix devShell: nix develop" >&2
  exit 127
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

browser_path="${PUPPETEER_EXECUTABLE_PATH:-}"

if [ -z "$browser_path" ]; then
  for candidate in \
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
    "/Applications/Chromium.app/Contents/MacOS/Chromium" \
    "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge" \
    "/usr/bin/google-chrome" \
    "/usr/bin/chromium" \
    "/usr/bin/chromium-browser"; do
    if [ -x "$candidate" ]; then
      browser_path="$candidate"
      break
    fi
  done
fi

if [ -z "$browser_path" ]; then
  echo "Chrome/Chromium executable not found for mmdc." >&2
  echo "Set PUPPETEER_EXECUTABLE_PATH or enter the nix devShell on Linux." >&2
  exit 1
fi

puppeteer_config="$tmp_dir/puppeteer.json"
printf '{\n  "executablePath": "%s",\n  "args": ["--no-sandbox", "--disable-setuid-sandbox"]\n}\n' \
  "$browser_path" >"$puppeteer_config"

count=0

while IFS= read -r markdown_file; do
  in_mermaid=0
  diagram_file=""

  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$in_mermaid" -eq 0 ] && [ "$line" = '```mermaid' ]; then
      count=$((count + 1))
      diagram_file="$tmp_dir/diagram-$count.mmd"
      : >"$diagram_file"
      in_mermaid=1
      continue
    fi

    if [ "$in_mermaid" -eq 1 ] && [ "$line" = '```' ]; then
      in_mermaid=0
      output_file="$tmp_dir/diagram-$count.svg"
      echo "== mermaid: $markdown_file #$count"
      mmdc --quiet --puppeteerConfigFile "$puppeteer_config" \
        --input "$diagram_file" \
        --output "$output_file"
      continue
    fi

    if [ "$in_mermaid" -eq 1 ]; then
      printf '%s\n' "$line" >>"$diagram_file"
    fi
  done <"$markdown_file"

  if [ "$in_mermaid" -eq 1 ]; then
    echo "unterminated mermaid block in $markdown_file" >&2
    exit 1
  fi
done < <(rg -l '```mermaid' book README.md real-world-adoption.ja.md real-world-adoption.md || true)

if [ "$count" -eq 0 ]; then
  echo "No mermaid diagrams found."
else
  echo "Checked $count mermaid diagram(s)."
fi
