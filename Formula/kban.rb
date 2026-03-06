class Kban < Formula
  desc "Simple filesystem-based kanban board for Claude Code agents"
  homepage "https://github.com/davidpellerin/homebrew-kban"
  url "https://github.com/davidpellerin/homebrew-kban/archive/refs/tags/v1.8.0.tar.gz"
  sha256 "9138d916948d1d217565152c212478fe97ca8ba2cd2dd17592181c581fcf99a6"
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
