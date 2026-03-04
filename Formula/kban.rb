class Kban < Formula
  desc "Simple filesystem-based kanban board for Claude Code agents"
  homepage "https://github.com/davidpellerin/homebrew-kban"
  url "https://github.com/davidpellerin/homebrew-kban/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "d872bb1075c07fd1d82f0f1244d3d1a61c52ba62e95af1321d865b22bb5beb5a"
  license "MIT"

  def install
    bin.install "bin/kban"
  end

  test do
    system "#{bin}/kban", "--help"
  end
end
