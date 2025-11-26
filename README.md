# entrust

> Automate iOS development from JIRA/Linear ticket to PR using Claude Code

**entrust** is a Swift CLI tool that fully automates the development workflow: fetch a task from JIRA or Linear, run Claude Code to implement it, and create a pull request - all with a single command.

## Features

- **JIRA & Linear Integration**: Fetch tasks with full context
- **Claude Code Automation**: AI implements features automatically
- **Git Worktrees**: Isolated execution environments prevent conflicts
- **Parallel Processing**: Process multiple tickets concurrently
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

# Process multiple tasks in parallel
entrust parallel IOS-1234 IOS-1235 IOS-1236

# From a file (one ticket per line)
entrust parallel --file tickets.txt --max-concurrent 5
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

Process a single task from JIRA or Linear using an isolated git worktree.

```bash
entrust run <task-id> [options]

Options:
  --tracker <type>        Task tracker [jira/linear]
  --repo <org/repo>       GitHub repository
  --base-branch <branch>  Base branch (default: main)
  --draft                 Create PR as draft
  --skip-tests            Skip running tests
  --dry-run               Show execution plan without running
  --keep-worktree         Keep worktree after completion (for debugging)
```

**How it works:**
- Creates an isolated git worktree in `/tmp/entrust-<ticket>-<uuid>`
- Runs Claude Code in the worktree to implement the feature
- Tests, commits, and pushes changes from the worktree
- Creates a pull request and updates the ticket status
- Automatically cleans up the worktree (unless `--keep-worktree` is used)

### `parallel`

Process multiple tasks concurrently using isolated git worktrees.

```bash
entrust parallel <task-id> [<task-id> ...] [options]

Options:
  --file <path>           Read ticket IDs from file (one per line)
  --max-concurrent <n>    Maximum concurrent tasks (default: 3)
  --tracker <type>        Task tracker [jira/linear]
  --repo <org/repo>       GitHub repository
  --base-branch <branch>  Base branch (default: main)
  --draft                 Create PR as draft
  --skip-tests            Skip running tests
  --dry-run               Show execution plan without running
  --keep-worktrees        Keep worktrees after completion (for debugging)
```

**Examples:**

```bash
# Process 3 tickets in parallel
entrust parallel IOS-1234 IOS-1235 IOS-1236

# Process tickets from a file with higher concurrency
entrust parallel --file sprint-tickets.txt --max-concurrent 5

# Preview what would be processed
entrust parallel IOS-1234 IOS-1235 --dry-run
```

**How it works:**
- Each ticket gets its own isolated git worktree in `/tmp/entrust-<ticket>-<uuid>`
- Tasks are processed concurrently up to `--max-concurrent` limit
- Each task runs Claude Code independently in its own worktree
- Provides real-time progress output prefixed with `[ticket-id]`
- Displays a summary report at the end with success/failure counts
- Automatically cleans up all worktrees (unless `--keep-worktrees` is used)

### `status`

Check configuration and credentials.

```bash
entrust status
```

## Configuration

### Configuration File

Settings are stored in a `.env` file. The tool checks for `.env` in the current directory first, then falls back to `~/.entrust/.env`:

**Example for JIRA:**
```bash
# entrust configuration

# Task Tracker Settings
TRACKER_TYPE=jira
JIRA_URL=https://your-company.atlassian.net
JIRA_EMAIL=you@company.com

# GitHub Settings
GITHUB_REPO=your-org/your-repo
BASE_BRANCH=main
USE_GH_CLI=true
AUTO_CREATE_DRAFT=false

# AI Agent Settings
AI_AGENT_TYPE=claude-code

# Execution Settings
RUN_TESTS_BY_DEFAULT=true
```

**Example for Linear:**
```bash
# entrust configuration

# Task Tracker Settings
TRACKER_TYPE=linear

# GitHub Settings
GITHUB_REPO=your-org/your-repo
BASE_BRANCH=main
USE_GH_CLI=true
AUTO_CREATE_DRAFT=false

# AI Agent Settings
AI_AGENT_TYPE=claude-code

# Execution Settings
RUN_TESTS_BY_DEFAULT=true
```

**Priority Order:**
1. `.env` in current directory (project-specific configuration)
2. `~/.entrust/.env` (global configuration)

This allows you to have project-specific settings that override your global defaults.

### Credentials

API tokens and credentials are **never** stored in `.env` files. They are stored securely in macOS Keychain:
- **JIRA API token**: Required when `TRACKER_TYPE=jira`
- **Linear API token**: Required when `TRACKER_TYPE=linear`
- **GitHub personal access token**: Required when `USE_GH_CLI=false`

Run `entrust setup` to securely store your credentials in the Keychain.

## Workflow

### Single Task (`run`)

When you run `entrust run IOS-1234`, the tool:

1. **Creates** an isolated git worktree in `/tmp/entrust-IOS-1234-<uuid>`
2. **Fetches** the task from JIRA/Linear
3. **Updates** ticket status to "In Progress"
4. **Creates** a feature branch (e.g., `feature/IOS-1234`)
5. **Runs** Claude Code in the worktree: `claude -p "prompt"`
6. **Tests** the implementation in the worktree (unless `--skip-tests`)
7. **Commits** changes with descriptive message
8. **Pushes** to GitHub
9. **Creates** pull request
10. **Updates** task status to "In Review"
11. **Cleans up** the worktree (unless `--keep-worktree`)

### Multiple Tasks (`parallel`)

When you run `entrust parallel IOS-1234 IOS-1235 IOS-1236`, the tool:

1. **Creates** isolated git worktrees for each ticket
2. **Processes** up to `--max-concurrent` (default 3) tickets simultaneously
3. **Each ticket** follows the same workflow as `run`, but in its own worktree
4. **Displays** real-time progress for all running tasks
5. **Prints** a summary report with success/failure counts and PR URLs
6. **Cleans up** all worktrees (unless `--keep-worktrees`)

### Why Worktrees?

Git worktrees provide isolation between tasks:
- **No conflicts**: Each task works in its own directory
- **Clean state**: Fresh working directory per task
- **Parallel safety**: Multiple Claude Code instances don't interfere
- **Easy debugging**: Use `--keep-worktree` to inspect the state after execution


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
├── Subcommands/          # CLI commands (setup, run, parallel, status)
├── Extensions/           # String sanitization, etc.
└── TicketAutomation.swift  # Main workflow orchestration
```

## License

MIT License - see LICENSE file for details

## Acknowledgments

- Inspired by [claude-intern](https://github.com/danii1/claude-intern)
- Built with [Swift Argument Parser](https://github.com/apple/swift-argument-parser)
- Powered by [Claude Code](https://claude.com/code)
