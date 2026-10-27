# Quality gates and release policy

GitHub Actions runs Maven verify including JUnit tests and Redis Testcontainers integration tests. JaCoCo coverage is uploaded as an artifact. CodeQL runs on pushes, PRs and weekly; dependency review runs on pull requests. Dependabot proposes dependency updates.

## SonarQube

sonar-project.properties provides basic project paths. A SonarQube or SonarCloud organization and authentication token must be configured before automated analysis can run. Do not commit tokens. A passing SonarQube quality gate has not yet been demonstrated.

## Acceptance criteria for production

1. CI and CodeQL passing at the release commit.
2. Concurrent quota tests against Redis under load.
3. Authentication and tenant isolation review.
4. Failure injection and Redis failover assessment.
5. Key cardinality and memory exhaustion protection.
6. HTTPS, network isolation and management endpoint protection.
7. Performance budgets validated on representative hardware.
8. Rollback rehearsal and operator runbook sign-off.

Do not claim production readiness solely from passing unit tests.
