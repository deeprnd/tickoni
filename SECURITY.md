# Security

This document describes the current security status and vulnerability-reporting process for Tickoni.

Tickoni’s systems foundation originates in Firedancer, Jump Crypto’s high-performance Solana systems codebase.

Firedancer contributes low-level C infrastructure for high-throughput networking, preallocated memory workspaces, concurrent processing, and restrictive process isolation. Tickoni repurposes that foundation for autonomous capital allocation.

Firedancer’s security programs and audit reports cover the Firedancer project. They do not automatically cover Tickoni’s investment, agent, portfolio-management, or execution components.

## Table of Contents

* [Reporting a Vulnerability](#reporting-a-vulnerability)
* [Security Status](#security-status)
* [Firedancer Security Resources](#firedancer-security-resources)

## Reporting a Vulnerability

Security vulnerabilities affecting Tickoni should be reported through the repository’s private security-reporting channel.

Please do not open a public GitHub issue for a vulnerability until it has been reviewed and addressed.

Non-security bugs may be submitted through the Tickoni GitHub issue tracker.

## Security Status

Tickoni is experimental software and remains under active development.

Tickoni-specific components have not yet undergone independent third-party security audits or a public bug-bounty program.

Use paper capital, conservative limits, restricted credentials, and staged approvals before enabling live execution.

## Firedancer Security Resources

The systems infrastructure inherited from Firedancer has been developed alongside Firedancer’s broader security program.

Relevant Firedancer resources include:

* [Firedancer Immunefi bug bounty program](https://immunefi.com/bug-bounty/Frankendancer/)
* [Firedancer v0.1 audit reports](https://github.com/firedancer-io/audits)
* [Firedancer v0.1 audit contest](https://github.com/immunefi-team/Bounty_Boosts/tree/main/Firedancer%20v0.1)

These resources provide useful security context for the Firedancer-derived systems foundation. They should not be interpreted as an audit, endorsement, or bug bounty covering Tickoni as a whole.
