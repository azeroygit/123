# KIRIA AUTOTRADER

A modular, safety-first Roblox Luau trading assistant and dark trading terminal for Adopt Me, powered **exclusively** by [AMVGG](https://amvgg.com/values/pets) pet valuations and guided by the **Kiria** companion system.

## Key Principles
- **AMVGG-Only Valuation**: Uses `https://amvgg.com/values/pets` (overview: `https://amvgg.com/values`) as the sole source of pet values. Never averages across providers or falls back to other valuation sites.
- **Explicit User Confirmation**: Never auto-accepts or auto-finalizes trades. Accepting offers and cancelling listings with pending offers require explicit user confirmation.
- **Legitimate Boundaries**: No anti-cheat bypasses, no unauthorized memory reading, no RemoteEvent exploitation, and no Cloudflare/auth bypassing. Provides manual editor and JSON import/export fallbacks when live game adapters are unavailable.
- **Modular & Leak-Free**: Relative module loading, zero global variables, zero circular dependencies, non-blocking async scheduling, and clean connection/thread teardown.

## Project Structure
- `src/Main.luau` — Main entry point
- `src/Bootstrap.luau` — Composition root & dependency wiring
- `src/Core/` — `EventBus`, `StateManager`, `TaskScheduler`, `Logger`, `ErrorHandler`, `ConfigManager`
- `src/Values/` — `AMVGGProvider`, `ValueParser`, `ValueCache`, `ValueValidator`, `ValueEngine`
- `src/Inventory/` — `InventoryReader`, `PetDatabase`, `InventoryValuator`
- `src/Trading/` — `ListingScanner`, `OfferAnalyzer`, `TradeEvaluator`, `ProfitCalculator`, `ListingManager`, `OfferQueue`, `OfferTimer`, `TradeHistory`
- `src/Kiria/` — `Companion`, `Personality`, `Memory`, `Reactions`
- `src/UI/` — `MainWindow`, `Dashboard`, `ListingsPage`, `OffersPage`, `InventoryPage`, `AnalyticsPage`, `SettingsPage`, `Notifications`, `Components/`
- `src/Tests/` — `ValueTests`, `TradingTests`, `TimerTests`, `IntegrationTests`, `TestRunner`

## Installation & Launch
1. Place the `KiriaAutoTrader/` folder into your Roblox Studio project (e.g. `ReplicatedStorage/KiriaAutoTrader` or `StarterPlayerScripts/KiriaAutoTrader`) or run tests locally with Lune.
2. Ensure the entry point `src/Main.luau` is executed as a `LocalScript` (or required by your client bootstrapper).
3. To run the automated test suite locally with Lune:
   ```powershell
   lune run src/Tests/TestRunner.luau
   ```

## Known Limitations
- **Live Game Adapter**: Reading live backpack pets or Trade Hub listings inside Roblox requires a permitted game UI/adapter; when unavailable, `InventoryReader` and `ListingScanner` provide full manual editing and JSON import/export fallbacks without fabricating data.
- **AMVGG Availability**: `https://amvgg.com/values/pets` serves Next.js RSC payloads behind Cloudflare (`__cf_bm`). If rate-limited or challenged, `AMVGGProvider` preserves the last valid local cache and reports `CACHED_FALLBACK` or `UNAVAILABLE`.
- **Liquidity**: Equal AMVGG value does not guarantee equal trade liquidity; `ProfitCalculator` surfaces demand/liquidity warnings alongside every evaluation.
