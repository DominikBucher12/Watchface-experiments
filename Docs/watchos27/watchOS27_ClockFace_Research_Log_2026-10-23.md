# watchOS 27: Native Custom Watch Face / ClockFace Reverse Engineering

**Technický deník a předávací dokument — 23. října 2026**  
**Projekt:** Pip-Boy ciferník pro Apple Watch (nativní watch face)  
**Repozitář:** `~/Hacking/Watchface-experiments`  
**Aktivní větev při posledních experimentech:** `version/simulator27`  
**Stav k ~16:45 (Europe/Prague):** vykreslování a nativní discovery ve vlastním klonu **fungují**; integrace do originálního systémového `com.apple.clockface` **nebyla prokázána**.

> **Účel:** Tento soubor shrnuje rozsáhlé experimenty provedené během dne, včetně ověřených výsledků, selhání, relevantního kódu a pokračování. Je sestaven z konverzace, sdílených zdrojových souborů a výstupů testů. Rozlišuje **PROKÁZÁNO**, **NEPROKÁZÁNO** a **HYPOTÉZA**. Nejedná se o tvrzení, že vlastní ciferník je již nainstalovaný v systémové galerii hodinek.

## 1. Cíl a podmínka úspěchu

Cílem je **vlastní nativní Pip-Boy watch face** integrovaný do watchOS, nikoli běžná watchOS aplikace, která ciferník jen simuluje. Po stisknutí **Digital Crown** musí systém zobrazit vlastní ciferník v původním `com.apple.clockface`, stejně jako systémové ciferníky. Ideálně má jít vybrat v originální galerii a zachovat jej mezi aktivacemi aplikací a restartem.

**Co samo o sobě nestačí:** zobrazit UI ve vlastním `ClockFaceLab`, získat `PASS` z privátního `NTKFaceBundleLoader`, úspěšně upravit seznam `NTKFaceBundleManager` v klonu nebo odeslat požadavek na Argon XPC. Výsledné kritérium vyžaduje funkci v **originálním systémovém procesu a původní uživatelské cestě**.

## 2. Prostředí a omezení

| Vlastnost | Zjištěná hodnota |
|---|---|
| Platforma | watchOS 27.0 **Simulator**, arm64 |
| Simulované hodinky | Apple Watch Series 9 (45 mm) |
| Simulator UDID | `4E768962-9FDF-4EBD-BE25-2A2A9E257143` |
| Systémový bundle ID | `com.apple.clockface` |
| Izolovaný experimentální bundle ID | `dev.develodom.ClockFaceLab` |
| Lokální face-bundle ID | `dev.develodom.WatchFaceLab.LocalFaceBundle` |
| Face-bundle class | `MYLocalFaceBundle` |
| Model / renderer | `MYCustomFace` / `MYCustomFaceView` |
| Face style | `44` (`0x2c`) |
| Aktuální build | watchOS 27 simulator; původní privátní hlavičky vznikly pro starší watchOS 26.5 x86_64 a vyžadovaly portování |
| Shell zvyklosti | Spouštění z kořene repozitáře, bez `cd`; použít standardní `grep`, nikoliv `rg` |

Systémová aplikace původně pochází z runtime root, např.:

```text
/private/var/run/com.apple.security.cryptexd/mnt/watchOS_24R362/Library/Developer/CoreSimulator/Profiles/Runtimes/watchOS 27.0.simruntime/Contents/Resources/RuntimeRoot/Applications/ClockFace.app/ClockFace
```

Cesta závisí na instalaci Xcode a runtime. **Nezapisovali jsme do originální aplikace ani runtime rootu**; klon vznikal kopírováním do repozitáře.

Důležitá implementační okolnost: `~/Downloads/setup-clockface-lab-v2.sh` vždy znovu generuje `Experiments/ClockFaceLab/ClockFaceLabBootstrap.m`. Úpravy pouze výsledného `.m` souboru tedy další běh setupu přepíše. Trvalé změny bootstrapu dělat v **šabloně uvnitř setup skriptu**.

## 3. Architektura funkčního lokálního experimentu

```text
watchOS Simulator
├── Systémový Carousel / původní com.apple.clockface
│   └── původní discovery + nativní galerie (vlastní face zde dosud nepotvrzen)
│
└── Samostatná instalace dev.develodom.ClockFaceLab
    ├── klon ClockFace.app (vlastní bundle ID, ad-hoc podpis)
    ├── Frameworks/ClockFaceLabBootstrap.dylib
    │   ├── dlopen(NanoTimeKit)
    │   ├── dlopen(ClockKitUI)
    │   └── dlopen(MYCustomFaceExperiment.framework)
    ├── Frameworks/MYCustomFaceExperiment.framework
    │   ├── MYCustomFace / MYCustomFaceView
    │   ├── face discovery, factory/serialization, Argon read-only probes
    │   └── MYOwnedDiscovery + instance-only NTKFaceBundleManager bridge
    └── FaceBundles/MYLocalFaceBundle.bundle
        └── NSPrincipalClass: MYLocalFaceBundle
```

