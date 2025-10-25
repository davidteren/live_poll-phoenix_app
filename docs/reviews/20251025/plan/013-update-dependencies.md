# Task: Update Dependencies to Latest Stable Versions

## Category
Maintenance, Security

## Priority
**MEDIUM** - Security and bug fixes in newer versions

## Description
Phoenix LiveView is outdated (1.1.0 vs 1.1.16 latest), and several dependencies are not pinned to specific versions. Dependencies must be updated to latest stable versions for security patches and bug fixes.

## Current State
```elixir
# mix.exs - Current versions
{:phoenix_live_view, "~> 1.1.0"},  # Outdated! Latest is 1.1.16
{:ecto, "~> 3.11"},  # Should pin to 3.13.3
{:heroicons, github: "tailwindlabs/heroicons"}  # Should use hex package
# Missing useful dependencies for production
```

## Proposed Solution

### Step 1: Update Core Dependencies
```elixir
# mix.exs
defmodule LivePoll.MixProject do
  use Mix.Project

  def project do
    [
      app: :live_poll,
      version: "0.2.0",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.html": :test,
        "coveralls.github": :test
      ]
    ]
  end

  defp deps do
    [
      # Core Phoenix
      {:phoenix, "~> 1.8.1"},
      {:phoenix_live_view, "~> 1.1.16"},  # UPDATED
      {:phoenix_ecto, "~> 4.6"},
      {:phoenix_html, "~> 4.2"},
      {:phoenix_live_reload, "~> 1.5", only: :dev},
      {:phoenix_live_dashboard, "~> 0.8.5"},
      
      # Database
      {:ecto, "~> 3.13.3"},  # PINNED
      {:ecto_sql, "~> 3.13.2"},  # PINNED
      {:postgrex, "~> 0.19.3"},
      
      # Telemetry & Monitoring
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.1"},
      
      # JSON
      {:jason, "~> 1.4"},
      
      # Server
      {:bandit, "~> 1.6"},
      {:dns_cluster, "~> 0.1.3"},
      
      # UI Components
      {:heroicons, "~> 0.5.6"},  # HEX PACKAGE instead of GitHub
      
      # Security (NEW)
      {:hammer, "~> 6.2"},  # Rate limiting
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},
      
      # Caching (NEW)
      {:cachex, "~> 3.6"},
      
      # Testing & Quality (NEW/UPDATED)
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:ex_machina, "~> 2.8", only: :test},
      {:floki, "~> 0.36", only: :test},
      {:stream_data, "~> 1.1", only: [:dev, :test]},
      
      # Development Tools
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["cmd --cd assets npm install"],
      "assets.build": ["esbuild default", "tailwind default"],
      "assets.deploy": [
        "esbuild default --minify",
        "tailwind default --minify",
        "phx.digest"
      ],
      # Quality checks
      quality: [
        "format --check-formatted",
        "credo --strict",
        "sobelow --config",
        "deps.audit",
        "dialyzer"
      ],
      # Precommit checks (as per AGENTS.md)
      precommit: [
        "format",
        "credo --strict",
        "sobelow --config",
        "test --cover --warnings-as-errors"
      ]
    ]
  end
end
```

### Step 2: Update JavaScript Dependencies
```json
// assets/package.json
{
  "name": "live_poll_assets",
  "version": "0.2.0",
  "private": true,
  "scripts": {
    "build": "webpack --mode production",
    "dev": "webpack --mode development --watch",
    "test": "jest",
    "analyze": "webpack-bundle-analyzer dist/stats.json"
  },
  "dependencies": {
    "phoenix": "file:../deps/phoenix",
    "phoenix_html": "file:../deps/phoenix_html",
    "phoenix_live_view": "file:../deps/phoenix_live_view",
    "echarts": "^5.5.1",
    "topbar": "^3.0.0"
  },
  "devDependencies": {
    "@babel/core": "^7.25.0",
    "@babel/preset-env": "^7.25.0",
    "babel-loader": "^9.2.0",
    "copy-webpack-plugin": "^12.0.0",
    "css-loader": "^7.1.0",
    "css-minimizer-webpack-plugin": "^7.0.0",
    "mini-css-extract-plugin": "^2.9.0",
    "postcss": "^8.4.47",
    "postcss-loader": "^8.1.0",
    "postcss-import": "^16.1.0",
    "tailwindcss": "^3.4.0",
    "terser-webpack-plugin": "^5.3.0",
    "webpack": "^5.95.0",
    "webpack-bundle-analyzer": "^4.10.0",
    "webpack-cli": "^5.1.0",
    "webpack-dev-server": "^5.1.0"
  }
}
```

