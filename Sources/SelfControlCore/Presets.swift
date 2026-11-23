import Foundation

/// Gotowe listy domen do dodania jednym kliknięciem.
public struct Preset: Identifiable, Equatable {
    public var id: String { name }
    public let name: String
    public let domains: [String]

    public static let all: [Preset] = [
        Preset(name: "Social media", domains: [
            "facebook.com", "instagram.com", "x.com", "twitter.com", "tiktok.com", "threads.net",
            "bsky.app", "linkedin.com", "pinterest.com", "snapchat.com", "reddit.com", "tumblr.com",
        ]),
        Preset(name: "Wideo i streaming", domains: [
            "youtube.com", "twitch.tv", "kick.com", "netflix.com", "primevideo.com", "disneyplus.com",
            "max.com", "player.pl", "cda.pl", "vod.pl", "9gag.com",
        ]),
        Preset(name: "Newsy", domains: [
            "onet.pl", "wp.pl", "interia.pl", "gazeta.pl", "o2.pl", "money.pl", "businessinsider.com.pl",
            "tvn24.pl", "polsatnews.pl", "rmf24.pl", "radiozet.pl", "tvp.info", "wyborcza.pl", "rp.pl",
            "pudelek.pl", "plotek.pl", "pomponik.pl", "natemat.pl", "wprost.pl", "fakt.pl", "se.pl",
            "news.google.com", "bbc.com", "cnn.com", "theguardian.com", "nytimes.com",
        ]),
        Preset(name: "Sport", domains: [
            "meczyki.pl", "sport.pl", "przegladsportowy.onet.pl", "sportowefakty.wp.pl", "weszlo.com",
            "transfermarkt.pl", "flashscore.pl", "livescore.com", "goal.pl", "laczynaspilka.pl",
        ]),
        Preset(name: "Humor i rozrywka", domains: [
            "wykop.pl", "joemonster.pl", "kwejk.pl", "demotywatory.pl", "jbzd.com.pl", "mistrzowie.org",
            "besty.pl", "9gag.com", "imgur.com", "kotaku.com",
        ]),
        Preset(name: "Zakupy", domains: [
            "allegro.pl", "olx.pl", "amazon.pl", "aliexpress.com", "temu.com", "shein.com",
            "zalando.pl", "ceneo.pl", "vinted.pl", "otomoto.pl", "otodom.pl",
        ]),
    ]
}
