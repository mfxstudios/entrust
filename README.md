# entrust

> Automate iOS development from JIRA/Linear ticket to PR using Claude Code

**entrust** is a Swift CLI tool that fully automates the development workflow: fetch a task from JIRA or Linear, run Claude Code to implement it, and create a pull request - all with a single command.

## Features

- **JIRA & Linear Integration**: Fetch tasks with full context
- **Claude Code Automation**: AI implements features automatically
- **Git Integration**: Auto-creates branches and commits
- **GitHub PRs**: Creates pull requests with detailed descriptions
- **Status Updates**: Automatically updates ticket status
- **Swift Testing**: Optional test execution before PR creation

## Installation

### Via Mint (Recommended)

```bash
mint install username/entrust
```

### Via Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/username/entrust.git", from: "2.0.0")
]
```

### Build from Source

```bash
git clone https://github.com/username/entrust.git
cd entrust
swift build -c release
cp .build/release/entrust /usr/local/bin/
```

## Quick Start

### 1. Setup

```bash
# Interactive configuration
entrust setup

# You'll be prompted for:
# - Task tracker (jira/linear)
# - GitHub repository
# - Credentials (stored securely in Keychain)
```

### 2. Run Automation

```bash
# Process a single task
entrust run IOS-1234

# With options
entrust run IOS-1234 --draft --skip-tests
```

## Commands

### `setup`

Configure credentials and preferences.

```bash
entrust setup          # Interactive configuration
entrust setup --show   # Display current configuration
entrust setup --clear  # Clear all stored configuration
```

### `run`

Process a single task from JIRA or Linear.

```bash
entrust run <task-id> [options]

Options:
  --tracker <type>        Task tracker [jira/linear]
  --repo <org/repo>       GitHub repository
  --base-branch <branch>  Base branch (default: main)
  --draft                 Create PR as draft
  --skip-tests            Skip running tests
  --dry-run               Show execution plan without running
```

### `status`

Check configuration and credentials.

```bash
entrust status
```

## Configuration

### Configuration File

Settings are stored in `~/.entrust/config.json`:

```json
{
  "trackerType": "jira",
  "jiraURL": "https://your-company.atlassian.net",
  "jiraEmail": "you@company.com",
  "repo": "your-org/your-repo",
  "baseBranch": "main",
  "useGHCLI": false,
  "runTestsByDefault": true,
  "autoCreateDraft": false
}
```

### Credentials

Credentials are stored securely in macOS Keychain:
- JIRA API token
- Linear API token
- GitHub personal access token (if not using gh CLI)

## Workflow

When you run `entrust run IOS-1234`, the tool:

1. **Fetches** the task from JIRA/Linear
2. **Creates** a feature branch (e.g., `feature/IOS-1234-implement-login`)
3. **Runs** Claude Code with task context: `claude -p "prompt"`
4. **Tests** the implementation (unless `--skip-tests`)
5. **Commits** changes with descriptive message
6. **Pushes** to GitHub
7. **Creates** pull request
8. **Updates** task status to "In Review"


## Claude Code

This tool requires [Claude Code](https://claude.com/code) to be installed:

```bash
# Check Claude Code is installed
claude --version

# Claude Code runs with: claude -p "your prompt here"
# It works directly in your repository, making changes autonomously
```

## Requirements

- macOS 12.0+
- Swift 6.0+
- [Claude Code](https://claude.com/code) installed
- Git configured
- JIRA or Linear account
- GitHub account

## Development

### Running Tests

```bash
swift test
```

### Project Structure

```
Sources/entrust/
├── AIAgent/              # Claude Code integration
├── TaskTracker/          # JIRA & Linear integrations
│   ├── JIRA/
│   └── Linear/
├── Managers/             # GitHub, Configuration, Keychain
├── Subcommands/          # CLI commands (setup, run, status)
├── Extensions/           # String sanitization, etc.
└── TicketAutomation.swift  # Main workflow orchestration
```

## License

MIT License - see LICENSE file for details

## Acknowledgments

- Inspired by [claude-intern](https://github.com/danii1/claude-intern)
- Built with [Swift Argument Parser](https://github.com/apple/swift-argument-parser)
- Powered by [Claude Code](https://claude.com/code)
