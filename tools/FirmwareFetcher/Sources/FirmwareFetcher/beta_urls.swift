import Foundation

let pages = [
    "https://ipswbeta.dev/ios/27.x/27.2-beta",
    "https://ipswbeta.dev/ios/27.x/27.2-beta-2",
    "https://ipswbeta.dev/ios/27.x/27.2-beta-3",
    "https://ipswbeta.dev/ios/27.x/27.2-beta-4",
    "https://ipswbeta.dev/ios/27.x/27.2-rc",
]
let expression = try NSRegularExpression(
    pattern: #"https:[^\"'\\[:space:]]+\.ipsw"#
)

for page in pages {
    let url = URL(string: page)!
    var request = URLRequest(url: url)
    request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
    let (data, response) = try await URLSession.shared.data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    let html = String(decoding: data, as: UTF8.self)
    let range = NSRange(html.startIndex..., in: html)
    let matches = expression.matches(in: html, range: range).compactMap {
        Range($0.range, in: html).map { String(html[$0]) }
    }
    print("page=\(page) status=\(status) bytes=\(data.count) links=\(matches.count)")
    for link in Set(matches).sorted() where link.contains("iPhone19,2") {
        print(link)
    }
}
