# Changelog

## v1.0.0 (2026-11-26)
- Initial from-scratch release of **KIRIA AUTOTRADER**.
- Implemented `Core/` infrastructure (`EventBus`, `StateManager`, `TaskScheduler`, `Logger`, `ErrorHandler`, `ConfigManager`).
- Implemented exclusive **AMVGG** (`https://amvgg.com/values/pets`) Next.js RSC + JSON parser, validator, local cache with failure preservation, rate-limited provider, and `ValueEngine`.
- Implemented `Inventory/` system with manual editor, JSON import/export, locked/favorite protection, and valuation sorting.
- Implemented `Trading/` engine: `ListingScanner`, `OfferAnalyzer`, `TradeEvaluator`, `ProfitCalculator`, `ListingManager` (configurable stale timers), `OfferQueue` & `OfferTimer`, and `TradeHistory` (Potential vs Pending vs Confirmed Profit).
- Implemented decoupled `Kiria/` companion (`Personality`, `Memory`, `Reactions`, `Companion`).
- Implemented Dark Trading Terminal `UI/` (`MainWindow`, `Dashboard`, `ListingsPage`, `OffersPage`, `InventoryPage`, `AnalyticsPage`, `SettingsPage`, `Notifications`, `Theme`, `Widgets`).
- Added unit and integration test suites (`ValueTests`, `TradingTests`, `TimerTests`, `IntegrationTests`, `TestRunner`).
