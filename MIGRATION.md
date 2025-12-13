# Migration Guide

## v1.1.0 - Environment Parameter

### Breaking Change

The `environment` parameter has been moved from `Options` to `configure()` method.

### Before (v1.0.x)

```swift
// Old API - NO LONGER WORKS
AppVitalityKit.shared.configure(
    apiKey: "xxx",
    options: .init(environment: .staging)  // ❌ environment was in Options
)
```

### After (v1.1.0+)

```swift
// New API
AppVitalityKit.shared.configure(
    apiKey: "xxx",
    environment: .staging  // ✅ environment is now a separate parameter
)

// With custom options
AppVitalityKit.shared.configure(
    apiKey: "xxx",
    environment: .staging,
    options: .init(enableDebugLogging: true)
)

// Production (default) - no change needed
AppVitalityKit.shared.configure(apiKey: "xxx")
```

### Migration Steps

1. If you were using `options: .init(environment: .staging)`, change to `environment: .staging`
2. If you were using production (default), no changes needed

