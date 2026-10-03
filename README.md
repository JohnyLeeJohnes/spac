<p align="center">
  <img src="assets/spac.png" width="96" alt="Ikona aplikace Spáč">
</p>

<h1 align="center">Spáč</h1>

<p align="center">
  Malý časovač vypnutí pro Windows. Hezčí kabát pro <code>shutdown.exe</code>.
</p>

<p align="center">
  <img src="docs/formular.png" width="340" alt="Nastavení časovače">
  &nbsp;&nbsp;
  <img src="docs/odpocet.png" width="340" alt="Běžící odpočet">
</p>

Pustíš si film, nastavíš 1,5 hodiny a jdeš spát. Spáč zavolá `shutdown` se správnými přepínači a ukáže ti,
co přesně spouští.

- **Jeden soubor, 53 kB.** Žádná instalace, žádné závislosti, žádné procesy na pozadí.
- **Čtyři akce:** vypnout, restartovat, hibernovat, odhlásit.
- **Čas na dvě kliknutí:** předvolby od 15 minut do 3 hodin, nebo vlastní hodnota až 23 h 59 min.
- **Vidíš, co se stane:** přesný příkaz i čas, kdy na něj dojde.
- **Jde to vzít zpět:** tlačítko Zrušit funguje i po zavření a znovuotevření aplikace.

## Stažení

1. Stáhni `Spac.exe` z [posledního vydání](https://github.com/JohnyLeeJohnes/spac/releases/latest).
2. Ulož ho, kam chceš, a spusť.

Stačí Windows 10 nebo 11. Aplikace běží na .NET Frameworku 4.8, který je součástí systému.

> Soubor není digitálně podepsaný, takže Windows SmartScreen může při prvním spuštění zobrazit varování.
> Pokračuje se přes **Další informace → Přesto spustit**. Kdo nechce věřit cizímu `.exe`, může si ho
> [sestavit sám](#sestavení-ze-zdrojáků).

Tip: pravým tlačítkem na `Spac.exe` → **Připnout na hlavní panel** a máš ho na jedno kliknutí.

## Co který přepínač dělá

| V aplikaci | Příkaz | Poznámka |
| --- | --- | --- |
| Vypnout | `shutdown /s /t <sekundy>` | Výchozí akce. |
| Restartovat | `shutdown /r /t <sekundy>` | |
| Hibernovat | `shutdown /h` | Jen pokud je hibernace v systému zapnutá. |
| Odhlásit | `shutdown /l` | |
| Vynutit zavření aplikací | `/f` | Aplikace se zavřou bez ptaní, neuložená práce se ztratí. |
| Rychlé spuštění | `/hybrid` | Jen s `/s`. Hybridní vypnutí jako u položky Vypnout v nabídce Start. |
| Po startu znovu otevřít aplikace | `/sg` místo `/s`, `/g` místo `/r` | Windows po přihlášení obnoví aplikace, které to podporují. |
| Zrušit | `shutdown /a` | |

## Dobré vědět

- **Vypnutí a restart s odpočtem jsou vždy vynucené.** Jakmile je `/t` větší než nula, Windows si `/f`
  doplní samy. Přepínač je proto u těchto akcí zapnutý napevno. Než odejdeš, ulož si práci.
- **Vypnutí a restart hlídá Windows.** Spáče můžeš po naplánování zavřít. Když ho otevřeš znovu, ukáže
  běžící odpočet a nabídne zrušení.
- **Hibernaci a odhlášení hlídá Spáč.** `shutdown.exe` u `/h` a `/l` časovač neumí, takže odpočítává
  aplikace a příkaz spustí až na konci. Musí proto zůstat spuštěná, zavřením okna odpočet zrušíš.
- **`/hybrid` a `/sg` se vylučují.** `shutdown.exe` tu kombinaci odmítne, takže zapnutí jednoho přepínače
  vypne druhý.
- **Nové nastavení přepíše staré.** Pokud už nějaké vypnutí naplánované je (třeba z příkazové řádky),
  Spáč ho zruší a nastaví to svoje.
- **Režim spánku tu není.** `shutdown.exe` ho neumí a Spáč záměrně nedělá nic, co by nešlo napsat do
  příkazové řádky.

Naplánované vypnutí jde vždy zrušit i bez aplikace:

```
shutdown /a
```

Spáč si ukládá jediný soubor, `%LOCALAPPDATA%\Spac\pending`, a to jen po dobu běžícího odpočtu.

## Sestavení ze zdrojáků

Potřebuješ jen [.NET SDK](https://dotnet.microsoft.com/download) (ověřeno s verzí 10).

```
git clone https://github.com/JohnyLeeJohnes/spac.git
cd spac
dotnet build src -c Release -o dist
```

Výsledek je `dist\Spac.exe`.

### Kde co je

| Soubor | Obsah |
| --- | --- |
| `src/Shutdown.cs` | Skládání přepínačů, volání `shutdown.exe`, uložený stav odpočtu. |
| `src/MainWindow.xaml` | Rozložení okna. |
| `src/MainWindow.xaml.cs` | Chování okna: formulář, odpočet, tmavý titulkový pruh. |
| `src/App.xaml` | Barvy a styly ovládacích prvků. |
| `tools/make-icon.ps1` | Vygeneruje ikonu do `assets/`. |

Chceš jiné barvy? Celá paleta je na začátku `src/App.xaml`. Jiné předvolby času? Řádek s `Presets`
v `src/MainWindow.xaml`, hodnota `Tag` je počet minut.

## Přispívání

Forkuj, upravuj, posílej pull requesty. Změny se zapisují do [CHANGELOG.md](CHANGELOG.md).

## Licence

[MIT](LICENSE)

---

**In English:** Spáč ("the sleeper") is a tiny shutdown timer for Windows 10/11, a friendly UI on top of
`shutdown.exe`. Pick an action (shut down, restart, hibernate, log off), pick a delay, and it runs the
matching command and shows you exactly which one. Single 53 kB executable, no installer, no dependencies.
The interface is in Czech.
