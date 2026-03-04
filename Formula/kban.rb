class Kban < Formula
  desc "Simple filesystem-based kanban board for Claude Code agents"
  homepage "https://github.com/davidpellerin/homebrew-kban"
  url "https://github.com/davidpellerin/homebrew-kban/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "<PLACEHOLDER>"
  license "MIT"

  def install
    bin.install "bin/kban"
  end

  test do
    system "#{bin}/kban", "--help"
  end
end
