#!/usr/bin/env bats
# Tests for bin/kban

KBAN="${BATS_TEST_DIRNAME}/../bin/kban"

setup() {
    TEST_DIR="$(mktemp -d)"
    cd "$TEST_DIR"
}

teardown() {
    cd /
    rm -rf "$TEST_DIR"
}

# ─── version ─────────────────────────────────────────────────────────────────

@test "version outputs version string" {
    run "$KBAN" version
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^kban\ [0-9] ]]
}

# ─── init ────────────────────────────────────────────────────────────────────

@test "init creates lane directories" {
    run "$KBAN" init
    [ "$status" -eq 0 ]
    [ -d ".kban/work/backlog" ]
    [ -d ".kban/work/ready" ]
    [ -d ".kban/work/doing" ]
    [ -d ".kban/work/done" ]
    [ -d ".kban/work/archive" ]
}

@test "init creates sample ticket" {
    "$KBAN" init
    [ -f ".kban/work/backlog/SETUP-001.md" ]
}

@test "init is idempotent when called twice" {
    "$KBAN" init
    run "$KBAN" init
    [ "$status" -eq 0 ]
    [ -f ".kban/work/backlog/SETUP-001.md" ]
}

# ─── board ───────────────────────────────────────────────────────────────────

@test "board shows lane headers" {
    "$KBAN" init
    run "$KBAN" board
    [ "$status" -eq 0 ]
    [[ "$output" =~ BACKLOG ]]
    [[ "$output" =~ READY ]]
    [[ "$output" =~ DOING ]]
    [[ "$output" =~ DONE ]]
}

@test "board shows ticket counts" {
    "$KBAN" init
    run "$KBAN" board
    [ "$status" -eq 0 ]
    [[ "$output" =~ BACKLOG\ \(1\) ]]
}

# ─── list ────────────────────────────────────────────────────────────────────

@test "list all shows tickets across lanes" {
    "$KBAN" init
    run "$KBAN" list
    [ "$status" -eq 0 ]
    [[ "$output" =~ SETUP-001 ]]
}

@test "list backlog shows only backlog tickets" {
    "$KBAN" init
    run "$KBAN" list backlog
    [ "$status" -eq 0 ]
    [[ "$output" =~ SETUP-001 ]]
}

@test "list ready shows empty ready lane" {
    "$KBAN" init
    run "$KBAN" list ready
    [ "$status" -eq 0 ]
    [[ ! "$output" =~ SETUP-001 ]]
}

@test "list shows BLOCKED suffix for blocked tickets" {
    "$KBAN" init
    "$KBAN" block SETUP-001
    run "$KBAN" list backlog
    [ "$status" -eq 0 ]
    [[ "$output" =~ BLOCKED ]]
}

# ─── show ────────────────────────────────────────────────────────────────────

@test "show displays ticket details" {
    "$KBAN" init
    run "$KBAN" show SETUP-001
    [ "$status" -eq 0 ]
    [[ "$output" =~ SETUP-001 ]]
    [[ "$output" =~ backlog ]]
}

@test "show fails for nonexistent ticket" {
    "$KBAN" init
    run "$KBAN" show NONEXISTENT-999
    [ "$status" -ne 0 ]
}

@test "show fails with no arguments" {
    "$KBAN" init
    run "$KBAN" show
    [ "$status" -ne 0 ]
}

# ─── move ────────────────────────────────────────────────────────────────────

@test "move changes ticket lane" {
    "$KBAN" init
    run "$KBAN" move SETUP-001 ready
    [ "$status" -eq 0 ]
    [ -f ".kban/work/ready/SETUP-001.md" ]
    [ ! -f ".kban/work/backlog/SETUP-001.md" ]
}

@test "move to same lane is idempotent" {
    "$KBAN" init
    run "$KBAN" move SETUP-001 backlog
    [ "$status" -eq 0 ]
    [ -f ".kban/work/backlog/SETUP-001.md" ]
}

@test "move fails for invalid lane" {
    "$KBAN" init
    run "$KBAN" move SETUP-001 invalid-lane
    [ "$status" -ne 0 ]
}

@test "move fails for nonexistent ticket" {
    "$KBAN" init
    run "$KBAN" move NONEXISTENT-999 ready
    [ "$status" -ne 0 ]
}

