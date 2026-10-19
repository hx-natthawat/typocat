import Foundation

/// What kind of app has focus. Terminals and editors get extra protection for
/// command names that look like wrong-layout noise (`git` → `เพะ`).
public enum AppCategory: String, Sendable {
    case terminal, code, chat, general

    public init(bundleID: String?) {
        guard let id = bundleID?.lowercased() else { self = .general; return }
        if Self.terminals.contains(id) { self = .terminal }
        else if Self.editors.contains(id) || id.hasPrefix("com.jetbrains.") { self = .code }
        else if Self.messengers.contains(id) { self = .chat }
        else { self = .general }
    }

    static let terminals: Set<String> = [
        "com.apple.terminal", "com.googlecode.iterm2", "dev.warp.warp-stable", "net.kovidgoyal.kitty",
        "com.github.wez.wezterm", "com.mitchellh.ghostty", "io.alacritty",
    ]
    static let editors: Set<String> = [
        "com.microsoft.vscode", "com.microsoft.vscodeinsiders", "com.apple.dt.xcode", "com.sublimetext.4",
        "com.sublimetext.3", "com.todesktop.230313mzl4w4u92", "dev.zed.zed", "com.vscodium",
    ]
    static let messengers: Set<String> = [
        "net.whatsapp.whatsapp", "com.apple.mobilesms", "ru.keepcoder.telegram", "org.telegram.desktop",
        "com.tinyspeck.slackmacgap", "com.microsoft.teams2", "com.microsoft.teams",
        "org.whispersystems.signal-desktop", "jp.naver.line.mac",
    ]
}

/// Words that must never be "corrected" even though they are not dictionary words.
public enum ProtectedWords {
    /// Product and tech names, protected everywhere.
    public static let tech: Set<String> = [
        "git", "npm", "api", "aws", "mac", "macos", "ios", "cmd", "jira", "vscode", "github", "gitlab",
        "docker", "kubectl", "json", "yaml", "http", "https", "url", "sql", "css", "html", "js", "ts",
        "npx", "pnpm", "repo", "pr", "ci", "cd", "ui", "ux", "ok", "lol", "btw", "imo", "tbh",
    ]

    /// Shell commands, protected only in terminals and code editors.
    public static let commands: Set<String> = Set("""
        ls cd pwd pushd popd dirs mkdir rmdir touch cat less more head tail tac stat file tree find locate \
        which whereis readlink realpath grep egrep fgrep rg ack awk sed cut sort uniq tee xargs diff patch \
        chmod chown chgrp umask sudo passwd tar zip unzip gzip gunzip bzip2 zcat echo printf env export set \
        unset alias unalias source history clear exit top htop btop kill killall pkill pgrep jobs nohup nice \
        renice time watch uptime free uname hostname sysctl lsof dmesg systemctl journalctl launchctl crontab \
        mount umount ssh scp sftp rsync ssh-keygen ssh-add ssh-copy-id curl wget ping traceroute dig nslookup \
        host ifconfig ipconfig netstat nmap telnet openssl gpg ngrok git svn glab gh docker docker-compose \
        podman kubectl helm minikube kubectx kubens terraform ansible vagrant aws gcloud heroku vercel netlify \
        flyctl doctl wrangler node deno bun python python3 ruby perl php lua java javac kotlin scala swift \
        swiftc clang gcc rustc dotnet dart npm npx yarn pnpm pip pip3 pipenv poetry uv conda gem bundle cargo \
        rustup brew port make cmake ninja bazel gradle mvn rails composer flutter pod vim nvim nano emacs code \
        subl tmux fzf ncdu exa eza psql mysql sqlite3 mongosh redis-cli pbcopy pbpaste mdfind diskutil \
        caffeinate plutil open defaults xcodebuild claude
        """.split(separator: " ").map(String.init))

    public static func contains(_ word: String, in category: AppCategory) -> Bool {
        let w = word.lowercased()
        if tech.contains(w) { return true }
        return (category == .terminal || category == .code) && commands.contains(w)
    }
}

/// The host name a website's language counts are kept under: what an address bar shows.
public enum WebsiteHost {
    /// "https://www.github.com/x" or "github.com/x" → "github.com". nil for pages without a
    /// host (a new tab, a file, a search typed into the address bar).
    public static func from(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: withScheme), let host = url.host?.lowercased(), host.contains("."),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
