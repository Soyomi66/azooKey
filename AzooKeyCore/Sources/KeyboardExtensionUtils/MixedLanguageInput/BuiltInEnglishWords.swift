//
//  BuiltInEnglishWords.swift
//  AzooKeyCore
//
//  日英混在入力で使う、同梱の英単語の辞書。
//
//  OSのスペルチェッカーは、製品名やサービス名を正しい大文字小文字でしか英単語と認めない（`iPhone`は正しく、`iphone`は誤り）。
//  ローマ字入力では小文字で打つので、ここに載せた語は小文字で引いて英単語として扱う。
//

/// 同梱の英単語の辞書。小文字で引く。
enum BuiltInEnglishWords {
    /// 日本語の文の中に小文字のまま混ぜて打たれる、製品・サービス・会社・技術の英語名の一覧。
    /// 打たれた英字を小文字にしてこの一覧と照らし、一致した語はかなに変換せず、ここに書いた表記で候補に出す。
    /// 小文字の綴りをローマ字で読むと別の意味の日本語になる語（「しり」と読める Siri など）と、
    /// 日本語の語を打つ途中の綴りと同じになる語（machi を打つ途中に現れる Mac など）は入れていない。
    /// ローマ字で読めても、読みが同じものを指す語（「あまぞん」と読める Amazon など）は入れている。
    static let properNouns: [String] = [
        "iPhone", "iPad", "iPadOS", "iOS", "MacBook", "macOS", "iCloud", "AirPods", "AirDrop",
        "AirPlay", "iTunes", "iMessage", "FaceTime", "watchOS", "Xcode", "Swift", "SwiftUI", "Apple",
        "Microsoft", "Windows", "Excel", "Word", "PowerPoint", "Outlook", "Teams", "OneDrive",
        "OneNote", "PowerShell", "Azure", "Copilot", "Edge", "LinkedIn", "Xbox", "Google", "Gmail",
        "YouTube", "Android", "Chrome", "Chromebook", "Gemini", "Firebase", "Flutter", "Kotlin",
        "Kubernetes", "TensorFlow", "Amazon", "AWS", "Kindle", "Alexa", "Twitch", "Facebook",
        "Instagram", "WhatsApp", "Twitter", "TikTok", "Discord", "Slack", "LINE", "Telegram", "Reddit",
        "Pinterest", "Bluesky", "Mastodon", "Misskey", "Zoom", "Spotify", "Netflix", "Uber", "Airbnb",
        "PayPal", "PayPay", "Stripe", "Shopify", "Wikipedia", "Dropbox", "Notion", "Figma", "Canva",
        "Trello", "Chatwork", "Salesforce", "Qiita", "pixiv", "WordPress", "Duolingo", "Udemy",
        "Kaggle", "Firefox", "PASMO", "Steam", "PlayStation", "Minecraft", "Fortnite", "Roblox",
        "Valorant", "JavaScript", "TypeScript", "Python", "Java", "Ruby", "Rust", "PHP", "Perl",
        "MATLAB", "SQL", "MySQL", "PostgreSQL", "SQLite", "MongoDB", "Redis", "Oracle", "Docker",
        "Terraform", "Jenkins", "Nginx", "Apache", "Linux", "Ubuntu", "Debian", "VMware", "GitHub",
        "GitLab", "npm", "Homebrew", "Vim", "Webpack", "Vite", "React", "Vue", "Angular", "jQuery",
        "Django", "Laravel", "FastAPI", "PyTorch", "NumPy", "Jupyter", "Tailwind", "GraphQL", "JSON",
        "YAML", "HTML", "CSS", "Markdown", "LaTeX", "PDF", "USB", "HDMI", "GPS", "URL", "Bluetooth",
        "Vercel", "Cloudflare", "Supabase", "ChatGPT", "OpenAI", "Claude", "Anthropic", "Midjourney",
        "DeepL", "DeepMind", "Adobe", "Photoshop", "Illustrator", "Lightroom", "InDesign", "AutoCAD",
        "Blender", "Unity", "Obsidian", "Arduino", "Bitcoin", "Ethereum", "Intel", "AMD", "NVIDIA",
        "Qualcomm", "Ryzen", "GeForce", "Samsung", "Galaxy", "Huawei", "Xiaomi",
        "Lenovo", "Dell", "Logicool", "GoPro", "Tesla", "IBM", "Cisco",
    ]

    /// 固有名詞ではないが、スペルチェッカーが知らないことがある語（小文字で書く）
    static let words: [String] = [
        "npm", "npx", "nodejs", "localhost", "kubectl", "nginx", "dotfiles", "devops", "frontend", "backend",
        "middleware", "plugin", "plugins", "config", "configs", "repo", "repos", "regex", "async", "stdin", "stdout",
        "stderr", "sudo", "chmod", "grep", "curl", "wget", "tmux", "vim", "neovim", "zsh", "bash", "git", "wifi",
        "toml", "scss", "webhook", "webhooks", "linter", "refactor", "refactoring", "commit", "commits", "rebase",
        "smartphone", "smartwatch", "app", "apps", "email", "emails", "online", "offline", "login", "logout", "signup",
    ]

    /// 小文字の綴りから、固有名詞の正しい表記を引く表
    static let properNounSpellings: [String: String] = {
        var spellings: [String: String] = [:]
        for word in properNouns {
            spellings[word.lowercased()] = spellings[word.lowercased()] ?? word
        }
        return spellings
    }()

    /// 載せた語の小文字の綴り
    static let lowercasedWords: Set<String> = Set(properNouns.map { $0.lowercased() } + words)

    /// 載せた語の頭（小文字）。`hasEnglishWord(withPrefix:)`に使う
    static let prefixes: Set<String> = {
        var prefixes: Set<String> = []
        for word in lowercasedWords {
            for length in 1 ... word.count {
                prefixes.insert(String(word.prefix(length)))
            }
        }
        return prefixes
    }()
}
