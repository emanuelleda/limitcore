# Contributing

Thanks for contributing to LimitCore.

1. Open an issue describing the bug or feature.
2. Create a focused branch and submit a pull request.
3. Include automated tests for behavior changes.
4. Run `mvn verify` and document any Redis-specific testing.
5. Never commit API keys, passwords, credentials, or personal data.

Changes to quota semantics must explain concurrency, Redis failures and backward compatibility.