### Soubory projektu

- `Experiments/MYCustomFace.m` a `.h` — vlastní `NTKFace`, renderer, digitální time view; aktuální face style 44.
- `Experiments/LocalFaceBundle/MYLocalFaceBundle.m` — subclass `NTKFaceBundle`; metadata a factory pro galerii.
- `Experiments/MYBundleDiscovery.m` — izolovaný loader, verifikace identity a round-trip serializace.
- `Experiments/MYOwnedDiscovery.m` — kontrolovaná instalace/check/removal bridge ve vlastním host procesu; **vkládá** `#include "MYClockFaceBridge.m"`.
- `Experiments/MYClockFaceBridge.m` — runtime bridge sdíleného face-bundle manageru; jeho kopie ze starších artefaktů může být ještě x86_64-only. **Rozhodující je aktuální obsah repozitáře po portování na arm64/watchOS 27.**
- `Experiments/MYArgonDescriptorV3.m` — Argon / descriptor experimenty včetně runtime method dumpu a `NTKInternalBuild()` checku.
- `Experiments/build-watchos27-simulator.sh` — sestavení frameworku a lokálního bundlu pro watchOS simulator.
- `~/Downloads/setup-clockface-lab-v2.sh` — vytvoření, podepsání a instalace klonu s bootstrapem.
- `Experiments/ClockFaceLab/ClockFaceLab.app` — generovaný klon aplikace.
- `Experiments/Build/Simulator/MYCustomFaceExperiment.framework` — výstupní framework.
- `Experiments/Build/Simulator/FaceBundles/MYLocalFaceBundle.bundle` — výstupní face bundle.
- `Experiments/Build/Simulator/ClockFaceInjectionProbe.dylib` — minimální logovací dylib pro pokus s původním procesem.
- `Experiments/ntk_argon_xrefs.py` — vlastní Mach-O/ARM64 xref analyzátor; po opravě UTF-8 dekódování funkční.

Ne všechny výše uvedené cesty musí existovat v generickém checkoutu. Některé byly vytvořené během interaktivních pokusů; části setupu a některé patch skripty jsou v `~/Downloads`.

## 4. Co bylo skutečně úspěšné

### 4.1 Vlastní model a renderer

**PROKÁZÁNO:** `MYCustomFace` se vytváří jako skutečný `NTKFace`; `MYCustomFaceView` jako `NTKFaceView`. Ve vlastním `ClockFaceLab` se ciferník viditelně vykreslil (byl doložen screenshotem).

Ověřené typy a rozhraní:

```objc
NTKFace *face = /* MYCustomFace, faceStyle 44 */;
NTKFaceView *view = [NTKFaceView newFaceViewForFace:face];
// výsledek: MYCustomFaceView a NTKDigitalTimeLabel jako timeView
```

Použité prvky privátních frameworků: `NanoTimeKit`, `ClockKitUI`, `NTKFaceViewController`, `NTKFaceInstanceDescriptor`, `NTKFacesBundleArrayGalleryCollection`.

### 4.2 Lokální `NTKFaceBundleLoader`

**PROKÁZÁNO:** `MYLocalFaceBundle.bundle` s `NSPrincipalClass=MYLocalFaceBundle` lze načíst pomocí:

```objc
NTKFaceBundleLoader *loader =
    [NTKFaceBundleLoader faceBundleLoaderWithDirectories:[NSSet setWithObject:directoryURL]];
NTKFaceBundle *bundle =
    [loader loadFaceBundleWithIdentifier:@"dev.develodom.WatchFaceLab.LocalFaceBundle"];
```

Kontroloval se nejen návratový objekt, ale i identita `NSBundle bundleForClass:`, `faceClass`, `faceViewClass`, default face a renderer. Log obsahoval `Local bundle PoC PASS`.

Původně se někde nesprávně pokoušelo volat instanční `-[MYLocalFaceBundle identifier]`; fungující implementace používá **class selector** `+[MYLocalFaceBundle identifier]` (např. `[bundle.class identifier]`). Chybný selector vedl k pádu a byl opraven.

### 4.3 Face identity, serializace a obnovení

**PROKÁZÁNO v lokálním procesu:** factory `bundledFaceWithIdentifier:forDevice:initCustomization:` vytvořila face se zachovanou třídou, stylem 44 a bundle identifikátorem. Následovalo:

1. `JSONObjectRepresentation` + ověření `NTKFaceBundleIdentifierKey`;
2. `NSJSONSerialization`;
3. `NTKFaceInstanceDescriptor initWithJSONRepresentation:resourceDirectory:`;
4. `NSKeyedArchiver` se `requiringSecureCoding:YES`;
5. `faceFromData:` a kontrola shody původního a obnoveného JSON;
6. opětovné vytvoření rendereru.

Byly získány logy typu `Local identity PoC PASS`. To potvrzuje životaschopnost face modelu, **ne systémovou perzistenci**.

### 4.4 Nativní galerie ve vlastním hostu

**PROKÁZÁNO:** `NTKFacesBundleArrayGalleryCollection` úspěšně zpracovala vlastní bundle, měla požadovanou jednu face a poskytla titul, popis, model a renderer.

Pozitivní logy:

```text
NATIVE_GALLERY ABI_V3 STARTED=1
NATIVE_GALLERY RESULT=1
Local bundle PoC PASS
```

Jeden předchozí crash vznikl voláním `MYStartNativeGalleryCollection(NSString *)` přes špatně deklarovaný function pointer `void (*)(void)`. Poučení: ověřovat C/ObjC ABI včetně argumentů, blocků a návratových typů.

### 4.5 Instance-only bridge `NTKFaceBundleManager`

**PROKÁZÁNO:** v klonu jsme přes `object_setClass()` upravili pouze jednu konkrétní instanci `NTKFaceBundleManager sharedManager`. Původní discovery i lookup pro ostatní bundles zůstaly forwardované.

Bridge zachycuje tyto dvě metody:

```objc
- (void)enumerateFaceBundlesOnDevice:(CLKDevice *)device
                    includingLegacy:(BOOL)legacy
                          withBlock:(void (^)(NTKFaceBundle *bundle))block;

- (NTKFaceBundle *)faceBundleForBundleIdentifier:(NSString *)identifier
                                        onDevice:(CLKDevice *)device
                                    forMigration:(BOOL)migration;
```

Zkontrolovaná type encodings:

```text
enumerateFaceBundlesOnDevice:includingLegacy:withBlock:
  v36@0:8@16B24@?28
faceBundleForBundleIdentifier:onDevice:forMigration:
  @36@0:8@16@24B32
```

V portu na arm64/watchOS 27 byly upraveny původní guardy pro architekturu, host bundle ID a očekávané UUID NanoTimeKitu. Identifikované watchOS 27 UUID: `FC474CFA-5407-3528-A346-6F6A6B424A35`. Původní zdrojový artefakt měl x86_64-only kontrolu a jiné UUID — pozor při zpětném kopírování.

**Zaznamenaný úspěšný běh (PID 95942, cca 16:15):**

```text
CLOCKFACE_LAB BOOTSTRAP LOADED pid=95942
CLOCKFACE_LAB OWNED_BRIDGE symbols start=1 check=1
ClockFace bridge preflight: managerClass=NTKFaceBundleManager methodsMatch=1
ClockFace bridge INSTALLED: one manager instance; original discovery forwarded
ClockFace bridge CHECK: matches=1 identifierLookupMatches=1 success=1
Owned discovery STARTED: baseline bundles=61
CLOCKFACE_LAB OWNED_BRIDGE INSTALLED=1
Owned discovery CONSUMPTION PASS: shared lookup -> native gallery -> identified custom model/renderer/timeView
CLOCKFACE_LAB OWNED_BRIDGE RESULT=1
```

Implementace má také `MYRemoveOwnedDiscoveryExperiment()` a kontroly obnovení původní třídy, enumerace a nepřítomnosti vlastního lookupu. Načtené ObjC images se samozřejmě neodnačtou; pro čistý opakovaný cyklus je vhodný restart klonu.

**Limit:** bridge je změna ve **vlastním procesu**. Originální `com.apple.clockface` díky tomu vlastní ciferník automaticky neobjeví.

## 5. Pokusy dostat kód do originálního `com.apple.clockface`

### 5.1 Přímé spuštění systémové aplikace

```bash
xcrun simctl launch "$SIM" com.apple.clockface
```

**SELHALO už bez injekce:** FrontBoard/`IOSSHLMainWorkspace` vrátil `Unknown error launching ClockFace`. To dokazuje, že přímý `simctl launch` v tomto prostředí není normální cesta spuštění. **Nelze z toho vyvozovat**, že odmítá samotný `DYLD_INSERT_LIBRARIES`.

### 5.2 LLDB attach a informace o procesu

```bash
xcrun lldb -p <clockface-pid>
```

**SELHALO:** `Not allowed to attach to process`. `launchctl procinfo` také narazil na přístupovou chybu (`0x5`). Proces je spravovaný systémovou simulační infrastrukturou. Bez dalšího oprávnění nelze na attach postavit spolehlivou metodu.

### 5.3 Prostředí/signatury

