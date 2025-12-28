# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2025-12-28

### Added

- IMAP IDLE command support for real-time mailbox updates
  - `Client.idle/1` function to enter IDLE state and wait for server notifications
- IMAP CREATE command support for creating new mailboxes
  - `Client.create/2` function to create mailboxes
- IMAP APPEND command support for adding messages to mailboxes
  - `Client.append/4` and `Client.append/5` functions with support for flags and datetime
- Comprehensive integration testing with GreenMail
  - Docker Compose setup for local testing
  - Full lifecycle integration tests
  - IDLE with concurrent append tests
- GitHub Actions CI/CD pipeline
  - Unit tests workflow
  - Integration tests workflow with GreenMail
- Environment-specific configuration files (`config/dev.exs`, `config/test.exs`)

### Changed

- Optimized message receiving logic by replacing regex with efficient binary pattern matching
  - Improved performance of `assemble_msg/2` function
  - Better handling of tagged responses and trailing data
- Updated CI to use Elixir 1.19 and OTP 28
- Improved README with better structure and examples

### Fixed

- Integration test stability improvements
- Unused variable warnings in tests
- Mock socket implementation improvements

## [0.1.5] - Previous Release

(Earlier changes not documented)
