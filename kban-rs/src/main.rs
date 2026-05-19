// kban - Simple filesystem-based kanban board for Claude Code agents
//
// Rust rewrite of bin/kban. Kept alongside the original bash script.
// Templates are embedded at compile time via include_str!.

use std::env;
use std::fs;
use std::io::{self, IsTerminal, Write};
use std::path::{Path, PathBuf};
use std::process;

// ─── Constants ───────────────────────────────────────────────────────────────

const VERSION: &str = "2.0.0";
const LANES: &[&str] = &["backlog", "ready", "doing", "done"];
const ARCHIVE_LANE: &str = "archive";
const COL_WIDTH: usize = 22;

const ANSI_RED: &str = "\x1b[0;31m";
const ANSI_GREEN: &str = "\x1b[0;32m";
const ANSI_YELLOW: &str = "\x1b[0;33m";
const ANSI_BLUE: &str = "\x1b[0;34m";
const ANSI_NC: &str = "\x1b[0m";

const SAMPLE_TICKET: &str =
    include_str!("../../templates/sample-tickets/sample-ticket.md");
const SKILL_MD: &str =
    include_str!("../../templates/skills/kban/SKILL.md");

// ─── Color helpers ───────────────────────────────────────────────────────────

fn use_color() -> bool {
    io::stdout().is_terminal() && env::var("NO_COLOR").is_err()
}

fn colored(code: &str, text: &str) -> String {
    if use_color() {
        format!("{}{}{}", code, text, ANSI_NC)
    } else {
        text.to_string()
    }
}

fn die(msg: &str) -> ! {
    eprintln!("{} {}", colored(ANSI_RED, "[ERROR]"), msg);
    process::exit(1);
}

fn log_info(msg: &str) {
    eprintln!("{} {}", colored(ANSI_BLUE, "[INFO]"), msg);
}

fn log_success(msg: &str) {
    eprintln!("{} {}", colored(ANSI_GREEN, "[OK]"), msg);
}

fn log_warn(msg: &str) {
    eprintln!("{} {}", colored(ANSI_YELLOW, "[WARN]"), msg);
}

// ─── Paths ───────────────────────────────────────────────────────────────────

fn kban_dir() -> PathBuf {
    env::current_dir()
        .unwrap_or_else(|e| die(&format!("Cannot get current directory: {}", e)))
        .join(".kban")
        .join("work")
}

// Walk up from the resolved binary path to find the directory containing web/
fn find_serve_script() -> Option<PathBuf> {
    let exe = env::current_exe().ok()?;
    let exe = fs::canonicalize(&exe).unwrap_or(exe);
    let mut dir = exe.parent()?.to_path_buf();
    for _ in 0..10 {
        let candidate = dir.join("web").join("serve.py");
        if candidate.is_file() {
            return Some(candidate);
        }
        dir = dir.parent()?.to_path_buf();
    }
    None
}

// ─── Frontmatter parsing ──────────────────────────────────────────────────────

fn get_field(path: &Path, field: &str) -> Option<String> {
    let content = fs::read_to_string(path).ok()?;
    let prefix = format!("{}:", field);
    let mut fm_count = 0u8;
    for line in content.lines() {
        if line == "---" {
            fm_count += 1;
            if fm_count >= 2 {
                break;
            }
            continue;
        }
        if fm_count == 1 && line.starts_with(&prefix) {
            return Some(line[prefix.len()..].trim().to_string());
        }
    }
    None
}

fn get_deps(path: &Path) -> Vec<String> {
    let raw = match get_field(path, "depends_on") {
        Some(v) => v,
        None => return vec![],
    };
    if raw.is_empty() || raw == "[]" {
        return vec![];
    }
    raw.trim_start_matches('[')
        .trim_end_matches(']')
        .split(',')
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .collect()
}

