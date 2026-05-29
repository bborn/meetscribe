#!/bin/zsh
# <xbar.title>MeetScribe</xbar.title>
# <xbar.version>1.0</xbar.version>
# <xbar.desc>One-press local meeting recorder + transcript.</xbar.desc>
# <swiftbar.refreshOnOpen>true</swiftbar.refreshOnOpen>
#
# Install: copy this file into your SwiftBar plugin folder, then run
#   chmod +x ~/Library/Application\ Support/SwiftBar/Plugins/meetscribe.1s.sh
# Requires: meetscribe and meetscribe-bg on PATH (or edit MS/BG below).

export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
MS="$(command -v meetscribe || echo "$HOME/.local/bin/meetscribe")"
BG="$(command -v meetscribe-bg || echo "$HOME/.local/bin/meetscribe-bg")"
STATE="$HOME/.local/state/meetscribe"
RECDIR="${MEETSCRIBE_OUTDIR:-$HOME/Desktop/meet-recordings}"

running(){ [[ -f "$STATE/pid" ]] && kill -0 "$(cat "$STATE/pid" 2>/dev/null)" 2>/dev/null; }

if running; then
  if [[ -f "$STATE/paused" ]]; then
    echo "⏸ Paused | color=orange"
    echo "---"
    echo "Paused — nothing is being captured | size=12 color=gray"
    echo "▶️  Resume | bash='$MS' param1=resume terminal=false refresh=true"
  else
    start=$(cat "$STATE/start" 2>/dev/null); now=$(date +%s)
    el=$(( now - ${start:-$now} )); mm=$(( el/60 )); ss=$(( el%60 ))
    printf "🔴 %d:%02d | color=red\n" $mm $ss
    echo "---"
    echo "Recording everything — meeting + your mic | size=12 color=gray"
    echo "⏸  Pause | bash='$MS' param1=pause terminal=false refresh=true"
  fi
  echo "⏹  Stop & save | bash='$BG' param1=stop terminal=false refresh=true"
  echo "📂  Open recordings folder | bash=open param1='$RECDIR' terminal=false"
else
  echo "⚫︎ Rec"
  echo "---"
  echo "🔴  Start recording | bash='$MS' param1=start terminal=false refresh=true"
  echo "📂  Open recordings folder | bash=open param1='$RECDIR' terminal=false"
fi
