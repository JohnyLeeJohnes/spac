# Changelog

Všechny podstatné změny v projektu. Formát vychází z [Keep a Changelog](https://keepachangelog.com/cs/1.1.0/),
verze se řídí [sémantickým verzováním](https://semver.org/lang/cs/).

## [1.0.0] - 2026-10-03

První vydání.

### Přidáno

- Akce vypnout (`/s`, výchozí), restartovat (`/r`), hibernovat (`/h`) a odhlásit (`/l`).
- Nastavení času předvolbami (15 min až 3 h) nebo ručně až do 23 h 59 min, včetně ladění šipkami
  a kolečkem myši.
- Přepínače pro vynucené zavření aplikací (`/f`), rychlé spuštění (`/hybrid`) a obnovení aplikací
  po startu (`/sg`, `/g`).
- Náhled přesného příkazu, který se spustí, a času, kdy k akci dojde.
- Obrazovka s odpočtem a tlačítkem Zrušit (`shutdown /a`).
- Tlačítko **Zrušit naplánované vypnutí** (`shutdown /a`) přímo ve formuláři. Zruší i vypnutí, které
  Spáč nenastavil.
- Odpočet vypnutí a restartu přežije zavření aplikace, po znovuotevření ho jde zrušit.
- Vlastní odpočet pro hibernaci a odhlášení, u kterých `shutdown.exe` přepínač `/t` nepodporuje.
- Hibernace se nenabízí, pokud je v systému vypnutá.
- Tmavý vzhled včetně titulkového pruhu okna.
- Ikona ve velikostech 16 až 256 px a `install.cmd`, který vytvoří zástupce v nabídce Start a na ploše.
- Spáč je skript v PowerShellu s oknem ve WPF, takže se nic nekompiluje ani neinstaluje a nevadí mu
  Smart App Control.

[1.0.0]: https://github.com/JohnyLeeJohnes/spac/releases/tag/v1.0.0