// Rewrite the blocked field in YAML frontmatter.
// value=true  → add/replace `blocked: true`
// value=false → remove the blocked line
fn set_blocked_in_content(content: &str, value: bool) -> String {
    let trailing_newline = content.ends_with('\n');
    let mut result: Vec<String> = Vec::new();
    let mut fm_count = 0u8;
    let mut blocked_written = false;

    for line in content.lines() {
        if line == "---" {
            fm_count += 1;
            if fm_count == 2 && value && !blocked_written {
                result.push("blocked: true".to_string());
                blocked_written = true;
            }
            result.push(line.to_string());
            continue;
        }
        if fm_count == 1 && line.starts_with("blocked:") {
            if value {
                result.push("blocked: true".to_string());
                blocked_written = true;
            }
            // For unblock, skip this line (removes it)
            continue;
        }
        result.push(line.to_string());
    }

    let mut out = result.join("\n");
    if trailing_newline {
        out.push('\n');
    }
    out
}

// ─── Ticket lookup ────────────────────────────────────────────────────────────

fn all_lanes() -> Vec<&'static str> {
    LANES.iter().copied().chain(std::iter::once(ARCHIVE_LANE)).collect()
}

fn find_ticket(id: &str) -> Option<PathBuf> {
    let dir = kban_dir();
    for lane in all_lanes() {
        let path = dir.join(lane).join(format!("{}.md", id));
        if path.is_file() {
            return Some(path);
        }
    }
    None
}

fn get_lane(id: &str) -> String {
    let path = find_ticket(id).unwrap_or_else(|| die(&format!("Ticket not found: {}", id)));
    path.parent()
        .and_then(|p| p.file_name())
        .and_then(|n| n.to_str())
        .unwrap_or("unknown")
        .to_string()
}

fn deps_met(path: &Path) -> bool {
    let dir = kban_dir();
    for dep in get_deps(path) {
        if !dir.join("done").join(format!("{}.md", dep)).is_file() {
            return false;
        }
    }
    true
}

fn lane_tickets(lane: &str) -> Vec<PathBuf> {
    let dir = kban_dir().join(lane);
    let mut files: Vec<PathBuf> = fs::read_dir(&dir)
        .ok()
        .into_iter()
        .flatten()
        .filter_map(|e| e.ok())
        .map(|e| e.path())
        .filter(|p| p.extension().and_then(|e| e.to_str()) == Some("md"))
        .collect();
    files.sort();
    files
}

fn validate_ticket_id(id: &str) {
    let parts: Vec<&str> = id.splitn(2, '-').collect();
    let valid = parts.len() == 2
        && !parts[0].is_empty()
        && parts[0].chars().all(|c| c.is_ascii_uppercase())
        && !parts[1].is_empty()
        && parts[1].chars().all(|c| c.is_ascii_digit());
    if !valid {
        log_warn(&format!(
            "Ticket ID '{}' does not match canonical format (e.g. TASK-001, FEAT-042). \
             The web UI will reject non-canonical IDs.",
            id
        ));
    }
}

// ─── Commands ─────────────────────────────────────────────────────────────────

