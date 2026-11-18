class DbManager < Formula
  desc "Interactive dump/restore of PostgreSQL + Citus databases, with dumps kept locally or in S3"
  homepage "https://github.com/sap1enza/db-manager"
  url "https://github.com/sap1enza/db-manager.git", tag: "v0.1.1"
  license "MIT"

  depends_on "awscli"
  depends_on "postgresql@17"

  def install
    libexec.install "db-manager"
    (bin/"db-manager").write_env_script libexec/"db-manager",
      PATH: "#{Formula["postgresql@17"].opt_bin}:$PATH"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/db-manager --version")
  end
end
