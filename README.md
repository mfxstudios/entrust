# entrust

> Automate your development workflow from task tracker to pull request using Claude Code

**entrust** is a Swift CLI tool that automates the entire development workflow: fetch tasks from JIRA or Linear, implement them using Claude Code AI, run tests with automatic retry, and create pull requests - all with a single command. It also handles PR feedback iteration by continuing Claude Code sessions automatically.

[![Swift 6.0+](https://img.shields.io/badge/Swift-6.0+-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey.svg)](https://www.apple.com/macos/)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

## ✨ Features

- **🎫 Task Tracker Integration**: Fetch tasks from JIRA or Linear with full context
- **🤖 Claude Code Automation**: AI implements features with real-time streaming output
- **💬 PR Feedback Loop**: Address reviewer feedback by continuing Claude sessions
- **🔄 Automatic Test Retry**: Runs tests and asks Claude to fix failures (configurable retries)
- **🌿 Git Worktrees**: Isolated execution environments prevent conflicts
- **⚡ Parallel Processing**: Process multiple tickets concurrently
- **📝 Smart PR Summaries**: Auto-generates structured PR descriptions with context
- **🔧 Session Management**: View and continue previous Claude Code sessions
- **🔐 Project-Level Config**: Each project has its own configuration and credentials
- **🔍 Auto-Detection**: Automatically detects GitHub org/repo from git remote

## 🚀 Installation

### Prerequisites

- **macOS** 15.0+ or **Linux** (Ubuntu 20.04+, other distributions)
  - macOS: Uses Keychain for secure credential storage (project-specific)
  - Linux: Uses file-based storage in `.entrust/credentials/` with secure permissions (project-specific)
- Swift 6.0+
- [Claude Code](https://claude.ai/claude-code) installed (`claude --version`)
- Git configured
- JIRA or Linear account
- GitHub account with `gh` CLI (optional, can use API tokens)

### Via Mint (Recommended for macOS)

[Mint](https://github.com/yonaskolb/Mint) is a package manager for Swift command-line tools.

```bash
# Install Mint if you haven't already
brew install mint

# Install entrust
mint install mfxstudios/entrust
```

### Build from Source (macOS & Linux)

**On macOS:**
```bash
git clone https://github.com/mfxstudios/entrust.git
cd entrust
swift build -c release
cp .build/release/entrust /usr/local/bin/
```

**On Linux:**
```bash
# Install Swift 6.0+ if not already installed
# See: https://swift.org/download/

git clone https://github.com/mfxstudios/entrust.git
cd entrust
swift build -c release
sudo cp .build/release/entrust /usr/local/bin/
```

### Verify Installation

```bash
entrust --version
entrust --help
```

## 🎯 Quick Start

### 1. Initial Setup

Navigate to your project directory and configure your task tracker and GitHub credentials:

```bash
cd /path/to/your/project
entrust setup
```

**Important:** Configuration is project-specific. Run `entrust setup` in each project directory where you want to use entrust.

You'll be prompted for:
- Task tracker type (jira/linear)
- JIRA URL and email (if using JIRA)
- GitHub repository (auto-detected from git remote, or enter manually)
- Base branch (default: `main`)
- API tokens (stored securely - Keychain on macOS, `.entrust/credentials/` on Linux)

This creates:
- `.env` - Project configuration file
- `.entrust/credentials/` (Linux only) - Encrypted credential storage

**Add to `.gitignore`:**
```
.env
.entrust/
```

### 2. Process a Single Task

```bash
# Fetch ticket IOS-1234, implement it with Claude, create PR
entrust run IOS-1234

# With options
entrust run IOS-1234 --draft --skip-tests

# Run in a new terminal window (keeps your current terminal free)
entrust run IOS-1234 --new-terminal
```

### 3. Process Multiple Tasks in Parallel

```bash
# Process 3 tickets concurrently
entrust parallel IOS-1234 IOS-1235 IOS-1236

# From a file with custom concurrency
entrust parallel --file tickets.txt --max-concurrent 5
```

### 4. Address PR Feedback

When reviewers leave feedback on your PR:

```bash
# Address feedback on PR #456
entrust feedback 456

# Or using full URL
entrust feedback https://github.com/myorg/myrepo/pull/456
```

## 📚 Commands

### `setup`

Configure task tracker and GitHub credentials.

```bash
entrust setup          # Interactive configuration
entrust setup --show   # Display current settings (tokens hidden)
entrust setup --clear  # Clear all configuration and credentials
```

**Project-Level Configuration:**
- Configuration is stored per-project in `.env` file in the current directory
- Credentials are stored project-specifically (macOS Keychain uses project path hash, Linux uses `.entrust/credentials/`)
- Each project can have different JIRA instances, GitHub repos, and settings
- Run `entrust setup` in each project directory where you want to use entrust

**Auto-detection:**
- When run from a git repository, `setup` automatically detects the GitHub org/repo from the `origin` remote
- Supports both SSH (`git@github.com:org/repo.git`) and HTTPS (`https://github.com/org/repo.git`) formats
- Simply press Enter to accept the detected value, or type a different org/repo to override

### `run`

Process a single task using an isolated git worktree.

```bash
entrust run <task-id> [options]

Options:
  --draft                 Create PR as draft
  --skip-tests            Skip running tests
  --new-terminal          Run Claude Code in a new terminal window
  --repo-root <path>      Repository root directory
```

**Workflow:**
1. Creates isolated worktree in `/tmp/entrust-<ticket>-<uuid>`
2. Fetches task from JIRA/Linear
3. Updates ticket status to "In Progress"
4. Runs Claude Code with streaming output
5. Runs tests with automatic retry on failure (up to 3 attempts)
6. Commits and pushes changes
7. Creates pull request with structured description
8. Updates ticket status to "In Review"
9. Cleans up worktree

### Interactive Mode (`--interactive`)

**NEW!** Guide Claude through implementation interactively with real-time chat, then auto-complete with tests & PR.

```bash
entrust run <task-id> --interactive [options]
```

**Workflow:**
1. Fetches task from JIRA/Linear
2. Updates ticket status to "In Progress"
3. **Starts interactive chat session** - you guide Claude conversationally
4. Type `done` or `finish` when ready to proceed
5. **Automated completion**: runs tests, commits, pushes, creates PR
6. Updates ticket status to "In Review"

**Example session:**
```bash
$ entrust run IOS-1234 --interactive

🎯 Interactive Mode - IOS-1234
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📋 Task: Add dark mode support
💬 Starting Interactive Session

Commands:
  • Type your messages to guide Claude
  • Type 'done' or 'finish' to end and proceed to automation
  • Type 'cancel' to exit without automation

🤖 Claude:
I'll help you add dark mode support. Let me start by...

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
You: Let's use a theme manager pattern instead

🤖 Claude:
Good idea! I'll refactor to use a ThemeManager...

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
You: done

✅ Interactive session complete!

🤖 Starting Automation Flow
🧪 Running tests...
✅ Tests passed
🌿 Creating branch: feature/IOS-1234
📬 Creating pull request...
✅ Complete!
```

**Use cases:**
- Complex features that need iterative refinement
- Learning how Claude approaches problems
- Situations requiring human judgment during implementation
- Debugging tricky issues step-by-step

### `parallel`

Process multiple tasks concurrently using isolated worktrees.

```bash
entrust parallel <task-id> [<task-id> ...] [options]

Options:
  --file <path>           Read ticket IDs from file (one per line)
  --max-concurrent <n>    Maximum concurrent tasks (default: 3)
  --draft                 Create PRs as drafts
  --skip-tests            Skip running tests
  --new-terminal          Run each ticket in a separate terminal window
  --interactive           Interactive mode (auto-enables --new-terminal)
```

**Examples:**

```bash
# Process specific tickets
entrust parallel IOS-1234 IOS-1235 IOS-1236

# Process from file with higher concurrency
entrust parallel --file sprint-tickets.txt --max-concurrent 5

# Create draft PRs for review
entrust parallel IOS-1234 IOS-1235 --draft

# Launch each ticket in its own terminal window (best for monitoring)
entrust parallel IOS-1234 IOS-1235 IOS-1236 --new-terminal

# Interactive mode for multiple tickets - guide Claude in each terminal
entrust parallel IOS-1234 IOS-1235 --interactive
```

**Notes:**
- When using `--new-terminal`, each ticket runs in a dedicated terminal window instead of using worktree-based parallelization. This provides better visibility but doesn't enforce the `--max-concurrent` limit.
- `--interactive` automatically enables `--new-terminal` and launches each ticket with interactive mode, allowing you to guide Claude separately in each terminal window.

### `feedback`

Address PR feedback by continuing the Claude Code session.

```bash
entrust feedback <pr-number or url> [options]

Options:
  --repo-root <path>      Repository root directory
  --all                   Process all comments (including previously processed)
```

**How it works:**
- Fetches PR comments from GitHub API
- Filters actionable comments:
  - All comments from "Request Changes" reviews
  - Any comment containing `**entrust**` or `entrust:` trigger
- Continues the original Claude Code session with feedback
- Runs tests with automatic retry
- Commits and pushes fixes
- Tracks processed comments to avoid duplicates

**Reviewer triggers:**

```markdown
<!-- In a PR review -->
**entrust** please add error handling here

<!-- Or with prefix -->
entrust: refactor this to use async/await

<!-- Or just mark review as "Request Changes" -->
This needs better validation
```

### `continue`

Continue a previous Claude Code session with additional instructions.

```bash
entrust continue <session-id or "latest"> <prompt>

Options:
  --working-directory <path>   Working directory for the session
```

**Examples:**

```bash
# Continue latest session
entrust continue latest "Add documentation to the new functions"

# Continue specific session
entrust continue abc123def "Fix the failing test"
```

### `sessions`

View Claude Code session history.

```bash
entrust sessions [options]

Options:
  --project <path>        Filter sessions by project path
  --verbose               Show detailed session information
  --limit <n>             Limit number of sessions to show
```

### `status`

Change ticket status manually.

```bash
entrust status <ticket-id> <status>

Example:
  entrust status IOS-1234 "In Review"
```

## ⚙️ Configuration

### Configuration File

Settings are stored in `.env` files. Priority order:
1. `.env` in current directory (project-specific)
2. `~/.entrust/.env` (global configuration)

**Example `.env` for JIRA:**

```bash
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
MAX_RETRY_ATTEMPTS=3
USE_NEW_TERMINAL=false
```

**Example `.env` for Linear:**

```bash
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
MAX_RETRY_ATTEMPTS=3
USE_NEW_TERMINAL=false
```

### Credentials (Keychain)

API tokens are **never** stored in `.env` files. They're stored securely in macOS Keychain:

- **JIRA API token**: Required when `TRACKER_TYPE=jira`
- **Linear API token**: Required when `TRACKER_TYPE=linear`
- **GitHub token**: Required when `USE_GH_CLI=false`

Run `entrust setup` to configure credentials securely.

### Test Retry Configuration

Control automatic test retry behavior:

```bash
# In .env file
MAX_RETRY_ATTEMPTS=3  # Default: 3, Range: 0-10

# 0 = No retry (fail immediately)
# 1 = Retry once
# 3 = Retry up to 3 times (recommended)
```

### New Terminal Mode

Run Claude Code in a separate terminal window to keep your current terminal free:

```bash
# In .env file
USE_NEW_TERMINAL=true  # Default: false

# Or use the command-line flag (single ticket)
entrust run IOS-1234 --new-terminal

# For parallel processing (each ticket in its own window)
entrust parallel IOS-1234 IOS-1235 IOS-1236 --new-terminal
```

**How it works:**
- **macOS**: Automatically detects and uses Terminal.app or iTerm2
- **Linux**: Supports gnome-terminal, konsole, xfce4-terminal, and xterm
- The original terminal returns immediately while Claude Code runs in the new window
- The new window stays open after completion so you can review the output
- With `parallel --new-terminal`, each ticket gets its own dedicated window

**Use cases:**
- Working on multiple tickets simultaneously (each in its own window)
- Keeping your main terminal free for other commands
- Better visibility of Claude Code's streaming output
- Easier to monitor long-running tasks
- Visual separation when processing multiple tickets

## 🔄 Workflows

### Single Task Workflow

```
entrust run IOS-1234
    ↓
[Create worktree] → /tmp/entrust-IOS-1234-abc123
    ↓
[Fetch task] → "Add user authentication"
    ↓
[Update status] → "In Progress"
    ↓
[Run Claude Code] → Streaming implementation
    ↓
[Run tests] → PASSED ✓
    ↓
[Commit & push] → feature/IOS-1234
    ↓
[Create PR] → github.com/org/repo/pull/456
    ↓
[Update status] → "In Review"
    ↓
[Cleanup worktree]
```

### Test Retry Workflow

```
[Run tests]
    ↓
FAILED ✗ → "Expected 200, got 404"
    ↓
[Attempt 1/3] → Continue Claude session with error
    ↓
Claude analyzes error and fixes code
    ↓
[Run tests again]
    ↓
FAILED ✗ → "Timeout on line 45"
    ↓
[Attempt 2/3] → Continue with new error
    ↓
Claude fixes timeout issue
    ↓
[Run tests again]
    ↓
PASSED ✓ → Tests succeed!
```

### PR Feedback Workflow

```
[PR #456 created]
    ↓
Reviewer adds feedback:
  - "Request Changes" review with 3 comments
  - General comment: "**entrust** add error handling"
    ↓
entrust feedback 456
    ↓
[Fetch PR comments] → 4 actionable comments
    ↓
[Load session] → abc123def (from PR metadata)
    ↓
[Recreate worktree] → feature/IOS-1234
    ↓
[Continue Claude session] → "Address the following feedback: ..."
    ↓
[Run tests] → PASSED ✓
    ↓
[Commit & push] → "[IOS-1234] Address PR feedback"
    ↓
[Mark comments processed] → Track IDs to avoid duplicates
```

### Parallel Workflow

```
entrust parallel IOS-1234 IOS-1235 IOS-1236 --max-concurrent 3
    ↓
[Create 3 worktrees in parallel]
  ├─ /tmp/entrust-IOS-1234-abc
  ├─ /tmp/entrust-IOS-1235-def
  └─ /tmp/entrust-IOS-1236-ghi
    ↓
[Process concurrently]
  ├─ [IOS-1234] Fetching... Running Claude... Testing... ✓
  ├─ [IOS-1235] Fetching... Running Claude... Testing... ✓
  └─ [IOS-1236] Fetching... Running Claude... Testing... ✓
    ↓
[Summary Report]
  ✓ 3 succeeded
  ✗ 0 failed
  → 3 PRs created
```

## 🏗️ Architecture

### Project Structure

```
Sources/entrust/
├── AIAgent/              # Claude Code SDK integration
│   └── AIAgent.swift     # Streaming execution with AsyncSequence
├── TaskTracker/          # Task management
│   ├── JIRA/            # JIRA API integration
│   └── Linear/          # Linear API integration
├── Managers/            # Core services
│   ├── GitHubService.swift       # PR creation, comments, worktrees
│   ├── ConfigurationManager.swift # .env file management
│   └── KeychainManager.swift     # Secure credential storage
├── Storage/             # Session persistence
│   └── PRSessionStorage.swift    # PR/session mapping
├── Subcommands/         # CLI commands
│   ├── Run.swift
│   ├── Parallel.swift
│   ├── Feedback.swift   # NEW: PR feedback handling
│   ├── Continue.swift
│   ├── Sessions.swift
│   ├── Setup.swift
│   └── Status.swift
└── TicketAutomation.swift        # Main workflow orchestration
```

### Key Components

**Claude Code Integration:**
- Uses [claude-code-sdk-swift](https://github.com/mfxstudios/claude-code-sdk-swift)
- Real-time streaming output with AsyncSequence
- Automatic backend detection (Agent SDK or Headless)
- Session management for conversation continuation

**Git Worktrees:**
- Isolated execution in `/tmp/entrust-<ticket>-<uuid>`
- No conflicts between parallel tasks
- Clean state for each task
- Easy debugging with `--keep-worktree`

**Test Retry System:**
- Configurable retry attempts (0-10)
- Multi-turn conversation with Claude
- Provides error context on each retry
- Automatic cleanup on success

**PR Feedback System:**
- Session ID stored in PR description (HTML comment)
- Local session database (`~/.entrust/pr-sessions.json`)
- Comment filtering with triggers
- Tracks processed comments to avoid duplicates

## 🧪 Development

### Running Tests

```bash
swift test                    # Run all tests
swift test --parallel         # Run tests in parallel
```

**Test Coverage:**
- 142 tests across 66 test suites
- Unit tests for all core functionality
- BDD-style tests with Given/When/Then naming
- Tests for PR feedback filtering, session storage, and streaming

### Building

```bash
swift build                   # Debug build
swift build -c release        # Release build
```

### Testing Locally

```bash
# Build and run
swift build
.build/debug/entrust --help

# Test with a real ticket
.build/debug/entrust run TEST-123 --skip-tests

# Install locally with Mint (for testing installation)
mint install . --force
```

## 📄 License

MIT License