fn usage() {
    print!(
        r#"kban - Simple filesystem-based kanban board

Usage: kban <command> [arguments]

Commands:
    version                     Show kban version
    init                        Create .kban folder structure in current directory
    install skill user [-f]     Install Claude Code skill for your user account (all projects)
    install skill project [-f]  Install Claude Code skill for this project only
    board                       Show the board overview
    create <id>                 Create a new ticket (default lane: backlog)
    list [lane]                 List tickets in a lane (or all lanes)
    show <id>                   Show ticket details
    next                        Show the next actionable ticket (ready + deps met)
    start <id>                  Move ticket to doing
    done <id>                   Mark ticket as done
    promote                     Move eligible backlog tickets to ready
    move <id> <lane>            Move ticket to any lane
    block <id>                  Mark ticket as blocked
    unblock <id>                Clear blocked status from ticket
    archive <id>                Move ticket to archive (hidden from board)
    unarchive <id>              Restore ticket from archive to done
    tickets [lane]              Flat list of all tickets with lane/priority/deps
    delete <id>                 Delete a ticket permanently
    serve                       Start the web UI (default: http://localhost:8080)

Options for create:
    --title "..."               Ticket title (required)
    --priority high|medium|low  Priority (default: medium)
    --lane <lane>               Lane to create in (default: backlog)
    --depends-on ID1,ID2        Comma-separated dependency IDs

Lanes: backlog, ready, doing, done, archive

Environment variables for serve:
    KBAN_HOST           Host to bind (default: localhost)
    KBAN_PORT           Port to bind (default: 8080)

"#
    );
}

fn check_board_exists() {
    let cwd = env::current_dir().unwrap_or_else(|_| die("Cannot get current directory"));
    if !cwd.join(".kban").is_dir() {
        eprintln!("Error: No .kban/ board found in the current directory.");
        eprintln!("Run 'kban init' to initialize a new board here.");
        process::exit(1);
    }
}

fn cmd_version() {
    println!("kban {}", VERSION);
}

fn cmd_init() {
    let dir = kban_dir();
    // .kban/ is the parent of .kban/work/
    let kban_root = dir.parent().expect("kban_dir has no parent");
    if kban_root.is_dir() {
        log_warn(&format!(".kban already exists at {}", dir.display()));
        return;
    }

    for lane in all_lanes() {
        let lane_dir = dir.join(lane);
        fs::create_dir_all(&lane_dir)
            .unwrap_or_else(|e| die(&format!("Failed to create {}: {}", lane_dir.display(), e)));
        fs::write(lane_dir.join(".gitkeep"), "")
            .unwrap_or_else(|e| die(&format!("Failed to create .gitkeep: {}", e)));
    }

    fs::write(dir.join("backlog").join("SETUP-001.md"), SAMPLE_TICKET)
        .unwrap_or_else(|e| die(&format!("Failed to create sample ticket: {}", e)));

    log_success(&format!("Initialized .kban board at {}", dir.display()));
    log_info("Sample ticket created: SETUP-001 (backlog)");
    log_info("Run 'kban board' to see your board");
}

fn cmd_board() {
    let sep = "─".repeat(COL_WIDTH);

    let counts: Vec<usize> = LANES.iter().map(|l| lane_tickets(l).len()).collect();
    let lane_files: Vec<Vec<PathBuf>> = LANES.iter().map(|l| lane_tickets(l)).collect();
    let max = counts.iter().copied().max().unwrap_or(0);

    println!();

    // Header
    for (i, lane) in LANES.iter().enumerate() {
        let label = format!("{} ({})", lane.to_uppercase(), counts[i]);
        print!("{:<width$}  ", label, width = COL_WIDTH);
    }
    println!();

    // Separator
    for _ in LANES {
        print!("{}  ", sep);
    }
    println!();

    // Rows
    for i in 0..max {
        for files in &lane_files {
            let ticket = files.get(i)
                .and_then(|f| f.file_stem())
                .and_then(|s| s.to_str())
                .unwrap_or("");
            print!("{:<width$}  ", ticket, width = COL_WIDTH);
        }
        println!();
    }
    println!();
}

fn cmd_list(args: &[String]) {
    let lane_arg = args.first().map(String::as_str).unwrap_or("all");

    let lanes: Vec<&str> = if lane_arg == "all" {
        LANES.to_vec()
    } else {
        vec![lane_arg]
    };

    for lane in lanes {
        let files = lane_tickets(lane);
        let mut printed_header = false;
        for f in &files {
            if lane_arg == "all" && !printed_header {
                println!("{}", colored(ANSI_YELLOW, &format!("[{}]", lane)));
                printed_header = true;
            }
            let tid = f.file_stem().and_then(|s| s.to_str()).unwrap_or("");
            let blocked = get_field(f, "blocked")
                .map(|v| v.to_lowercase() == "true")
                .unwrap_or(false);
            if blocked {
                println!("{} {}", tid, colored(ANSI_RED, "[BLOCKED]"));
            } else {
                println!("{}", tid);
            }
        }
    }
}

fn cmd_tickets(args: &[String]) {
    let filter = args.first().map(String::as_str);
    let lanes: Vec<&str> = if let Some(lane) = filter {
        if !LANES.contains(&lane) {
            die(&format!("Invalid lane: {}. Valid: {}", lane, LANES.join(" ")));
        }
        vec![lane]
    } else {
        LANES.to_vec()
    };

    const ID_W: usize = 14;
    const LANE_W: usize = 9;
    const PRIO_W: usize = 8;

    println!("{:<ID_W$}  {:<LANE_W$}  {:<PRIO_W$}  {}", "ID", "LANE", "PRIORITY", "TITLE");
    println!("{}", "─".repeat(70));

    for lane in &lanes {
        for f in lane_tickets(lane) {
            let tid = f.file_stem().and_then(|s| s.to_str()).unwrap_or("").to_string();
            let title = get_field(&f, "title").unwrap_or_else(|| tid.clone());
            let priority = get_field(&f, "priority").unwrap_or_else(|| "medium".to_string());
            let deps = get_field(&f, "depends_on").unwrap_or_default();
            let blocked = get_field(&f, "blocked")
                .map(|v| v.to_lowercase() == "true")
                .unwrap_or(false);

            let suffix = if blocked {
                format!(" {}", colored(ANSI_RED, "[BLOCKED]"))
            } else if !deps.is_empty() && deps != "[]" {
                format!(" {}", colored(ANSI_BLUE, &format!("[deps: {}]", deps)))
            } else {
                String::new()
            };

            print!("{:<ID_W$}  {:<LANE_W$}  {:<PRIO_W$}  {}", tid, lane, priority, title);
            println!("{}", suffix);
        }
    }
}

fn cmd_show(args: &[String]) {
    let id = args.first().unwrap_or_else(|| die("Usage: kban show <id>"));
    let path = find_ticket(id).unwrap_or_else(|| die(&format!("Ticket not found: {}", id)));
    let lane = get_lane(id);
    println!("{} {}", colored(ANSI_BLUE, &format!("[{}]", lane)), id);
    println!("─────────────────────────────────────");
    let content = fs::read_to_string(&path)
        .unwrap_or_else(|e| die(&format!("Cannot read ticket: {}", e)));
    print!("{}", content);
}

fn cmd_next() {
    for f in lane_tickets("ready") {
        if deps_met(&f) {
            let id = f.file_stem().and_then(|s| s.to_str()).unwrap_or("");
            println!("{}", id);
            return;
        }
    }
    log_warn("No actionable tickets in ready");
    process::exit(1);
}

fn cmd_create(args: &[String]) {
    if args.is_empty() {
        die("Usage: kban create <id> --title \"...\" [--priority high|medium|low] [--lane backlog|ready|doing|done] [--depends-on ID1,ID2]");
    }

    let id = &args[0];
    validate_ticket_id(id);

    let mut title = String::new();
    let mut priority = "medium".to_string();
    let mut lane = "backlog".to_string();
    let mut depends_on = String::new();

    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "--title" => { i += 1; title = args.get(i).cloned().unwrap_or_default(); }
            "--priority" => { i += 1; priority = args.get(i).cloned().unwrap_or_default(); }
            "--lane" => { i += 1; lane = args.get(i).cloned().unwrap_or_default(); }
            "--depends-on" => { i += 1; depends_on = args.get(i).cloned().unwrap_or_default(); }
            other => die(&format!("Unknown option: {}", other)),
        }
        i += 1;
    }

    if title.is_empty() {
        die("--title is required");
    }
    match priority.as_str() {
        "high" | "medium" | "low" => {}
        _ => die(&format!("Invalid priority: {}. Valid: high, medium, low", priority)),
    }
    if !LANES.contains(&lane.as_str()) {
        die(&format!("Invalid lane: {}. Valid: {}", lane, LANES.join(" ")));
    }
    if let Some(_) = find_ticket(id) {
        let existing_lane = get_lane(id);
        die(&format!("Ticket already exists: {} (in {})", id, existing_lane));
    }

    let deps_yaml = if depends_on.is_empty() {
        "[]".to_string()
    } else {
        format!("[{}]", depends_on.replace(',', ", "))
    };

    let content = format!(
        "---\ntitle: {title}\npriority: {priority}\ndepends_on: {deps_yaml}\n---\n\n## Goal\n\n{title}\n\n## Tasks\n\n- [ ] TODO\n"
    );

    let dest = kban_dir().join(&lane).join(format!("{}.md", id));
    fs::write(&dest, content)
        .unwrap_or_else(|e| die(&format!("Failed to create ticket: {}", e)));
    log_success(&format!("Created {} in {}: {}", id, lane, title));
}