@test "move fails with too few arguments" {
    "$KBAN" init
    run "$KBAN" move SETUP-001
    [ "$status" -ne 0 ]
}

# ─── start ───────────────────────────────────────────────────────────────────

@test "start moves ticket to doing" {
    "$KBAN" init
    "$KBAN" move SETUP-001 ready
    run "$KBAN" start SETUP-001
    [ "$status" -eq 0 ]
    [ -f ".kban/work/doing/SETUP-001.md" ]
}

@test "start fails with no arguments" {
    "$KBAN" init
    run "$KBAN" start
    [ "$status" -ne 0 ]
}

# ─── done ────────────────────────────────────────────────────────────────────

@test "done moves ticket to done lane" {
    "$KBAN" init
    "$KBAN" move SETUP-001 doing
    run "$KBAN" done SETUP-001
    [ "$status" -eq 0 ]
    [ -f ".kban/work/done/SETUP-001.md" ]
}

@test "done fails with no arguments" {
    "$KBAN" init
    run "$KBAN" done
    [ "$status" -ne 0 ]
}

# ─── next ────────────────────────────────────────────────────────────────────

@test "next returns actionable ready ticket" {
    "$KBAN" init
    "$KBAN" move SETUP-001 ready
    run "$KBAN" next
    [ "$status" -eq 0 ]
    [[ "$output" =~ SETUP-001 ]]
}

@test "next fails when no ready tickets" {
    "$KBAN" init
    run "$KBAN" next
    [ "$status" -ne 0 ]
}

# ─── promote ─────────────────────────────────────────────────────────────────

@test "promote moves eligible backlog tickets to ready" {
    "$KBAN" init
    run "$KBAN" promote
    [ "$status" -eq 0 ]
    [ -f ".kban/work/ready/SETUP-001.md" ]
}

@test "promote skips blocked tickets" {
    "$KBAN" init
    "$KBAN" block SETUP-001
    run "$KBAN" promote
    [ -f ".kban/work/backlog/SETUP-001.md" ]
    [ ! -f ".kban/work/ready/SETUP-001.md" ]
}

@test "promote only promotes tickets with all deps done" {
    "$KBAN" init
    rm .kban/work/backlog/SETUP-001.md
    cat > .kban/work/backlog/DEP-001.md <<'EOF'
---
title: Has unmet dep
priority: high
depends_on: [MISSING-999]
---
EOF
    cat > .kban/work/backlog/DEP-002.md <<'EOF'
---
title: No deps
priority: high
depends_on: []
---
EOF
    run "$KBAN" promote
    [ "$status" -eq 0 ]
    [ -f ".kban/work/backlog/DEP-001.md" ]
    [ -f ".kban/work/ready/DEP-002.md" ]
}

# ─── block / unblock ─────────────────────────────────────────────────────────

@test "block marks ticket as blocked" {
    "$KBAN" init
    run "$KBAN" block SETUP-001
    [ "$status" -eq 0 ]
    grep -q "blocked: true" .kban/work/backlog/SETUP-001.md
}

@test "unblock removes blocked status" {
    "$KBAN" init
    "$KBAN" block SETUP-001
    run "$KBAN" unblock SETUP-001
    [ "$status" -eq 0 ]
    ! grep -q "blocked: true" .kban/work/backlog/SETUP-001.md
}

@test "block fails for nonexistent ticket" {
    "$KBAN" init
    run "$KBAN" block NONEXISTENT-999
    [ "$status" -ne 0 ]
}

@test "unblock fails for nonexistent ticket" {
    "$KBAN" init
    run "$KBAN" unblock NONEXISTENT-999
    [ "$status" -ne 0 ]
}

@test "block fails with no arguments" {
    "$KBAN" init
    run "$KBAN" block
    [ "$status" -ne 0 ]
}

# ─── archive / unarchive ─────────────────────────────────────────────────────

@test "archive moves ticket to archive lane" {
    "$KBAN" init
    run "$KBAN" archive SETUP-001
    [ "$status" -eq 0 ]
    [ -f ".kban/work/archive/SETUP-001.md" ]
    [ ! -f ".kban/work/backlog/SETUP-001.md" ]
}

