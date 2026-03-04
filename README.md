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
kban version             # Show kban version
kban init                # Create .kban folder structure in current directory
kban agent <tool>        # Scaffold an AI coding agent (claude, opencode)
kban board               # Show the board overview
kban list [lane]         # List tickets in a lane (or all lanes)
kban show <id>           # Show ticket details
kban next                # Show the next actionable ticket (ready + deps met)
kban start <id>          # Move ticket to doing
kban done <id>           # Mark ticket as done (auto-promotes backlog tickets)
kban move <id> <lane>    # Move ticket to any lane
```

Lanes: `backlog`, `ready`, `doing`, `done`

## Sample Prompts (Claude Code)

After running `kban agent claude`, try these in Claude Code:

```
using the kban agent, work through the ready queue until it's empty
```
```
using the kban agent, what's left to do?
```
```
using the kban agent, pick up the next ticket and implement it
```
```
using the kban agent, show me what's blocked and why
```
