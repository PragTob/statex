FROM hexpm/elixir:1.19.5-erlang-28.5-debian-trixie-20260421

# Core build dependencies (NOT git anymore — handled via features)
RUN apt-get update && apt-get install -y \
    git \
    build-essential \
    curl \
    inotify-tools \
    ca-certificates \
    && apt-get clean -y && rm -rf /var/lib/apt/lists/*

# Ensure Hex + Rebar exist for any mix operations
RUN mix local.hex --force && \
    mix local.rebar --force

# Optional but helpful for debugging / shell ergonomics
ENV ERL_AFLAGS="+B -kernel shell_history enabled"

WORKDIR /workspace