@test "archive is idempotent when already archived" {
    "$KBAN" init
    "$KBAN" archive SETUP-001
    run "$KBAN" archive SETUP-001
    [ "$status" -eq 0 ]
}

@test "unarchive moves ticket to done lane" {
    "$KBAN" init
    "$KBAN" archive SETUP-001
    run "$KBAN" unarchive SETUP-001
    [ "$status" -eq 0 ]
    [ -f ".kban/work/done/SETUP-001.md" ]
    [ ! -f ".kban/work/archive/SETUP-001.md" ]
}

@test "archive hides ticket from board" {
    "$KBAN" init
    "$KBAN" archive SETUP-001
    run "$KBAN" board
    [ "$status" -eq 0 ]
    [[ ! "$output" =~ SETUP-001 ]]
}

# ─── YAML frontmatter edge cases ─────────────────────────────────────────────

@test "show handles ticket with missing priority field" {
    "$KBAN" init
    cat > .kban/work/backlog/TEST-001.md <<'EOF'
---
title: No priority ticket
depends_on: []
---
Body text here.
EOF
    run "$KBAN" show TEST-001
    [ "$status" -eq 0 ]
    [[ "$output" =~ TEST-001 ]]
}

@test "show handles ticket with extra frontmatter fields" {
    "$KBAN" init
    cat > .kban/work/backlog/TEST-002.md <<'EOF'
---
title: Extra fields ticket
priority: low
depends_on: []
custom_field: some value
another_field: 42
---
EOF
    run "$KBAN" show TEST-002
    [ "$status" -eq 0 ]
}

@test "list handles ticket with missing depends_on field" {
    "$KBAN" init
    cat > .kban/work/backlog/TEST-003.md <<'EOF'
---
title: No depends_on
priority: high
---
EOF
    run "$KBAN" list backlog
    [ "$status" -eq 0 ]
    [[ "$output" =~ TEST-003 ]]
}

@test "promote handles ticket with empty depends_on list" {
    "$KBAN" init
    rm .kban/work/backlog/SETUP-001.md
    cat > .kban/work/backlog/TEST-004.md <<'EOF'
---
title: Empty deps list
priority: high
depends_on: []
---
EOF
    run "$KBAN" promote
    [ "$status" -eq 0 ]
    [ -f ".kban/work/ready/TEST-004.md" ]
}

# ─── dependency resolution ───────────────────────────────────────────────────

@test "next skips ready ticket with unmet deps" {
    "$KBAN" init
    cat > .kban/work/ready/DEP-001.md <<'EOF'
---
title: Has unmet dep
priority: high
depends_on: [MISSING-001]
---
EOF
    run "$KBAN" next
    [ "$status" -ne 0 ]
}

@test "next returns ticket whose deps are all done" {
    "$KBAN" init
    cat > .kban/work/done/DEP-000.md <<'EOF'
---
title: Already done dep
priority: low
depends_on: []
---
EOF
    cat > .kban/work/ready/DEP-001.md <<'EOF'
---
title: Has met dep
priority: high
depends_on: [DEP-000]
---
EOF
    run "$KBAN" next
    [ "$status" -eq 0 ]
    [[ "$output" =~ DEP-001 ]]
}

@test "next returns first ticket when multiple are ready" {
    "$KBAN" init
    cat > .kban/work/ready/AAA-001.md <<'EOF'
---
title: First alphabetically
priority: high
depends_on: []
---
EOF
    cat > .kban/work/ready/ZZZ-999.md <<'EOF'
---
title: Last alphabetically
priority: high
depends_on: []
---
EOF
    run "$KBAN" next
    [ "$status" -eq 0 ]
    [[ "$output" =~ AAA-001 ]]
}