fn do_move(id: &str, target: &str) {
    validate_ticket_id(id);

    if !all_lanes().contains(&target) {
        die(&format!(
            "Invalid lane: {}. Valid: {} {}",
            target,
            LANES.join(" "),
            ARCHIVE_LANE
        ));
    }

    let path = find_ticket(id).unwrap_or_else(|| die(&format!("Ticket not found: {}", id)));
    let current = get_lane(id);

    if current == target {
        log_warn(&format!("{} is already in {}", id, target));
        return;
    }

    let dest = kban_dir().join(target).join(format!("{}.md", id));
    fs::rename(&path, &dest)
        .unwrap_or_else(|e| die(&format!("Failed to move ticket: {}", e)));
    log_success(&format!("{}: {} → {}", id, current, target));
}

fn cmd_move(args: &[String]) {
    if args.len() < 2 {
        die("Usage: kban move <id> <lane>");
    }
    do_move(&args[0], &args[1]);
}

fn cmd_start(args: &[String]) {
    let id = args.first().unwrap_or_else(|| die("Usage: kban start <id>"));
    do_move(id, "doing");
}

fn cmd_done(args: &[String]) {
    let id = args.first().unwrap_or_else(|| die("Usage: kban done <id>"));
    do_move(id, "done");
}

fn cmd_block(args: &[String]) {
    let id = args.first().unwrap_or_else(|| die("Usage: kban block <id>"));
    let path = find_ticket(id).unwrap_or_else(|| die(&format!("Ticket not found: {}", id)));
    let content = fs::read_to_string(&path)
        .unwrap_or_else(|e| die(&format!("Cannot read ticket: {}", e)));
    fs::write(&path, set_blocked_in_content(&content, true))
        .unwrap_or_else(|e| die(&format!("Cannot write ticket: {}", e)));
    log_success(&format!("{} marked as blocked", id));
}