### Step 3: Add Security Dependency Configuration
```elixir
# .sobelow-conf
[
  verbose: false,
  private: false,
  skip: false,
  router: "lib/live_poll_web/router.ex",
  exit: "low",
  format: "txt",
  out: "",
  threshold: "low",
  ignore: ["Config.HTTPS"],
  ignore_files: []
]
```

### Step 4: Add Credo Configuration
```elixir
# .credo.exs
%{
  configs: [
    %{
      name: "default",
      files: %{
        included: [
          "lib/",
          "src/",
          "test/",
          "web/",
          "apps/*/lib/",
          "apps/*/src/",
          "apps/*/test/",
          "apps/*/web/"
        ],
        excluded: [~r"/_build/", ~r"/deps/", ~r"/node_modules/"]
      },
      plugins: [],
      requires: [],
      strict: true,
      parse_timeout: 5000,
      color: true,
      checks: %{
        enabled: [
          {Credo.Check.Consistency.ExceptionNames, []},
          {Credo.Check.Consistency.LineEndings, []},
          {Credo.Check.Consistency.ParameterPatternMatching, []},
          {Credo.Check.Consistency.SpaceAroundOperators, []},
          {Credo.Check.Consistency.SpaceInParentheses, []},
          {Credo.Check.Consistency.TabsOrSpaces, []},
          {Credo.Check.Design.AliasUsage, [priority: :low, if_nested_deeper_than: 2, if_called_more_often_than: 0]},
          {Credo.Check.Design.TagFIXME, []},
          {Credo.Check.Design.TagTODO, [exit_status: 2]},
          {Credo.Check.Readability.AliasOrder, []},
          {Credo.Check.Readability.FunctionNames, []},
          {Credo.Check.Readability.LargeNumbers, []},
          {Credo.Check.Readability.MaxLineLength, [priority: :low, max_length: 120]},
          {Credo.Check.Readability.ModuleAttributeNames, []},
          {Credo.Check.Readability.ModuleDoc, []},
          {Credo.Check.Readability.ModuleNames, []},
          {Credo.Check.Readability.ParenthesesInCondition, []},
          {Credo.Check.Readability.ParenthesesOnZeroArityDefs, []},
          {Credo.Check.Readability.PipeIntoAnonymousFunctions, []},
          {Credo.Check.Readability.PredicateFunctionNames, []},
          {Credo.Check.Readability.PreferImplicitTry, []},
          {Credo.Check.Readability.RedundantBlankLines, []},
          {Credo.Check.Readability.Semicolons, []},
          {Credo.Check.Readability.SpaceAfterCommas, []},
          {Credo.Check.Readability.StringSigils, []},
          {Credo.Check.Readability.TrailingBlankLine, []},
          {Credo.Check.Readability.TrailingWhiteSpace, []},
          {Credo.Check.Readability.UnnecessaryAliasExpansion, []},
          {Credo.Check.Readability.VariableNames, []},
          {Credo.Check.Readability.WithCustomTaggedTuple, []},
          {Credo.Check.Refactor.Apply, []},
          {Credo.Check.Refactor.CondStatements, []},
          {Credo.Check.Refactor.CyclomaticComplexity, []},
          {Credo.Check.Refactor.FunctionArity, []},
          {Credo.Check.Refactor.LongQuoteBlocks, []},
          {Credo.Check.Refactor.MatchInCondition, []},
          {Credo.Check.Refactor.MapJoin, []},
          {Credo.Check.Refactor.NegatedConditionsInUnless, []},
          {Credo.Check.Refactor.NegatedConditionsWithElse, []},
          {Credo.Check.Refactor.Nesting, []},
          {Credo.Check.Refactor.UnlessWithElse, []},
          {Credo.Check.Refactor.WithClauses, []},
          {Credo.Check.Refactor.FilterFilter, []},
          {Credo.Check.Refactor.RejectReject, []},
          {Credo.Check.Refactor.RedundantWithClauseResult, []},
          {Credo.Check.Warning.ApplicationConfigInModuleAttribute, []},
          {Credo.Check.Warning.BoolOperationOnSameValues, []},
          {Credo.Check.Warning.ExpensiveEmptyEnumCheck, []},
          {Credo.Check.Warning.IExPry, []},
          {Credo.Check.Warning.IoInspect, []},
          {Credo.Check.Warning.MixEnv, []},
          {Credo.Check.Warning.OperationOnSameValues, []},
          {Credo.Check.Warning.OperationWithConstantResult, []},
          {Credo.Check.Warning.RaiseInsideRescue, []},
          {Credo.Check.Warning.SpecWithStruct, []},
          {Credo.Check.Warning.WrongTestFileExtension, []},
          {Credo.Check.Warning.UnusedEnumOperation, []},
          {Credo.Check.Warning.UnusedFileOperation, []},
          {Credo.Check.Warning.UnusedKeywordOperation, []},
          {Credo.Check.Warning.UnusedListOperation, []},
          {Credo.Check.Warning.UnusedPathOperation, []},
          {Credo.Check.Warning.UnusedRegexOperation, []},
          {Credo.Check.Warning.UnusedStringOperation, []},
          {Credo.Check.Warning.UnusedTupleOperation, []},
          {Credo.Check.Warning.UnsafeExec, []}
        ],
        disabled: [
          {Credo.Check.Refactor.ModuleDependencies, []},
          {Credo.Check.Refactor.VariableRebinding, []},
          {Credo.Check.Warning.LazyLogging, []},
          {Credo.Check.Warning.LeakyEnvironment, []},
          {Credo.Check.Warning.MapGetUnsafePass, []},
          {Credo.Check.Warning.UnsafeToAtom, []}
        ]
      }
    }
  ]
}
```

