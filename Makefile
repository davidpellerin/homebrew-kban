.PHONY: test test-bash test-python

test: test-bash test-python

test-bash:
	bats tests/kban.bats

test-python:
	pytest tests/test_serve.py -v -p no:langsmith