fn cmd_unblock(args: &[String]) {
    let id = args.first().unwrap_or_else(|| die("Usage: kban unblock <id>"));
    let path = find_ticket(id).unwrap_or_else(|| die(&format!("Ticket not found: {}", id)));
    let content = fs::read_to_string(&path)
        .unwrap_or_else(|e| die(&format!("Cannot read ticket: {}", e)));
    fs::write(&path, set_blocked_in_content(&content, false))
        .unwrap_or_else(|e| die(&format!("Cannot write ticket: {}", e)));
    log_success(&format!("{} unblocked", id));
}

fn cmd_promote() {
    let files = lane_tickets("backlog");
    let mut promoted = 0usize;

    for f in files {
        let bid = f.file_stem().and_then(|s| s.to_str()).unwrap_or("").to_string();
        let blocked = get_field(&f, "blocked")
            .map(|v| v.to_lowercase() == "true")
            .unwrap_or(false);
        if deps_met(&f) && !blocked {
            let dest = kban_dir().join("ready").join(format!("{}.md", bid));
            fs::rename(&f, &dest)
                .unwrap_or_else(|e| die(&format!("Failed to promote {}: {}", bid, e)));
            log_success(&format!("{}: backlog → ready", bid));
            promoted += 1;
        }
    }

    if promoted == 0 {
        log_warn("No eligible tickets to promote");
    }
}

fn cmd_archive(args: &[String]) {
    let id = args.first().unwrap_or_else(|| die("Usage: kban archive <id>"));
    let path = find_ticket(id).unwrap_or_else(|| die(&format!("Ticket not found: {}", id)));
    let current = get_lane(id);
    if current == ARCHIVE_LANE {
        log_warn(&format!("{} is already archived", id));
        return;
    }
    let dest = kban_dir().join(ARCHIVE_LANE).join(format!("{}.md", id));
    fs::rename(&path, &dest)
        .unwrap_or_else(|e| die(&format!("Failed to archive ticket: {}", e)));
    log_success(&format!("{}: {} → archive", id, current));
}

fn cmd_unarchive(args: &[String]) {
    let id = args.first().unwrap_or_else(|| die("Usage: kban unarchive <id>"));
    let path = kban_dir().join(ARCHIVE_LANE).join(format!("{}.md", id));
    if !path.is_file() {
        die(&format!("Ticket not found in archive: {}", id));
    }
    let dest = kban_dir().join("done").join(format!("{}.md", id));
    fs::rename(&path, &dest)
        .unwrap_or_else(|e| die(&format!("Failed to unarchive ticket: {}", e)));
    log_success(&format!("{}: archive → done", id));
}

