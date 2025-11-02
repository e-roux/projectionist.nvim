# projectionist.nvim

A modern Lua port of [vim-projectionist](https://github.com/tpope/vim-projectionist) for Neovim.

Projectionist provides granular project configuration using "projections" that enable seamless navigation between related files in your projects.

## Features

- **Full vim-projectionist compatibility**: All commands and functions work exactly as in the original
- **Modern Neovim integration**: Built with Lua for Neovim 0.11+
- **Extensive project type support**: Python, Go, Rust, Deno, Make, Zsh, Lua, and more
- **Flexible configuration**: Support for `.projections.json`, `heuristic.json`, and Lua setup
- **Comprehensive testing**: 12/12 test coverage ensuring reliability

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  'e-roux/projectionist.nvim',
  config = function()
    require('projectionist').setup()
  end,
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  'e-roux/projectionist.nvim',
  config = function()
    require('projectionist').setup()
  end,
}
```

### Using [vim-plug](https://github.com/junegunn/vim-plug)

```vim
Plug 'e-roux/projectionist.nvim'

lua << EOF
require('projectionist').setup()
EOF
```

## Quick Start

### Basic Example

Create a `.projections.json` file in your project root:

```json
{
  "app/*.py": {
    "type": "source",
    "alternate": "test/test_{}.py"
  },
  "test/test_*.py": {
    "type": "test",
    "alternate": "app/{}.py"
  }
}
```

Now you can:
- Use `:A` to jump between source and test files
- Use `:Etest` to navigate to test files
- Use `:Esource` to navigate to source files

## Commands

### Navigation Commands

| Command | Description |
|---------|-------------|
| `:A` | Open alternate file in current window |
| `:AS` | Open alternate file in horizontal split |
| `:AV` | Open alternate file in vertical split |
| `:AT` | Open alternate file in new tab |

### Project File Commands

| Command | Description |
|---------|-------------|
| `:E{type} [file]` | Edit file of specific type |
| `:S{type} [file]` | Edit file of specific type in split |
| `:V{type} [file]` | Edit file of specific type in vertical split |
| `:T{type} [file]` | Edit file of specific type in new tab |

### Root Navigation

| Command | Description |
|---------|-------------|
| `:Eproject [file]` | Edit file relative to project root |
| `:Sproject [file]` | Edit file relative to project root in split |
| `:Vproject [file]` | Edit file relative to project root in vertical split |
| `:Tproject [file]` | Edit file relative to project root in new tab |

## Configuration

### Setup Function

```lua
require('projectionist').setup({
  -- Custom heuristics (optional)
  heuristics = {
    ["src/*.rs"] = {
      type = "source",
      alternate = "tests/{}.rs"
    },
    ["tests/*.rs"] = {
      type = "test",
      alternate = "src/{}.rs"
    }
  },
  
  -- Enable commands (default: true)
  enable_commands = true,
  
  -- Enable debug logging (default: false)
  debug = false
})
```

### Configuration Files

#### `.projections.json` (Project-specific)

```json
{
  "lib/*.py": {
    "type": "source",
    "alternate": "test/test_{}.py",
    "template": [
      "def {}():",
      "    pass"
    ]
  },
  "test/test_*.py": {
    "type": "test",
    "alternate": "lib/{}.py",
    "template": [
      "import unittest",
      "from lib.{} import {}",
      "",
      "class Test{}(unittest.TestCase):",
      "    def test_{}(self):",
      "        pass"
    ]
  }
}
```

#### `heuristic.json` (Project-specific heuristics)

```json
{
  "go.mod": {
    "*.go": {
      "type": "source",
      "alternate": "{}_test.go"
    },
    "*_test.go": {
      "type": "test",
      "alternate": "{}.go"
    }
  }
}
```

## Projection Properties

### `alternate`
Defines the alternate file pattern:
```json
"app/*.py": {"alternate": "test/test_{}.py"}
```

### `type`
Defines the file type for navigation commands:
```json
"app/*.py": {"type": "source"}
```

### `template`
Defines file template for new files:
```json
"test/test_*.py": {
  "template": [
    "import unittest",
    "",
    "class Test{}(unittest.TestCase):",
    "    def test_{}(self):",
    "        pass"
  ]
}
```

## Template Variables

| Variable | Description |
|----------|-------------|
| `{}` or `{*}` | First placeholder match |
| `{1}`, `{2}`, ... | Numbered placeholder matches |
| `{basename}` | File basename without extension |
| `{dirname}` | Directory name of file |
| `{camelcase}` | Convert to CamelCase |
| `{underscore}` | Convert to snake_case |
| `{uppercase}` | Convert to UPPERCASE |
| `{lowercase}` | Convert to lowercase |

## API Functions

```lua
local projectionist = require('projectionist')

-- Query file for projection property
local alternate = projectionist.query_file('alternate', 'app/user.py')

-- Expand template with file placeholders
local expanded = projectionist.expand('test/test_{}.py', 'app/user.py')

-- Get alternate path for file
local alt_path = projectionist.path('app/user.py')
```

## Supported Project Types

Built-in support for:
- **Python** (`pyproject.toml`, `setup.py`)
- **Go** (`go.mod`)
- **Rust** (`Cargo.toml`)
- **Deno** (`deno.json`)
- **Make** (`Makefile`)
- **Zsh** (`.zshrc`, `.zprofile`)
- **Lua** (`.lua` files)
- **JavaScript/TypeScript** (`package.json`)

## Migration from vim-projectionist

This plugin is a drop-in replacement for vim-projectionist. All existing `.projections.json` files will work without modification.

## Development

### Requirements
- Neovim 0.11+
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) (for testing)

### Running Tests

```bash
# Install test dependencies locally
git clone https://github.com/nvim-lua/plenary.nvim lua_modules/plenary

# Run tests (choose one method)

# Method 1: Using single quotes (recommended for zsh/bash)
nvim --headless -u test/minimal_init.vim -c 'lua require("plenary.test_harness").test_directory("test/", {minimal_init = "test/minimal_init.vim"})' -c 'qa!'

# Method 2: Using Make (most portable)
make test

# Method 3: Using a test script
./test.sh
```

## Contributing

Contributions are welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

Same terms as Vim itself. See `:help license`.

## Credits

- Original [vim-projectionist](https://github.com/tpope/vim-projectionist) by Tim Pope
- Lua port by [e-roux](https://github.com/e-roux)
