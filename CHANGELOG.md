# CHANGELOG

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Complete Lua port of vim-projectionist functionality
- Native Neovim 0.11+ support with modern Lua APIs
- Comprehensive project type detection (Python, Go, Rust, Deno, Make, Zsh, Lua)
- Support for `.projections.json` and `heuristic.json` configuration files
- Full test suite with 12/12 test coverage
- All original vim-projectionist commands and functions:
  - `:A`, `:AS`, `:AV`, `:AT` - Alternate file navigation
  - `:E*`, `:S*`, `:V*`, `:T*` - Project file navigation
  - `:Eproject`, `:Sproject`, `:Vproject`, `:Tproject` - Root navigation
- API functions for plugin integration:
  - `query_file()` - File relationship queries
  - `expand()` - Template expansion
  - `path()` - Alternate path resolution

### Changed
- Migrated from VimScript to modern Lua implementation
- Improved performance with native Neovim APIs
- Enhanced error handling and debugging support
- Modular architecture for better maintainability

### Fixed
- Critical bug in `query_file()` API parameter signature
- Template expansion issues with `{dirname}` placeholder
- Path resolution edge cases for nested project structures

## [0.1.0] - Initial Release

### Added
- Basic setup function for Neovim configuration
- Foundation for vim-projectionist compatibility
