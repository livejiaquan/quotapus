# Security Policy

## Reporting a Vulnerability

If you find a security vulnerability in Quotapus, please report it privately. Do not open a public issue.

1. Go to the [Security Advisories page](https://github.com/livejiaquan/quotapus/security/advisories/new)
2. Click "Report a vulnerability"
3. Fill in the details

This keeps the report private until a fix is released.

## What to Include

- Description of the vulnerability
- Steps to reproduce
- Affected versions
- Impact assessment (what can an attacker do?)

## Scope

In scope:

- The Quotapus app
- The built-in providers (credential handling, API calls)
- Remote Devices (the SSH import and the remote exporter script)
- The local HTTP API
- Build and release infrastructure

Out of scope:

- Third-party provider APIs (report to the provider directly)
- Social engineering attacks
- Denial of service attacks

Vulnerabilities in code inherited from [OpenUsage](https://github.com/robinebers/openusage) are worth reporting upstream as well.

## Supported Versions

Only the latest release is supported with security updates.