Originální ClockFace měl původní podpis bez ad-hoc flagu (`flags=0x0`) a prázdná vypsaná entitlements `<dict/>`; klon byl podepsaný ad-hoc (`flags=0x2`). Slepé přidávání entitlements by nebylo podložené a nebylo použito jako řešení.

### 5.4 `launchctl debug` na konkrétní UIKitApplication job

Minimalistická knihovna `ClockFaceInjectionProbe.dylib` měla constructor, který pouze loguje:

```objc
__attribute__((constructor)) static void ClockFaceInjectionProbe(void) {
    NSLog(@"CLOCKFACE_ORIGINAL_INJECTION LOADED pid=%d bundle=%@",
          getpid(), [NSBundle mainBundle].bundleIdentifier);
}
```

Příklad původního běhu injekčního skriptu:

```text
PID:   97008
Job:   UIKitApplication:com.apple.clockface[2ab1][rb-legacy]
Target: system/UIKitApplication:com.apple.clockface[2ab1][rb-legacy]
Service configured for next launch.
Could not kickstart service "UIKitApplication:com.apple.clockface[2ab1][rb-legacy]":
  102: Operation not supported on socket
```

**PROKÁZÁNO:** `launchctl debug system/<dynamický label> --environment DYLD_INSERT_LIBRARIES=...` konfiguraci přijal. **NEPROKÁZÁNO:** že ji systémový proces skutečně dostal nebo že ji dyld respektoval.

`launchctl kickstart -kp` není pro tuto instanci podporovaný. Tím jsme nedokázali vyvolat nový start stejného labelu.

### 5.5 `simctl terminate` a automatické obnovení

```bash
xcrun simctl terminate "$SIM" com.apple.clockface
```

**PROKÁZÁNO:** Carousel okamžitě znovu spouští ClockFace s jiným PID i tokenem jobu:

```text
BEFORE: 97404  UIKitApplication:com.apple.clockface[c91d][rb-legacy]
AFTER:  97639  UIKitApplication:com.apple.clockface[e2f8][rb-legacy]
```

Proto je one-shot `launchctl debug` navázaný na konkrétní label **nevhodný pro běžné restarty**, pokud nedokážeme zajistit spuštění stejné instance.

Kontrola `log show` našla pouze záznamy konfigurace:

```text
launchctl debug system/UIKitApplication:com.apple.clockface[b557][rb-legacy] --environment DYLD_INSERT_LIBRARIES=...
launchctl debug system/UIKitApplication:com.apple.clockface[2ab1][rb-legacy] --environment DYLD_INSERT_LIBRARIES=...
```

Log **neobsahoval** `CLOCKFACE_ORIGINAL_INJECTION LOADED`. Korektní závěr: **načtení knihovny do originálního procesu nebylo potvrzeno**, nikoliv že watchOS univerzálně blokuje všechny formy injekce.

## 6. FaceSupportServer / Argon: cesta přes daemon místo injekce

### 6.1 XPC endpoint a read-only experiment

Identifikován endpoint:

```text
com.apple.nanotimekit.facesupportserver
```

V `launchctl print system` se objevil jako endpoint, ale dotaz `launchctl print system/com.apple.nanotimekit.facesupportserver` hlásil `service not found`: **endpoint není totéž co samostatný launchd job se stejným labelem**.

Zkoušeli jsme čtecí XPC `knownKeyDescriptors:`. Zpráva mohla být odeslaná, avšak bez doložené odpovědi. Pro registraci ciferníku to samo nestačí.

### 6.2 Nalezené Argon logy a třídy

Statická analýza `NanoTimeKit` našla řetězce:

```text
Asking to add key descriptor: %@
Adding key descriptor: %@ via daemon
Adding key descriptor: %@ via XPC
Couldn't add key descriptor: %@
Argon ingested key descriptor in message named %@.
Argon extracted descriptor %@ to path %@
Argon verification failed
```

Dále:

```text
/Library/NanoTimeKit/FaceSupport/ExtractedBundles/
/AppleInternal/Library/NanoTimeKit/FaceSupport/UnencryptedBundles/
load_unencrypted_argon_bundles
```

Nejde o důkaz dostupnosti instalace pro třetí strany. Jsou to **implementační stopy**.

### 6.3 Proč `strings` a `llvm-objdump --objc-meta-data` nestačily

Hledání přes `strings -a | grep` našlo pouze dva relevantní záznamy pro nešifrované bundles. `llvm-objdump --macho --objc-meta-data` uměl zobrazit třídy, ale u relative method listů vracel:

```text
entsize 15 (relative, invalid)
```

Metody nešlo přímo vypsat z tohoto statického výpisu. Proto jsme do již fungujícího klonu přidali introspekci přes `objc_lookUpClass`, `class_copyMethodList`, `method_getTypeEncoding` a metaclass pro class metody. To fungovalo.