fn cmd_delete(args: &[String]) {
    let id = args.first().unwrap_or_else(|| die("Usage: kban delete <id>"));
    let path = find_ticket(id).unwrap_or_else(|| die(&format!("Ticket not found: {}", id)));
    let lane = get_lane(id);
    fs::remove_file(&path)
        .unwrap_or_else(|e| die(&format!("Failed to delete ticket: {}", e)));
    log_success(&format!("Deleted {} (was in {})", id, lane));
}

fn cmd_serve() {
    let script = find_serve_script()
        .unwrap_or_else(|| die("Web server script not found: web/serve.py"));

    use std::os::unix::process::CommandExt;
    let err = process::Command::new("python3").arg(&script).exec();
    die(&format!("Failed to exec python3: {}", err));
}

fn cmd_install(args: &[String]) {
    if args.is_empty() {
        die("Usage: kban install skill <user|project> [-f]");
    }
    match args[0].as_str() {
        "skill" => cmd_install_skill(&args[1..]),
        other => die(&format!("Unknown install type: {}. Supported: skill", other)),
    }
}

fn cmd_install_skill(args: &[String]) {
    let mut scope = String::new();
    let mut force = false;

    for arg in args {
        match arg.as_str() {
            "-f" | "--force" => force = true,
            s => scope = s.to_string(),
        }
    }

    if scope.is_empty() {
        let home = env::var("HOME").unwrap_or_default();
        println!("Where do you want to install the kban skill?");
        println!(
            "  [1] user     → {}/.claude/skills/kban/ (available in all projects)",
            home
        );
        println!("  [2] project  → ./.claude/skills/kban/ (this project only)");
        print!("Choose [1/2]: ");
        io::stdout().flush().ok();

        let mut choice = String::new();
        io::stdin().read_line(&mut choice).ok();

        scope = match choice.trim() {
            "1" | "user" => "user".to_string(),
            "2" | "project" => "project".to_string(),
            other => die(&format!("Invalid choice: {}. Enter 1 or 2.", other)),
        };
    }

    let home = env::var("HOME").unwrap_or_default();
    let dest_dir = match scope.as_str() {
        "user" => PathBuf::from(&home).join(".claude").join("skills").join("kban"),
        "project" => PathBuf::from(".claude").join("skills").join("kban"),
        other => die(&format!("Invalid scope: {}. Use 'user' or 'project'.", other)),
    };

    let dest = dest_dir.join("SKILL.md");
    if dest.is_file() && !force {
        log_warn(&format!(
            "{} already exists — skipping (use -f to overwrite)",
            dest.display()
        ));
        return;
    }

    fs::create_dir_all(&dest_dir)
        .unwrap_or_else(|e| die(&format!("Failed to create directory: {}", e)));
    fs::write(&dest, SKILL_MD)
        .unwrap_or_else(|e| die(&format!("Failed to write skill: {}", e)));
    log_success(&format!("Installed kban skill → {}", dest.display()));
    log_info("Run 'kban init' first if you haven't set up the board yet");
}

// ─── Main ─────────────────────────────────────────────────────────────────────

fn main() {
    let args: Vec<String> = env::args().collect();

    if args.len() < 2 {
        usage();
        return;
    }

    let cmd = &args[1];
    let rest: Vec<String> = args[2..].to_vec();

    // Commands that work without an initialized board
    match cmd.as_str() {
        "version" | "-h" | "--help" | "init" | "install" => {}
        _ => check_board_exists(),
    }

    match cmd.as_str() {
        "version" => cmd_version(),
        "init" => cmd_init(),
        "install" => cmd_install(&rest),
        "board" => cmd_board(),
        "create" => cmd_create(&rest),
        "list" => cmd_list(&rest),
        "show" => cmd_show(&rest),
        "next" => cmd_next(),
        "start" => cmd_start(&rest),
        "done" => cmd_done(&rest),
        "move" => cmd_move(&rest),
        "promote" => cmd_promote(),
        "block" => cmd_block(&rest),
        "unblock" => cmd_unblock(&rest),
        "archive" => cmd_archive(&rest),
        "unarchive" => cmd_unarchive(&rest),
        "tickets" => cmd_tickets(&rest),
        "delete" => cmd_delete(&rest),
        "serve" => cmd_serve(),
        "-h" | "--help" => usage(),
        _ => die(&format!(
            "Unknown command: {}. Use 'kban --help' for usage.",
            cmd
        )),
    }
}
