# Deprecated Code & Dependencies

## Phoenix Framework Analysis

### LiveView Version Compatibility
- **Current**: `{:phoenix_live_view, "~> 1.1.0"}`
- **Issue**: Phoenix LiveView 1.1.0 was a development version. Current stable is 0.20.x or 1.0.x depending on Phoenix version
- **Recommendation**: Update to stable `{:phoenix_live_view, "~> 0.20.0"}` for Phoenix 1.8.x compatibility

### Phoenix Version
- **Current**: `{:phoenix, "~> 1.8.1"}`
- **Status**: Current stable version - no issues

### Deprecated Patterns Check
- **✅ No deprecated `live_redirect` or `live_patch` found**
- **✅ No deprecated `Phoenix.View` usage**
- **✅ Proper use of `push_navigate` and `push_patch` (not found in codebase but templates use `<.link>` correctly)**

## Elixir Dependencies

### Core Dependencies Status
```
{:phoenix_ecto, "~> 4.5"} - Current
{:ecto_sql, "~> 3.13"} - Current
{:postgrex, ">= 0.0.0"} - Too loose, should pin to "~> 0.19"
{:phoenix_html, "~> 4.1"} - Current
{:req, "~> 0.5"} - Current
{:jason, "~> 1.2"} - Current
{:bandit, "~> 1.5"} - Current
```

### Development Dependencies
```
{:phoenix_live_reload, "~> 1.2"} - Current
{:esbuild, "~> 0.10"} - Slightly outdated, current is ~> 0.8 (wait, 0.10 is newer)
{:tailwind, "~> 0.3"} - Outdated, current is ~> 0.2
```

### Heroicons Usage
- **Current**: GitHub dependency `{:heroicons, github: "tailwindlabs/heroicons", tag: "v2.2.0"}`
- **Issue**: Using GitHub dependency instead of Hex package
- **Recommendation**: Switch to `{:heroicons, "~> 0.5"}` from Hex

## JavaScript Dependencies

### Package.json Analysis
```json
{
  "dependencies": {
    "echarts": "^6.0.0"
  }
}
```
- **ECharts**: Current version - no issues

### Vendor Dependencies
- **daisyUI**: Custom vendor files present but minimal usage
- **Heroicons**: Custom vendor files present and properly integrated

## DaisyUI Usage Assessment

### Current Usage
- **Files**: `daisyui.js` and `daisyui-theme.js` in vendor directory
- **Actual Usage**: Minimal - only referenced in `core_components.ex` docstring
- **Bundle Impact**: ~300KB of unused CSS/JS (daisyui.js is 251KB)
- **Recommendation**: **Remove daisyUI** - it's not being used and adds significant bundle size

### Tailwind Integration
- **CSS Import**: Uses new Tailwind v4 syntax `@import "tailwindcss" source(none);`
- **Status**: Modern and correct

## Security Vulnerabilities

### Dependency Vulnerabilities
- **Postgrex**: Version constraint `">= 0.0.0"` is too permissive
- **Potential Issue**: Could install very old versions with known vulnerabilities
- **Recommendation**: Pin to `"~> 0.19"`

### NPM Dependencies
- **ECharts**: Version `^6.0.0` - check for known vulnerabilities
- **Recommendation**: Regularly audit with `npm audit`

## Migration Recommendations

### High Priority
1. **Update Phoenix LiveView version** to stable release
2. **Remove DaisyUI** to reduce bundle size
3. **Pin Postgrex version** for security

### Medium Priority
1. **Switch Heroicons to Hex package**
2. **Update Tailwind dependency**
3. **Audit npm dependencies regularly**

### Low Priority
1. **Review and update development dependencies**

## Code Examples

### Current Issue (mix.exs)
```elixir
{:phoenix_live_view, "~> 1.1.0"},  # Development version
{:postgrex, ">= 0.0.0"},           # Too permissive
{:heroicons, github: "tailwindlabs/heroicons", ...}  # GitHub dep
```

### Recommended (mix.exs)
```elixir
{:phoenix_live_view, "~> 0.20.0"},  # Stable version
{:postgrex, "~> 0.19"},             # Pinned version
{:heroicons, "~> 0.5"},             # Hex package
```

### Remove DaisyUI
```bash
# Remove vendor files
rm assets/vendor/daisyui.js
rm assets/vendor/daisyui-theme.js

# Remove from core_components.ex docstring references
```

## Impact Assessment

- **Bundle Size**: Removing DaisyUI saves ~300KB
- **Security**: Pinned Postgrex prevents vulnerable versions
- **Maintenance**: Hex dependencies are more reliable than GitHub deps
- **Compatibility**: Stable LiveView version ensures long-term support
