class Kban < Formula
  desc "Simple filesystem-based kanban board for Claude Code agents"
  homepage "https://github.com/davidpellerin/homebrew-kban"
  url "https://github.com/davidpellerin/homebrew-kban/archive/refs/tags/v1.11.0.tar.gz"
  sha256 "65ca08f0a924136c7643dc5920c5bd54d337b15c83da25329d805c86cbe57d6c"
  license "MIT"

  depends_on "python@3"

  def install
    bin.install "bin/kban"
    (prefix/"web").install "web/serve.py", "web/index.html"
    (prefix/"templates").install Dir["templates/*"]
  end

  test do
    system "#{bin}/kban", "--help"
    assert_match "kban #{version}", shell_output("#{bin}/kban version")

    # Init creates the expected lane directories
    system "#{bin}/kban", "init"
    assert_predicate testpath/".kban"/"work"/"backlog", :directory?
    assert_predicate testpath/".kban"/"work"/"ready", :directory?
    assert_predicate testpath/".kban"/"work"/"doing", :directory?
    assert_predicate testpath/".kban"/"work"/"done", :directory?
    assert_predicate testpath/".kban"/"work"/"archive", :directory?

    # Board and list work after init
    system "#{bin}/kban", "board"
    assert_match "SETUP-001", shell_output("#{bin}/kban list backlog")

    # Full ticket lifecycle: backlog → ready → doing → done
    system "#{bin}/kban", "move", "SETUP-001", "ready"
    assert_match "SETUP-001", shell_output("#{bin}/kban list ready")

    system "#{bin}/kban", "start", "SETUP-001"
    assert_match "SETUP-001", shell_output("#{bin}/kban list doing")

    system "#{bin}/kban", "done", "SETUP-001"
    assert_match "SETUP-001", shell_output("#{bin}/kban list done")
  end
end
