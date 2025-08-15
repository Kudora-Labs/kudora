# Contributing to Kudora

Thank you for your interest in contributing to Kudora! This document provides guidelines and information for contributors.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [How to Contribute](#how-to-contribute)
- [Branch Naming Convention](#branch-naming-convention)
- [Pull Request Process](#pull-request-process)
- [Code Review Requirements](#code-review-requirements)
- [Development Guidelines](#development-guidelines)
- [Testing Requirements](#testing-requirements)
- [Issue Guidelines](#issue-guidelines)

## Code of Conduct

By participating in this project, you agree to abide by our Code of Conduct. Please treat all contributors and users with respect and kindness.

## Getting Started

### Prerequisites

- Go 1.23+
- Make

### Setup Development Environment

```bash
# Fork and clone the repository
git clone https://github.com/YOUR_USERNAME/kudora.git
cd kudora

# Add upstream remote
git remote add upstream https://github.com/kudora-labs/kudora.git
```

### Local Node Setup

Follow these steps to build and run a local Kudora node:

#### 1. Build and Install

```bash
make install
```

_Compiles and installs the kudorad binary (Kudora daemon)_

#### 2. Configure PATH

The `kudorad` binary needs to be accessible in your system's `$PATH`:

**MacOS (zsh):**

```bash
echo 'export PATH="$(go env GOPATH)/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

**Windows:**

```cmd
# Add $(go env GOPATH)\bin to your PATH environment variable
```

**Linux:**

```bash
echo 'export PATH="$(go env GOPATH)/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

#### 3. Initialize Node

```bash
kudorad init Node-1 --chain-id kudora_12000-1 --home ./node-1
```

_Creates a new blockchain node named "Node-1" with chain ID "kudora_12000-1", storing data in `./node-1` directory_

#### 4. Create Wallet

```bash
kudorad keys add alice --keyring-backend file --home ./node-1
```

_Creates a new wallet/account named "alice" using file-based keyring storage_

#### 5. Setup Genesis Account

```bash
kudorad genesis add-genesis-account alice 1800000000000000000000000000kud --home ./node-1 --keyring-backend file
```

_Adds Alice's account to the genesis block with 1.8 billion KUD tokens initial balance_

#### 6. Create Genesis Transaction

```bash
kudorad genesis gentx alice 1000000000000000000kud --chain-id=kudora_12000-1 --keyring-backend file --home=./node-1
```

_Creates a genesis transaction where Alice stakes 1 billion KUD to become a founding validator_

#### 7. Collect Genesis Transactions

```bash
kudorad genesis collect-gentxs --home=./node-1
```

_Collects all genesis transactions and incorporates them into the genesis block_

#### 8. Configure Client

```bash
kudorad config set client chain-id kudora_12000-1 --home ./node-1
```

_Sets the default chain ID for client commands_

#### 9. Validate Genesis

```bash
kudorad genesis validate-genesis --home=./node-1
```

_Validates that the genesis file is properly formatted and valid_

#### 10. Enable APIs

Edit `./node-1/config/app.toml` and set:

```toml
[json-rpc]
enable = true

[api]
enable = true
```

_Enables JSON-RPC and API endpoints for interacting with the blockchain_

#### 11. Start Node

```bash
kudorad start --home ./node-1
```

_Starts the blockchain node and begins block production_

This creates a **single-node blockchain network** where Alice is both the sole validator and initial token holder, suitable for local development and testing.

## How to Contribute

### Types of Contributions

We welcome various types of contributions:

- **Bug fixes**: Fix issues in existing code
- **Features**: Add new functionality
- **Documentation**: Improve or add documentation
- **Tests**: Add or improve test coverage
- **Performance**: Optimize existing code
- **Security**: Fix security vulnerabilities

### Before You Start

1. **Check existing issues**: Look for existing issues or discussions
2. **Create an issue**: For significant changes, create an issue first to discuss
3. **Fork the repository**: Create your own fork to work on
4. **Create a branch**: Follow our branch naming convention

## Branch Naming Convention

Use the following prefixes for your branch names:

### Required Format

```
<type>/<short-description>
```

### Branch Types

- **`feat/`**: New features or enhancements

  - Example: `feat/add-staking-rewards`
  - Example: `feat/evm-smart-contract-support`

- **`fix/`**: Bug fixes

  - Example: `fix/validation-error-handling`
  - Example: `fix/ibc-connection-timeout`

- **`chore/`**: Maintenance tasks, dependencies, build improvements

  - Example: `chore/update-cosmos-sdk`
  - Example: `chore/improve-makefile`

- **`docs/`**: Documentation updates

  - Example: `docs/update-api-reference`
  - Example: `docs/add-deployment-guide`

- **`test/`**: Adding or improving tests

  - Example: `test/add-integration-tests`
  - Example: `test/improve-simulation-coverage`

- **`refactor/`**: Code refactoring without functional changes

  - Example: `refactor/simplify-ante-handlers`
  - Example: `refactor/optimize-module-structure`

- **`security/`**: Security-related fixes or improvements
  - Example: `security/fix-validator-key-handling`
  - Example: `security/improve-transaction-validation`

### Branch Naming Examples

```bash
# Good examples
git checkout -b feat/add-governance-module
git checkout -b fix/resolve-memory-leak
git checkout -b chore/upgrade-dependencies
git checkout -b docs/add-api-examples
git checkout -b test/add-unit-tests-bank-module

# Bad examples (avoid these)
git checkout -b new-feature
git checkout -b bugfix
git checkout -b updates
```

## Pull Request Process

### 1. Prepare Your Pull Request

```bash
# Update your fork with latest changes
git fetch upstream
git checkout main
git merge upstream/main

# Create and switch to your feature branch
git checkout -b feat/your-feature-name

# Make your changes and commit
git add .
git commit -m "feat: add your feature description"

# Push to your fork
git push origin feat/your-feature-name
```

### 2. Create Pull Request

1. **Go to GitHub**: Navigate to your fork on GitHub
2. **Create PR**: Click "New Pull Request"
3. **Fill template**: Use our PR template (auto-populated)
4. **Add details**: Provide clear title and description

### 3. Pull Request Template

Your PR should include:

```markdown
## Description

Brief description of changes made.

## Type of Change

- [ ] Bug fix (non-breaking change which fixes an issue)
- [ ] New feature (non-breaking change which adds functionality)
- [ ] Breaking change (fix or feature that would cause existing functionality to not work as expected)
- [ ] Documentation update

## Testing

- [ ] Unit tests pass
- [ ] Integration tests pass
- [ ] Manual testing completed

## Checklist

- [ ] My code follows the project's style guidelines
- [ ] I have performed a self-review of my code
- [ ] I have commented my code, particularly in hard-to-understand areas
- [ ] I have made corresponding changes to the documentation
- [ ] My changes generate no new warnings
- [ ] I have added tests that prove my fix is effective or that my feature works

## Smart Contract Changes (if applicable)

- [ ] Smart contract code has been reviewed by at least 1 external developer
- [ ] Security considerations have been documented
- [ ] Gas optimization has been considered
```

## Code Review Requirements

### General Code Review

- **Minimum reviewers**: 1 approved review required
- **Reviewer selection**: At least one core team member or experienced contributor
- **Review scope**: Code quality, functionality, tests, documentation

### Smart Contract Code Review

**⚠️ CRITICAL REQUIREMENT for Smart Contract Changes:**

- **Minimum reviewers**: **At least 1 external developer** (not the author)
- **Required expertise**: Reviewer must have smart contract development experience
- **Security focus**: Special attention to security vulnerabilities
- **Documentation**: Security considerations must be documented

### Review Process

1. **Automated checks**: All CI checks must pass
2. **Code review**: Human review for logic, style, and best practices
3. **Testing**: Verify tests are comprehensive and passing
4. **Documentation**: Ensure documentation is updated if needed
5. **Security**: Special security review for smart contracts

## Development Guidelines

### Code Style

- **Go**: Follow standard Go conventions and use `gofmt`
- **Protobuf**: Follow protobuf style guide
- **Comments**: Add meaningful comments for complex logic
- **Naming**: Use descriptive variable and function names

### Git Commit Guidelines

Follow conventional commit format:

```
<type>(<scope>): <subject>

<body>

<footer>
```

**Types:**

- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation
- `style`: Formatting changes
- `refactor`: Code restructuring
- `test`: Adding tests
- `chore`: Maintenance

**Examples:**

```bash
feat(bank): add multi-send transaction support

Add support for sending tokens to multiple recipients in a single transaction.
This improves efficiency and reduces gas costs for batch operations.

Closes #123
```

### Code Quality

- **Linting**: Run `make lint` before submitting
- **Formatting**: Run `make format` to format code
- **Testing**: Ensure all tests pass with `make test`
- **Documentation**: Update relevant documentation

## Testing Requirements

### Required Tests

- **Unit tests**: For all new functions and methods
- **Integration tests**: For module interactions
- **Simulation tests**: For complex state changes
- **End-to-end tests**: For user-facing functionality

### Running Tests

```bash
# Run all tests
make test

# Run specific test types
make test-unit
make test-integration
make test-sim

# Run with coverage
make test-cover

# Run with race detection
make test-race
```

### Test Guidelines

- Tests should be deterministic and repeatable
- Use meaningful test names that describe what is being tested
- Include both positive and negative test cases
- Mock external dependencies appropriately

## Issue Guidelines

### Creating Issues

#### Bug Reports

Use this template for bug reports:

```markdown
**Bug Description**
A clear and concise description of the bug.

**Steps to Reproduce**

1. Step one
2. Step two
3. Step three

**Expected Behavior**
What you expected to happen.

**Actual Behavior**
What actually happened.

**Environment**

- OS: [e.g., macOS 14.0]
- Go version: [e.g., 1.23.1]
- Kudora version: [e.g., v1.0.0]

**Additional Context**
Any additional information, logs, or screenshots.
```

#### Feature Requests

Use this template for feature requests:

```markdown
**Feature Description**
A clear and concise description of the feature.

**Use Case**
Describe the use case and why this feature would be valuable.

**Proposed Solution**
Describe your proposed solution (if any).

**Alternatives Considered**
Describe alternative solutions you've considered.

**Additional Context**
Any additional context, mockups, or examples.
```

### Issue Labels

We use these labels to categorize issues:

- `bug`: Something isn't working
- `enhancement`: New feature or request
- `documentation`: Improvements or additions to documentation
- `good first issue`: Good for newcomers
- `help wanted`: Extra attention is needed
- `priority: high`: High priority issues
- `priority: medium`: Medium priority issues
- `priority: low`: Low priority issues

## Smart Contract Development

### Security Guidelines

- **External review**: All smart contract code must be reviewed by at least 1 external developer
- **Security checklist**: Use our security checklist before submission
- **Gas optimization**: Consider gas costs and optimize where possible
- **Testing**: Comprehensive testing including edge cases and error conditions

### Smart Contract Review Checklist

- [ ] Reentrancy protection implemented where needed
- [ ] Input validation for all public functions
- [ ] Access control properly implemented
- [ ] Gas optimization considered
- [ ] Error handling comprehensive
- [ ] Events emitted for important state changes
- [ ] Documentation includes security considerations

## Getting Help

### Communication Channels

- **GitHub Issues**: For bugs and feature requests
- **GitHub Discussions**: For questions and general discussion
- **Discord/Slack**: For real-time communication (if available)

### Documentation

- [README.md](README.md): General project information
- [API Documentation](docs/): Detailed API reference
- [Cosmos SDK Docs](https://docs.cosmos.network/): Framework documentation

## Recognition

We appreciate all contributions! Contributors will be:

- Listed in our contributors section
- Mentioned in release notes for significant contributions
- Invited to join our contributor community

## License

By contributing to Kudora, you agree that your contributions will be licensed under the same license as the project (MIT License).

---

Thank you for contributing to Kudora! 🚀
