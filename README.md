# Self-Control

Blokada rozpraszających stron na macOS — ręcznie na czas albo wg harmonogramu (dni + godziny, także przez północ).

- `selfcontrold` — demon root (launchd), co 5 s ustawia `/etc/hosts`. Podczas blokady zmiany mogą ją tylko zaostrzyć; usunięcie domeny, skrócenie czasu czy wyłączenie aktywnego harmonogramu wchodzi w życie po jej końcu.
- `SelfControlApp` — kłódka w pasku menu: start blokady, lista domen, harmonogramy.

```sh
scripts/install.sh     # build + instalacja (sudo)
scripts/uninstall.sh   # tylko poza blokadą
swift test
```

Pliki: żądanie od aplikacji `/Users/Shared/SelfControl/request.json`, stan demona `/Library/Application Support/SelfControl/state.json`, log `/var/log/selfcontrold.log`.