@test "promote respects multi-dep tickets" {
    "$KBAN" init
    rm .kban/work/backlog/SETUP-001.md
    cat > .kban/work/done/DEP-A.md <<'EOF'
---
title: Done dep A
depends_on: []
---
EOF
    cat > .kban/work/backlog/MULTI-001.md <<'EOF'
---
title: Needs both deps
priority: high
depends_on: [DEP-A, DEP-B]
---
EOF
    run "$KBAN" promote
    # DEP-B not done yet, so MULTI-001 stays in backlog
    [ -f ".kban/work/backlog/MULTI-001.md" ]

    cat > .kban/work/done/DEP-B.md <<'EOF'
---
title: Done dep B
depends_on: []
---
EOF
    run "$KBAN" promote
    # Now both deps are done, MULTI-001 should promote
    [ -f ".kban/work/ready/MULTI-001.md" ]
}

# ─── end-to-end lifecycle ─────────────────────────────────────────────────────

@test "full ticket lifecycle: backlog -> ready -> doing -> done" {
    "$KBAN" init
    "$KBAN" move SETUP-001 ready
    [ -f ".kban/work/ready/SETUP-001.md" ]

    "$KBAN" start SETUP-001
    [ -f ".kban/work/doing/SETUP-001.md" ]

    "$KBAN" done SETUP-001
    [ -f ".kban/work/done/SETUP-001.md" ]
}

@test "promote auto-promotes when dependent ticket is done" {
    "$KBAN" init
    cat > .kban/work/backlog/CHILD-001.md <<'EOF'
---
title: Depends on SETUP-001
priority: high
depends_on: [SETUP-001]
---
EOF
    # SETUP-001 not done yet — CHILD-001 stays
    run "$KBAN" promote
    [ -f ".kban/work/backlog/CHILD-001.md" ]

    # Complete SETUP-001
    "$KBAN" move SETUP-001 done

    # Now CHILD-001 should be promotable
    run "$KBAN" promote
    [ "$status" -eq 0 ]
    [ -f ".kban/work/ready/CHILD-001.md" ]
}

# ─── create ──────────────────────────────────────────────────────────────────

@test "create makes ticket in backlog by default" {
    "$KBAN" init
    run "$KBAN" create FEAT-001 --title "My feature"
    [ "$status" -eq 0 ]
    [ -f ".kban/work/backlog/FEAT-001.md" ]
}

@test "create ticket has correct frontmatter" {
    "$KBAN" init
    "$KBAN" create FEAT-001 --title "My feature" --priority high
    grep -q "title: My feature" .kban/work/backlog/FEAT-001.md
    grep -q "priority: high" .kban/work/backlog/FEAT-001.md
    grep -q "depends_on: \[\]" .kban/work/backlog/FEAT-001.md
}

@test "create with --lane places ticket in correct lane" {
    "$KBAN" init
    run "$KBAN" create FEAT-002 --title "Ready ticket" --lane ready
    [ "$status" -eq 0 ]
    [ -f ".kban/work/ready/FEAT-002.md" ]
    [ ! -f ".kban/work/backlog/FEAT-002.md" ]
}

@test "create with --depends-on sets dependency list" {
    "$KBAN" init
    "$KBAN" create FEAT-003 --title "With deps" --depends-on "FEAT-001,FEAT-002"
    grep -q "depends_on: \[FEAT-001, FEAT-002\]" .kban/work/backlog/FEAT-003.md
}

@test "create fails when ticket id already exists" {
    "$KBAN" init
    "$KBAN" create FEAT-001 --title "First"
    run "$KBAN" create FEAT-001 --title "Duplicate"
    [ "$status" -ne 0 ]
    [[ "$output" =~ already\ exists ]]
}

@test "create fails with no arguments" {
    "$KBAN" init
    run "$KBAN" create
    [ "$status" -ne 0 ]
}

@test "create fails without --title" {
    "$KBAN" init
    run "$KBAN" create FEAT-001 --priority high
    [ "$status" -ne 0 ]
    [[ "$output" =~ --title ]]
}

@test "create fails with invalid priority" {
    "$KBAN" init
    run "$KBAN" create FEAT-001 --title "Test" --priority invalid
    [ "$status" -ne 0 ]
}

@test "create fails with invalid lane" {
    "$KBAN" init
    run "$KBAN" create FEAT-001 --title "Test" --lane invalid-lane
    [ "$status" -ne 0 ]
}

@test "create with default priority sets medium" {
    "$KBAN" init
    "$KBAN" create FEAT-001 --title "Default priority"
    grep -q "priority: medium" .kban/work/backlog/FEAT-001.md
}