### 6.4 Skutečné runtime selectory a ABI

**Ověřeno za běhu (PID 99365, 16:31:19):**

| Třída / selector | Type encoding | Poznámka |
|---|---|---|
| `-[NTKDArgonServiceXPCWrapper ingestKeyDescriptor:withMethod:completion:]` | `v40@0:8@16Q24@?32` | Asynchronní XPC ingestion |
| `-[NTKDArgonService ingestKeyDescriptor:withMethod:completion:]` | `v40@0:8@16Q24@?32` | Serverová/servisní vrstva |
| `-[NTKDArgonServiceXPCWrapper knownKeyDescriptors:]` | `v24@0:8@?16` | Čtení descriptorů |
| `-[NTKDArgonService knownKeyDescriptors:]` | `v24@0:8@?16` | Čtení descriptorů |
| `-[NTKDArgonService displayUserNotificationForKeyDescriptor:completion:]` | `v32@0:8@16@?24` | Notifikace |
| `+[NTKDArgonService sharedService]` | `@16@0:8` | Singleton služby |
| `-[NTKArgonLocalKeyDatabase addKeyDescriptor:error:]` | `B32@0:8@16^@24` | Lokální databázový zápis, nikoli plná instalace |
| `-[NTKArgonLocalKeyDatabase initWithKeyStoragePath:]` | `@24@0:8@16` | Inicializace lokální DB |
| `-[NTKArgonManager extractKnownKeyDescriptorsIfNeededWithCompletion:]` | `v24@0:8@?16` | Extrakce známých descriptorů |
| `-[NTKArgonManager initWithKeyDatabase:fetchers:extractor:]` | `@40@0:8@16@24@32` | Složení manageru |
| `-[NTKArgonKeyDescriptor initWithKey:fileName:]` | `@32@0:8@16@24` | Konstruktor descriptoru |
| `+[NTKArgonKeyDescriptor keyDescriptorFromBundle:]` | `@24@0:8@16` | Parsování z bundlu |
| `+[NTKArgonKeyDescriptor unfilteredKeyDescriptorFromBundle:]` | `@24@0:8@16` | Variantní parsování |

**Přesné zatím neznámé věci:** povolené hodnoty `withMethod:`, skutečná signatura completion blocku, autorizace serveru, požadovaný archiv a ověřování podpisu. Proto jsme **nespustili zápis** přes `ingestKeyDescriptor:` ani nezasahovali do lokální DB.

### 6.5 Falešná Argon metadata nejsou instalační payload

Testovací metadata používala:

```text
FileName = WatchFaceLab-Test.aea
Key      = WatchFaceLab-Test-NotARealKey
```

Reálný `.aea` soubor se v experimentu nenacházel. Tedy i kdyby volání ingestion přijalo descriptor, **není doložený žádný platný archiv pro stažení/extrakci/ověření**.

## 7. Nejzásadnější zjištění: nešifrovaný Argon loader je gated

### 7.1 Vlastní ARM64 XREF skript

Pro absenci Hopperu a Ghidry vznikl `Experiments/ntk_argon_xrefs.py`. Z Mach-O odvodil virtuální adresy a dekódoval vybrané ARM64 reference (`ADR`, `ADRP+ADD`, `ADRP+LDR`).

Výsledky:

```text
STRING  0x1b48e87ca file+0x3f07ca load_unencrypted_argon_bundles
STRING  0x1b48e7575 file+0x3ef575 /AppleInternal/Library/NanoTimeKit/FaceSupport/UnencryptedBundles/
POINTER 0x1e9ad90f0 -> 0x1b48e7575
Summary: 2 strings; 1 direct pointers; 1 potential code references
XREF    0x1b4602e2c -> 0x1b48e87ca [ADRP+ADD from 0x1b4602e28]
```

První skript havaroval na `UnicodeDecodeError: invalid start byte 0xa0` při převodu `llvm-objdump` výstupu do UTF-8. Oprava: `subprocess.run(..., encoding="utf-8", errors="replace", ...)`.

Následující disassembly výpis v původním skriptu vybíral chybnou oblast (`0x1b489d54c` místo `0x1b4602e2c`). Řešení: spustit `llvm-objdump` pro konkrétní adresní rozsah a ze souboru extrahovat okolí skutečného XREF. Jeden pokus s `--start-address`/`--stop-address` vedl k **velmi dlouhému souboru (~973 tisíc řádků)**; správný cílový blok ale v přiloženém disassembly byl dohledatelný.

### 7.2 Rozhodující disassembly

Relevantní úsek `NanoTimeKit`:

```asm
0x1b4602e18  bl   _NTKInternalBuild
0x1b4602e1c  cbz  w0, 0x1b4602ed8

0x1b4602e20  adrp x0, ...     ; "NanoTimeKitExtras"
0x1b4602e24  add  x0, ...
0x1b4602e28  adrp x1, ...
0x1b4602e2c  add  x1, ...     ; "load_unencrypted_argon_bundles"
0x1b4602e30  bl   __os_feature_enabled_impl
0x1b4602e34  cbz  w0, 0x1b4602ed8

0x1b4602e40  add  x2, ...     ; @"/AppleInternal/Library/NanoTimeKit/FaceSupport/UnencryptedBundles/"
0x1b4602e48  bl   _objc_msgSend$stringByAppendingPathComponent:
0x1b4602e5c  bl   _objc_msgSend$fileURLWithPath:
0x1b4602e74  bl   _objc_msgSend$addObject:

0x1b4602ed8  mov  w25, #0x0   ; větev přeskočení AppleInternal cesty
0x1b4602ee4  add  x2, ...     ; @"/System/Library/NanoTimeKit/FaceBundles/"
```

Jde o krátké vyhodnocení cesty pro přidání **AppleInternal unencrypted bundles**: do výsledného seznamu se přidá jen při současném splnění:

```c
NTKInternalBuild() &&
os_feature_enabled("NanoTimeKitExtras", "load_unencrypted_argon_bundles")
```

To neznamená, že **všechny** možnosti přidávání faces jsou vypnuté. Přesně to znamená, že **tato konkrétní AppleInternal cesta** je za tímto gate.

### 7.3 Runtime ověření gate

Do `MYInspectArgonDescriptorsV3()` byl přidán:

```objc
void *symbol = dlsym(RTLD_DEFAULT, "NTKInternalBuild");
if (!symbol) {
    NSLog(@"ARGON_GATE NTKInternalBuild symbol unavailable");
} else {
    BOOL (*internalBuild)(void) = (BOOL (*)(void))symbol;
    NSLog(@"ARGON_GATE NTKInternalBuild=%d", internalBuild());
}
```

Zpočátku samostatný časově úzký `log show --last 3m` nevypisoval žádné `ARGON_GATE`, což **nebyl důkaz návratu nula**. Kontrola zdrojáku a build artefaktu potvrdila, že řetězce v simulator frameworku existují. Další log dotaz s delším rozsahem výsledek definitivně objevil:

```text
2026-10-23 16:41:05.014 ClockFace[1828] (MYCustomFaceExperiment) ARGON_GATE NTKInternalBuild=0
2026-10-23 16:41:05.016 ClockFace[1828] (MYCustomFaceExperiment) ARGON_V3 BEGIN
```

**PROKÁZÁNO:** `NTKInternalBuild()` na daném watchOS 27 simulátoru vrací **0**. Větev pro `/AppleInternal/.../UnencryptedBundles/` proto nebyla přes tento standardní mechanismus dosažitelná bez ohledu na druhý feature flag.

Pokus `xcrun simctl get_app_container "$SIM" dev.develodom.ClockFaceLab app` skončil `NSPOSIXErrorDomain code=2`, a proto nebyly porovnány hashe skutečně instalovaného frameworku touto metodou. Neovlivňuje to přímý runtime log `ARGON_GATE=0`; konkrétní důvod neúspěšného `get_app_container` **nebyl zjištěn**.

## 8. Chyby, dead ends a poučení

| Pokus / problém | Co jsme zjistili | Co neopakovat bez nové hypotézy |
|---|---|---|
| „Vlastní watchOS aplikace jako ciferník“ | UI může fungovat, ale Crown vrací systémový ciferník | Nezaměňovat app UI za nativní face |
| Pouze lokální `NTKFaceBundleLoader` | Face bundle funguje ve vlastním procesu | Nevydávat za globální registraci |
| Gallery startup s nesprávným function pointerem | ABI mismatch způsoboval crash | Nevypouštět typované parametry (`NSString *`) |
| `-[MYLocalFaceBundle identifier]` | `identifier` je class metoda | Používat `[bundle.class identifier]` |
| Patch v generovaném `ClockFaceLabBootstrap.m` | Setup jej přepisuje | Patchovat setup template |
| `simctl launch com.apple.clockface` | FrontBoard chybuje i bez DYLD inject | Nepoužívat jako důkaz blokované injekce |
| Host LLDB attach | `Not allowed to attach to process` | Neplánovat bez podpory attach |
| `launchctl debug` + `kickstart` | Debug konfigurace přijata, `kickstart` error 102 | Nevyvozovat úspěšné načtení DLL/dylibu |
| `terminate` systémového ClockFace | Job ID se při restartu mění | Nečekat, že one-shot nastavení přežije nový job |
| `knownKeyDescriptors:` | Čtecí cesta bez doložené reply | Nevydávat za instalační operaci |
| Falešný `.aea` descriptor | Payload chybí | Nespouštět ingestion a nečekat extrakci |
| `strings` přes NanoTimeKit | Metadata jen indicie; nenašel odpovídající selectors | Použít runtime method introspection / XREF |
| `llvm-objdump --objc-meta-data` | `relative, invalid` method lists | Dekódovat runtime methods |
| Výpis disassembly bez úzkého filtrování | ~973k řádků, nesprávné počáteční místo | Extrahovat okolí konkrétního PC/XREF |
| `log show` a `tail` | Relevantní počáteční záznamy lze odříznout | Queryovat přesný marker a dost dlouhé okno |
| AppleInternal unencrypted Argon | `NTKInternalBuild() == 0` | Bez nové cesty k loaderu dále netestovat feature flag |

