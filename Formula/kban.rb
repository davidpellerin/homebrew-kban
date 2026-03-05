class Kban < Formula
  desc "Simple filesystem-based kanban board for Claude Code agents"
  homepage "https://github.com/davidpellerin/homebrew-kban"
  url "https://github.com/davidpellerin/homebrew-kban/archive/refs/tags/v1.3.0.tar.gz"
  sha256 "fcc81af0b956977c445cb881941a4bdb39650d9d46ce3eafe8363ff968282593"
  license "MIT"

  def install
    bin.install "bin/kban"
    (prefix/"web").install "web/serve.py", "web/index.html"
    (prefix/"templates").install Dir["templates/*"]
  end

  test do
    system "#{bin}/kban", "--help"
  end
end
