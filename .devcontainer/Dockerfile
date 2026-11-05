# Development-only image; production uses the root Dockerfile.
FROM maven:3.9-eclipse-temurin-25
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --gid 1000 vscode \
    && useradd --uid 1000 --gid 1000 -m -s /bin/bash vscode \
    && mkdir -p /home/vscode/.m2 \
    && chown -R vscode:vscode /home/vscode
USER vscode
WORKDIR /workspaces/limitcore