## 9. Přesná hranice dosaženého pokroku

```text
[PASS] Native face model + rendering in a ClockFace clone
[PASS] Local NTKFaceBundle subclass loaded via NTKFaceBundleLoader
[PASS] Identity / JSON / keyed archive round-trip
[PASS] NTKFacesBundleArrayGalleryCollection consumption
[PASS] NTKFaceBundleManager shared-instance discovery bridge in clone
[PASS] Original enumeration forwarded + custom identifier lookup
[PASS] Original ClockFace process can be terminated and auto-restarts
[PASS] launchctl debug accepts one-shot environment configuration
[PASS] Argon service/runtime ABI identified
[PASS] ARM64 XREF to unencrypted bundle feature flag identified
[PASS] NTKInternalBuild() == 0 verified on watchOS 27 Simulator

[NOT PROVEN] DYLD injection executed inside original com.apple.clockface
[NOT PROVEN] Original ClockFace discovers custom bundle
[NOT PROVEN] Original system gallery displays/selects custom face
[NOT PROVEN] Digital Crown returns to custom face
[NOT PROVEN] Persistent registration across system restarts
[NOT PROVEN] Argon accepts local custom bundle or valid custom .aea archive
```

## 10. Co doporučuji dělat dále (seřazeno podle informační hodnoty)

### Priorita A: zjistit přesnou hranici discovery v původním ClockFace bez dalšího chaosu

Staticky analyzovat `NTKFaceBundleManager` a `NTKFaceBundleLoader` — jejich výchozí adresáře, pořadí načítání, enumerátory a vstupní body z ClockFace. Zaměřit se zejména na to, zda původní aplikace používá **data-driven registraci ve sdíleném úložišti**, nebo pouze předem známé systémové bundle roots. Pokud žádná writable discovery cesta není, samotné kopírování vlastního `.bundle` do app containeru nemůže stačit.

**Prokazatelný výsledek příští fáze:** identifikované funkce + volané adresáře + konkrétní podmínka, která odlišuje systémový `NTKFaceBundleManager` od klonu. Bez náhodného zkoušení XPC API.

### Priorita B: pokud discovery nemá vhodnou externí cestu, explicitně řešit execution v originálním procesu

Zvážit test na **samostatně klonovaném simulátoru** a otestovat specificky procesový start mechanismem, který nevyžaduje `launchctl kickstart` na dynamickém UIKitApplication labelu. Potvrzovat injekci pouze konstruktorovým logem `bundle=com.apple.clockface` a současnou kontrolou PID, nikoli jen hláškou `Service configured for next launch`.

Jakmile by se ověřilo vykonávání uvnitř originálního procesu, portovaný manager bridge potřebuje dostupný lokální bundle a framework path. Cesty relativní k `[NSBundle mainBundle]` v klonu **neplatí pro originální ClockFace**. Muselo by se zvlášť vyřešit, odkud originální proces bezpečně načte `MYLocalFaceBundle.bundle` a `MYCustomFaceExperiment.framework`, a zda je dovolí sandbox/signature policy.

### Priorita C: Argon ponechat jako větev pouze s novým důkazem

`ingestKeyDescriptor:withMethod:completion:` existuje, ale nejsou známy metodové enum hodnoty, completion ABI, požadavky na autorizaci ani formát/signování `.aea`. Standardní cesta nešifrovaných AppleInternal bundles je na tomto simulátoru gated off. Nedoporučuje se zapisovat placeholder descriptor do systémové DB nebo zkoušet náhodné hodnoty `withMethod:`.

### Priorita D: finální funkční acceptance test

Po případné úspěšné registraci ověřit postupně: (1) discovery ze systémového host procesu; (2) viditelnost v původní galerii; (3) výběr ciferníku; (4) Digital Crown -> vlastní ciferník; (5) přechody do aplikací, sleep/wake, restart a zachování identity/renderingu.

## 11. Reprodukční příkazy

### Build a start lokálního klonu

