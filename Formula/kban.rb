class Kban < Formula
  desc "Simple filesystem-based kanban board for Claude Code agents"
  homepage "https://github.com/davidpellerin/homebrew-kban"
  url "https://github.com/davidpellerin/homebrew-kban/archive/refs/tags/v1.1.0.tar.gz"
  sha256 "bc08ab05f1ceb5651a8f81e475abd27f7fd27d7b715a2dca0ec3ea7599855d39"
  license "MIT"

  def install
    bin.install "bin/kban"
    (prefix/"web").install "web/serve.py", "web/index.html"
  end

  test do
    system "#{bin}/kban", "--help"
  end
end