### Step 5: Create Dependency Update Script
```bash
#!/bin/bash
# scripts/update_deps.sh

echo "Updating Elixir dependencies..."
mix deps.update --all

echo "Checking for outdated dependencies..."
mix hex.outdated

echo "Updating JavaScript dependencies..."
cd assets
npm update
npm audit fix

echo "Running security audit..."
cd ..
mix deps.audit
mix sobelow --config

echo "Running quality checks..."
mix format
mix credo --strict

echo "Dependencies updated! Please review changes and run tests."
```

## Requirements
1. ✅ Update Phoenix LiveView to 1.1.16
2. ✅ Pin Ecto to 3.13.3
3. ✅ Use Heroicons from Hex instead of GitHub
4. ✅ Add security dependencies (Hammer, Sobelow)
5. ✅ Add quality tools (Credo, Dialyxir)
6. ✅ Add testing tools (ExCoveralls, ExMachina)
7. ✅ Configure dependency security auditing

## Definition of Done
1. **Dependencies Updated**
   - [ ] mix.exs updated with new versions
   - [ ] package.json updated
   - [ ] Dependencies compile without warnings
   - [ ] No security vulnerabilities

2. **Quality Tools**
   - [ ] Credo configured and passing
   - [ ] Sobelow configured and passing
   - [ ] Mix audit shows no issues
   - [ ] Dialyzer configured

3. **Tests**
   - [ ] All tests pass with new dependencies
   - [ ] No deprecation warnings
   - [ ] Coverage tools working

4. **Documentation**
   - [ ] README updated with new commands
   - [ ] Development setup documented
   - [ ] CI/CD configuration updated

## Branch Name
`chore/update-dependencies`

## Dependencies
None - Can be done independently

## Estimated Complexity
**S (Small)** - 1-2 hours

## Testing Instructions
1. Update mix.exs with new versions
2. Run `mix deps.get`
3. Run `mix deps.compile`
4. Check for warnings/errors
5. Run `mix test` to verify nothing broken
6. Run `mix quality` to check code quality
7. Run `mix deps.audit` for security
8. Update JavaScript dependencies
9. Run `npm audit` for JS security

## Security Improvements
- Latest LiveView has security patches
- Sobelow adds security scanning
- Mix audit checks for vulnerable dependencies
- Hammer provides rate limiting capabilities

## Notes
- Review CHANGELOG for breaking changes
- Update CI/CD to use new quality checks
- Consider automating dependency updates
- Pin major versions to avoid breaking changes
