.PHONY: test test-bash test-python lint work

test: lint test-bash test-python

lint:
	shellcheck bin/kban

test-bash:
	bats tests/kban.bats

test-python:
	pytest tests/test_serve.py -v -p no:langsmith --cov=web --cov-report=term-missing

work:
	@for id in $$(kban list ready | sed 's/\x1b\[[0-9;]*m//g' | grep -oE '^[A-Z]+-[0-9]+'); do \
		echo "==> Working on $$id"; \
		kban start $$id; \
		tmp=$$(mktemp); \
		cat > $$tmp <<'PROMPT'
You are an autonomous agent working on a kban ticket.
Your job is to implement everything described completely and to a high standard —
not to summarise or plan, but to actually do the work.

WORKING INSTRUCTIONS:
- Read the ticket carefully, then execute all tasks described.
- Leverage available agents and skills — spawn sub-agents for independent subtasks,
  run things in parallel where possible, use specialised skills when they match.
- Write clean, minimal, well-tested code. Avoid over-engineering.
- When work is genuinely complete, output a concise summary of what you did.
- Do NOT call kban done — the Makefile handles lane transitions.

TICKET:
PROMPT
		kban show $$id >> $$tmp; \
		claude --dangerously-skip-permissions --print < $$tmp; \
		rm -f $$tmp; \
	done
