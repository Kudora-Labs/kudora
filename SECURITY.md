# Security Policy

## Reporting Security Vulnerabilities

We take the security of Kudora seriously. If you believe you have found a security vulnerability, please report it to us as described below.

## How to Report a Security Vulnerability

**Please do not report security vulnerabilities through public GitHub issues.**

Instead, please report them via email to: **kudora-labs@kudora.org**

You should receive a response within 48 hours. If for some reason you do not, please follow up via email to ensure we received your original message.

## What to Include in Your Report

Please include the following information in your security report:

- Type of issue (e.g., buffer overflow, SQL injection, cross-site scripting, etc.)
- Full paths of source file(s) related to the manifestation of the issue
- The location of the affected source code (tag/branch/commit or direct URL)
- Any special configuration required to reproduce the issue
- Step-by-step instructions to reproduce the issue
- Proof-of-concept or exploit code (if possible)
- Impact of the issue, including how an attacker might exploit the issue

## Our Response Process

1. **Acknowledgment**: We will acknowledge receipt of your vulnerability report within 48 hours
2. **Assessment**: We will assess the vulnerability and determine its severity level
3. **Fix Development**: We will work on developing a fix for confirmed vulnerabilities
4. **Disclosure Timeline**: We will coordinate with you on the disclosure timeline
5. **Public Disclosure**: After the fix is deployed, we will publicly disclose the vulnerability

## Disclosure Policy

- We ask that you give us reasonable time to investigate and mitigate an issue before making any information public
- We will make every effort to acknowledge your responsible disclosure
- We will provide updates on our progress in resolving the issue
- When we publish information about a security issue, we will acknowledge your responsible disclosure (unless you prefer to remain anonymous)

## Scope

This security policy applies to:

- The main Kudora blockchain codebase
- Custom modules in the `x/` directory
- Application logic and configuration
- Smart contract interactions (EVM compatibility layer)
- IBC-related functionality
- API endpoints and interfaces

### Out of Scope

- Third-party dependencies (please report to the respective maintainers)
- Issues in testnet or development environments that do not affect production
- Issues requiring physical access to infrastructure
- Social engineering attacks

## Security Best Practices for Contributors

If you're contributing to Kudora, please:

- Follow secure coding practices
- Validate all inputs and sanitize outputs
- Use established cryptographic libraries
- Implement proper error handling
- Add security-focused tests for new features
- Keep dependencies up to date

## Bug Bounty Program

Currently, we do not have a formal bug bounty program. However, we greatly appreciate responsible disclosure and will acknowledge security researchers who help improve our security posture.

## Vulnerability Severity Guidelines

We use the following severity levels:

### Critical
- Remote code execution
- Privilege escalation to admin/validator level
- Consensus breaking vulnerabilities
- Fund loss or theft vulnerabilities

### High
- Authentication bypass
- Unauthorized access to sensitive data
- DoS attacks that can take down the network
- Significant smart contract vulnerabilities

### Medium
- Information disclosure
- DoS attacks with limited impact
- Logic errors with security implications

### Low
- Minor information leakage
- Security misconfigurations with minimal impact

## Supported Versions

We support security updates for:

| Version | Supported          |
| ------- | ------------------ |
| Latest  | ✅ Active support  |
| Previous| ⚠️ Limited support |
| Older   | ❌ No support      |

## Security Updates

Security updates will be released as:

- Patch releases for critical and high severity issues
- Minor releases for medium severity issues
- Major releases for low severity issues (bundled with other changes)

Security advisories will be published in our GitHub Security Advisories section.

## Contact Information

For security-related inquiries:

<!-- - **Email**: security@kudoralabs.com -->
- **PGP Key**: [Available upon request]
- **Response Time**: Within 48 hours

For general questions about this security policy:

- **Email**: kudora-labs@kudora.org
- **GitHub Issues**: For non-security related questions only

## Acknowledgments

We thank the following security researchers for their responsible disclosure:

<!-- This section will be updated as we receive and resolve security reports -->

*No security reports have been received yet.*

---

**Last Updated**: January 2025

Thank you for helping keep Kudora and our community safe!