# ─── delete ──────────────────────────────────────────────────────────────────

@test "delete removes ticket file" {
    "$KBAN" init
    run "$KBAN" delete SETUP-001
    [ "$status" -eq 0 ]
    [ ! -f ".kban/work/backlog/SETUP-001.md" ]
}

@test "delete works from any lane" {
    "$KBAN" init
    "$KBAN" move SETUP-001 doing
    run "$KBAN" delete SETUP-001
    [ "$status" -eq 0 ]
    [ ! -f ".kban/work/doing/SETUP-001.md" ]
}

@test "delete fails for nonexistent ticket" {
    "$KBAN" init
    run "$KBAN" delete NONEXISTENT-999
    [ "$status" -ne 0 ]
}

@test "delete fails with no arguments" {
    "$KBAN" init
    run "$KBAN" delete
    [ "$status" -ne 0 ]
}

# ─── init: agent prompt install ──────────────────────────────────────────────

@test "init copies agent prompt to config dir" {
    HOME="$TEST_DIR" run "$KBAN" init
    [ "$status" -eq 0 ]
    [ -f "$TEST_DIR/.config/kban/agent-prompt.md" ]
}

@test "init does not overwrite existing agent prompt" {
    mkdir -p "$TEST_DIR/.config/kban"
    echo "custom content" > "$TEST_DIR/.config/kban/agent-prompt.md"
    HOME="$TEST_DIR" "$KBAN" init
    grep -q "custom content" "$TEST_DIR/.config/kban/agent-prompt.md"
}

# ─── work ────────────────────────────────────────────────────────────────────

@test "work fails with nonexistent --prompt file" {
    HOME="$TEST_DIR" "$KBAN" init
    run "$KBAN" work --prompt /nonexistent/prompt.md
    [ "$status" -ne 0 ]
    [[ "$output" =~ "not found" ]]
}

@test "work fails with unknown option" {
    HOME="$TEST_DIR" "$KBAN" init
    run "$KBAN" work --unknown
    [ "$status" -ne 0 ]
}

@test "work with no ready tickets exits cleanly" {
    HOME="$TEST_DIR" "$KBAN" init
    prompt="$TEST_DIR/prompt.md"
    echo "test prompt" > "$prompt"
    run "$KBAN" work --prompt "$prompt"
    [ "$status" -eq 0 ]
}

@test "work processes each ready ticket" {
    mkdir -p "$TEST_DIR/bin"
    printf '#!/bin/sh\ncat > /dev/null\necho "claude invoked"\n' > "$TEST_DIR/bin/claude"
    chmod +x "$TEST_DIR/bin/claude"

    HOME="$TEST_DIR" "$KBAN" init
    "$KBAN" create TASK-001 --title "First task" --lane ready
    "$KBAN" create TASK-002 --title "Second task" --lane ready
    prompt="$TEST_DIR/prompt.md"
    echo "test prompt" > "$prompt"

    run env PATH="$TEST_DIR/bin:$PATH" "$KBAN" work --prompt "$prompt"
    [ "$status" -eq 0 ]
    [ -f ".kban/work/doing/TASK-001.md" ]
    [ -f ".kban/work/doing/TASK-002.md" ]
}

@test "work uses ~/.config/kban/agent-prompt.md by default" {
    mkdir -p "$TEST_DIR/bin"
    printf '#!/bin/sh\ncat > /dev/null\n' > "$TEST_DIR/bin/claude"
    chmod +x "$TEST_DIR/bin/claude"

    HOME="$TEST_DIR" "$KBAN" init
    "$KBAN" create TASK-001 --title "Test task" --lane ready

    run env PATH="$TEST_DIR/bin:$PATH" HOME="$TEST_DIR" "$KBAN" work
    [ "$status" -eq 0 ]
}

# ─── error handling ───────────────────────────────────────────────────────────

@test "unknown command exits with error" {
    run "$KBAN" not-a-real-command
    [ "$status" -ne 0 ]
}

@test "no arguments shows usage" {
    run "$KBAN"
    [ "$status" -eq 0 ]
    [[ "$output" =~ Usage ]]
}

@test "--help shows usage" {
    run "$KBAN" --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ Usage ]]
}
