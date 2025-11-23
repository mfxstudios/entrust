# Entrust

A CLI tool for automating software development workflows by integrating task trackers (JIRA, Linear, Apple Reminders) with AI coding agents and GitHub.

## Features

- **Multi-Tracker Support**: Connect to JIRA, Linear, or Apple Reminders as your task source
- **AI Agent Integration**: Works with Claude Code, Aider, Cursor, or custom AI CLI tools
- **GitHub Automation**: Automatically creates branches, commits, and pull requests
- **Parallel Execution**: Process multiple tasks concurrently
- **Configurable Prompts**: Customize AI prompts via template files

## Requirements

- macOS 15.0+
- Swift 6.2+
- One of the supported AI agents installed (e.g., `claude`, `aider`, `cursor`)
- GitHub CLI (`gh`) recommended for GitHub operations

## Installation

### Using Mint

```bash
mint install <username>/entrust
```

### Using Swift Package Manager

```bash
git clone https://github.com/<username>/entrust.git
cd entrust
swift build -c release
cp .build/release/entrust /usr/local/bin/
```

### From Source

```bash
swift build
swift run entrust --help
```

## Quick Start

### 1. Configure the tool

```bash
entrust setup
```

This interactive setup will guide you through configuring:
- Task tracker (JIRA, Linear, or Reminders)
- GitHub repository and authentication
- AI agent selection
- Default preferences

### 2. Run a task

```bash
# Process a single task
entrust run TASK-123

# Process multiple tasks in parallel
entrust parallel TASK-123 TASK-124 TASK-125
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

Process a single task from your tracker.

```bash
entrust run <task-id> [options]

Options:
  --repo <org/repo>       Override default repository
  --base-branch <branch>  Override default base branch (default: main)
  --draft                 Create PR as draft
  --skip-tests            Skip running tests
  --ai-agent <agent>      AI agent to use (claude-code, aider, cursor, custom)
  --custom-command <cmd>  Custom AI CLI command (when using --ai-agent custom)
  --context <text>        Additional context for the AI agent
```

### `parallel`

Process multiple tasks concurrently.

```bash
entrust parallel <task-ids>... [options]

Options:
  --max-concurrent <n>    Maximum concurrent tasks (default: 3)
  --repo <org/repo>       Override default repository
  --base-branch <branch>  Override default base branch
  --draft                 Create PRs as drafts
  --skip-tests            Skip running tests
  --ai-agent <agent>      AI agent to use
```

## Configuration

### Configuration File

Settings are stored in `~/.entrust/config.json`:

```json
{
  "trackerType": "jira",
  "jiraURL": "https://your-org.atlassian.net",
  "jiraEmail": "you@example.com",
  "repo": "org/repo",
  "baseBranch": "main",
  "useGHCLI": true,
  "autoCreateDraft": false,
  "aiAgentType": "claude-code",
  "runTestsByDefault": true
}
```

### Credentials

Sensitive credentials are stored securely in the macOS Keychain:
- JIRA API Token
- Linear API Token
- GitHub Personal Access Token (if not using GitHub CLI)

## Task Trackers

### JIRA

Requires:
- JIRA URL (e.g., `https://your-org.atlassian.net`)
- Email address
- API Token ([Generate here](https://id.atlassian.com/manage-profile/security/api-tokens))

### Linear

Requires:
- API Token ([Generate here](https://linear.app/settings/api))

### Apple Reminders

Uses the native macOS Reminders app as a Kanban board:
- Create lists for each column (e.g., "Backlog", "In Progress", "Done")
- Tasks are read from your configured list
- Requires Reminders access permission

## AI Agents

### Claude Code (Default)

```bash
# Ensure Claude Code is installed
claude --version

# Use with entrust
entrust run TASK-123 --ai-agent claude-code
```

### Aider

```bash
# Install Aider
pip install aider-chat

# Use with entrust
entrust run TASK-123 --ai-agent aider
```

### Cursor

```bash
# Use Cursor CLI
entrust run TASK-123 --ai-agent cursor
```

### Codex

```bash
# Use OpenAI Codex CLI
entrust run TASK-123 --ai-agent codex
```

### Gemini

```bash
# Use Google Gemini CLI
entrust run TASK-123 --ai-agent gemini
```

### Copilot

```bash
# Use GitHub Copilot via gh CLI
# Requires: gh extension install github/gh-copilot
entrust run TASK-123 --ai-agent copilot
```

## Workflow

When you run `entrust run TASK-123`, the tool:

1. **Fetches** the task from your configured tracker
2. **Creates** a new git branch (e.g., `feature/TASK-123-implement-login`)
3. **Generates** a prompt from the task details
4. **Invokes** the AI agent with the prompt
5. **Runs** tests (unless `--skip-tests`)
6. **Commits** changes with a descriptive message
7. **Creates** a pull request on GitHub
8. **Updates** the task status and adds the PR link

## Development

### Running Tests

```bash
swift test
```

### Building

```bash
swift build
```

### Project Structure

```
Sources/entrust/
├── AIAgent/              # AI agent protocol and implementations
├── Managers/             # Configuration and keychain management
├── Models/               # Data models
├── Prompt/               # Prompt template system
├── Services/             # GitHub service
├── Subcommands/          # CLI commands (setup, run, parallel)
├── TaskTracker/          # Task tracker implementations
│   ├── JIRA/
│   ├── Linear/
│   └── Reminders/
└── entrust.swift         # Main entry point

Tests/entrustTests/
├── Mocks/                # Test mocks
├── Models/               # Model tests
├── Prompt/               # Prompt template tests
├── Services/             # Service tests
└── TaskTracker/          # Tracker tests
```

## License

MIT License
