# homebrew-kban

Homebrew tap for [kban](https://github.com/davidpellerin/homebrew-kban) — a simple filesystem-based kanban board for AI tooling such as Claude Code.

## Install

```bash
brew tap davidpellerin/kban
brew install kban
```

## Usage

Run from any project directory that has a `.kban/work/` structure:

```
kban board               # Show the board overview
kban list [lane]         # List tickets in a lane (or all lanes)
kban show <id>           # Show ticket details
kban next                # Show the next actionable ticket
kban start <id>          # Move ticket to doing
kban done <id>           # Mark ticket as done
kban move <id> <lane>    # Move ticket to any lane
```

Lanes: `backlog`, `ready`, `doing`, `done`
