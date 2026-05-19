class Kban < Formula
  desc "Simple filesystem-based kanban board for Claude Code agents"
  homepage "https://github.com/davidpellerin/homebrew-kban"
  version "2.0.0"
  license "MIT"

  on_macos do
    on_arm do
      url "https://github.com/davidpellerin/homebrew-kban/releases/download/v2.0.0/kban-aarch64-apple-darwin.tar.gz"
      sha256 "fca565f4ea423acc2bc2327dbc5bfc097051ce9b0581769dc768b87786302769"
    end
    on_intel do
      url "https://github.com/davidpellerin/homebrew-kban/releases/download/v2.0.0/kban-x86_64-apple-darwin.tar.gz"
      sha256 "57a46190da683317f1380433dabfd9eee1e296912e678842837d5f2db94c924f"
    end
  end

  on_linux do
    on_intel do
      url "https://github.com/davidpellerin/homebrew-kban/releases/download/v2.0.0/kban-x86_64-unknown-linux-gnu.tar.gz"
      sha256 "c9d6b833dd8431171acc09258d8d210b583153263c9314af8565fef36f896835"
    end
  end

  depends_on "python@3"

  def install
    bin.install "kban"
    (prefix/"web").install "web/serve.py", "web/index.html"
    (prefix/"templates").install Dir["templates/*"]
  end

  test do
    system "#{bin}/kban", "--help"
    assert_match "kban #{version}", shell_output("#{bin}/kban version")

    system "#{bin}/kban", "init"
    assert_predicate testpath/".kban"/"work"/"backlog", :directory?
    assert_predicate testpath/".kban"/"work"/"ready", :directory?
    assert_predicate testpath/".kban"/"work"/"doing", :directory?
    assert_predicate testpath/".kban"/"work"/"done", :directory?
    assert_predicate testpath/".kban"/"work"/"archive", :directory?

    system "#{bin}/kban", "board"
    assert_match "SETUP-001", shell_output("#{bin}/kban list backlog")

    system "#{bin}/kban", "move", "SETUP-001", "ready"
    assert_match "SETUP-001", shell_output("#{bin}/kban list ready")

    system "#{bin}/kban", "start", "SETUP-001"
    assert_match "SETUP-001", shell_output("#{bin}/kban list doing")

    system "#{bin}/kban", "done", "SETUP-001"
    assert_match "SETUP-001", shell_output("#{bin}/kban list done")
  end
end