```bash
bash Experiments/build-watchos27-simulator.sh
CLOCKFACE_LAB_FORCE_REMOTE_MANAGER=1 bash ~/Downloads/setup-clockface-lab-v2.sh
```

### Identifikace originálního procesu

```bash
SIM="4E768962-9FDF-4EBD-BE25-2A2A9E257143"
xcrun simctl spawn "$SIM" launchctl list | grep 'UIKitApplication:com.apple.clockface\['
```

### Důležité ověřovací logy

```bash
xcrun simctl spawn "$SIM" log show \
  --last 20m --info --debug --style compact \
  --predicate 'eventMessage CONTAINS "Owned discovery" OR eventMessage CONTAINS "OWNED_BRIDGE" OR eventMessage CONTAINS "ARGON_GATE" OR eventMessage CONTAINS "ARGON_V3 BEGIN"' \
  | tail -70
```

### Vlastní Mach-O XREF analyzátor

```bash
python3 Experiments/ntk_argon_xrefs.py \
  Experiments/ClockFaceLab/Analysis/Extracted/System/Library/PrivateFrameworks/NanoTimeKit.framework/NanoTimeKit \
  | tee Experiments/argon-xrefs.txt
```

### Cílené hledání známé instrukční reference ve velkém disassembly souboru

```bash
grep -n -B 30 -A 85 '^1b4602e2c:' /path/to/disassembly.txt
```

*Pozor:* terminálové příkazy uvádějí příklady pro konkrétní checkout. Dynamické job tokeny `[2ab1]`, `[c91d]`, `[e2f8]` nejsou stabilní identifikátory.

## 12. Poznámky k integritě zdrojů

- Starší přiložené soubory (`MYClockFaceBridge.m`, `NTKPrivateInterfaces.h`, některé setup skripty) pocházejí i ze starší x86_64/26.5 fáze. **Aktuální zdrojový strom na Macu má přednost** před historickou kopií.
- Runtime výstupy `OWNED_BRIDGE PASS`, `ARGON_METHODS` a `ARGON_GATE NTKInternalBuild=0` jsou přímo doložené logy v konverzaci.
- Disassembly pro unencrypted feature gate byl doložený v přiloženém velkém výpisu a přesnými adresami v kódu.
- Není doložený finální originální systémový watch face, žádný dokončený Argon import ani platný `.aea` payload.
- V případě nové fáze uchovávat build UUID, výstupy `method_getTypeEncoding`, architekturu, PID a host bundle ID při každém PASS; samotné `ClockFace[PID]` není dostatečné, protože klon používá stejný executable name.

---

## 13. Krátké předání pro další chat / inženýra

> Reverse-engineerujeme **nativní watchOS 27 ARM64 Simulator watch face**, ne obyčejnou appku. Face `MYCustomFace` + renderer `MYCustomFaceView` funguje, custom `MYLocalFaceBundle.bundle` funguje s `NTKFaceBundleLoader`, model/JSON/NSKeyedArchiver round-trip a `NTKFacesBundleArrayGalleryCollection` dávají PASS. Ve vlastním `dev.develodom.ClockFaceLab` funguje instance-only bridge `NTKFaceBundleManager sharedManager` s forwardováním původní discovery a lookupu; log `Owned discovery CONSUMPTION PASS`, baseline 61 bundles. **Originální `com.apple.clockface` vlastní face zatím nevidí.** `simctl launch` originálu zamítnut FrontBoard, LLDB attach denied; `launchctl debug` přijme `DYLD_INSERT_LIBRARIES`, ale `kickstart` vrací 102 a při `simctl terminate` se systémový ClockFace obnoví s jiným UIKitApplication job tokenem. Pro původní proces neexistuje potvrzený injection constructor log. Argon XPC API `ingestKeyDescriptor:withMethod:completion:` zjištěno (`v40@0:8@16Q24@?32`), ale payload `WatchFaceLab-Test.aea` je fake a neexistuje. V NanoTimeKit disassembly na `0x1b4602e18..0x1b4602e74` je AppleInternal unencrypted path pod `NTKInternalBuild() && os_feature_enabled("NanoTimeKitExtras","load_unencrypted_argon_bundles")`. Runtime ověřeno `ARGON_GATE NTKInternalBuild=0` (16:41:05) — tuto cestu opustit. Další smysluplný krok: **statická analýza systémového discovery rootu / loader call chainu**, případně izolovaný a jednoznačně ověřitelný experiment s execution v původním host procesu. Nezaměňovat úspěch v klonu s integrací do systému. Setup `~/Downloads/setup-clockface-lab-v2.sh` regeneruje bootstrap `.m`. Používat `grep`, ne `rg`, žádné `cd`.

*Dokument reflektuje stav k 23. 10. 2026. Neobsahuje spekulativní tvrzení o tom, že jde obejít běžné instalační bezpečnostní brány watchOS.*
