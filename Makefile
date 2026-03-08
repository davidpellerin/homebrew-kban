.PHONY: test test-bash test-python lint

test: lint test-bash test-python

lint:
	shellcheck bin/kban

test-bash:
	bats tests/kban.bats

test-python:
	pytest tests/test_serve.py -v -p no:langsmith --cov=web --cov-report=term-missing
