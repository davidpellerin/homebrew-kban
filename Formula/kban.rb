class Kban < Formula
  desc "Simple filesystem-based kanban board for Claude Code agents"
  homepage "https://github.com/davidpellerin/homebrew-kban"
  url "https://github.com/davidpellerin/homebrew-kban/archive/refs/tags/v1.2.0.tar.gz"
  sha256 "21d13c4dc079cbfa4fb0bc89b9ac20b3634a150584dda56af330b289c70e0956"
  license "MIT"

  def install
    bin.install "bin/kban"
    (prefix/"web").install "web/serve.py", "web/index.html"
  end

  test do
    system "#{bin}/kban", "--help"
  end
end
