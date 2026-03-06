class Kban < Formula
  desc "Simple filesystem-based kanban board for Claude Code agents"
  homepage "https://github.com/davidpellerin/homebrew-kban"
  url "https://github.com/davidpellerin/homebrew-kban/archive/refs/tags/v1.4.0.tar.gz"
  sha256 "fb687862395a2677700b0ef7c85d05ad9ad732620b80cbe9148158cae4182731"
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
