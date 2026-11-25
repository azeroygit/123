# Configuration Guide

All settings are managed by `src/Core/ConfigManager.luau` and persisted to `KiriaAutoTrader/config.json` when file I/O is available.

## `AMVGG`
| Key | Default | Description |
| --- | --- | --- |
| `EndpointUrl` | `"https://amvgg.com/values/pets"` | Exclusive AMVGG pets endpoint (non-AMVGG URLs are blocked). |
| `HubUrl` | `"https://amvgg.com/values"` | AMVGG hub reference URL. |
| `RefreshIntervalSeconds` | `1800` | Background refresh interval in seconds. |
| `RequestTimeoutSeconds` | `15` | HTTP request timeout. |
| `MaxRetries` | `3` | Exponential backoff retry attempts. |
| `CacheFile` | `"KiriaAutoTrader/amvgg_cache.json"` | Local cache file path. |
| `AllowStaleCacheFallback` | `true` | Preserve last valid AMVGG dataset if refresh fails. |

## `Trading`
| Key | Default | Description |
| --- | --- | --- |
| `Mode` | `"manual_confirm"` | `"manual_confirm"` or `"practice"`. |
| `MaxItemsPerOffer` | `4` | Max pets combined in generated offers (1–9). |
| `MinProfitValue` | `1.0` | Minimum AMVGG profit required for offer candidates. |
| `MinProfitPercent` | `5.0` | Minimum percentage gain required for offer candidates. |
| `MaxOverpayPercent` | `0.0` | Maximum allowed overpay %. |
| `RequireExplicitConfirmation` | `true` | Locked to `true`; trades never auto-finalize. |
| `AutoCancelStaleListings` | `false` | Disabled by default; requires explicit confirmation. |
| `ListingExpirationSeconds` | `60` | Stale listing timer (`30`, `45`, `60`, `90`, `120`). |
| `OfferResponseIntervalSeconds` | `45` | Pending offer response check interval (`30–60`s). |
| `OfferExpirationSeconds` | `180` | Pending offer expiration timeout. |
| `MaxPendingOffers` | `20` | Maximum concurrent pending offers. |
| `MaxActiveListings` | `5` | Maximum concurrent active listings. |

## `Thresholds`
| Key | Default | Rating |
| --- | --- | --- |
| `ExcellentDealMinPct` | `25.0` | `EXCELLENT_DEAL` |
| `GoodDealMinPct` | `8.0` | `GOOD_DEAL` |
| `FairTradeMinPct` | `-3.0` | `FAIR_TRADE` |
| `SmallLossMinPct` | `-12.0` | `SMALL_LOSS` (below is `BAD_TRADE`) |

## `UI` & `Data`
- `UI.Theme`: `"KiriaDark"`
- `UI.Keybind`: `"RightShift"`
- `UI.NotificationsEnabled`: `true`
- `UI.KiriaEnabled`: `true`
- `Data.LogLevel`: `"INFO"` (`DEBUG`, `INFO`, `SUCCESS`, `WARN`, `ERROR`, `OFF`)
