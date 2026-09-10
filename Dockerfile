FROM ruby:3.2-slim

# build-essential: some gems in the dependency tree may need to compile native
# extensions on Linux even when they ship precompiled darwin binaries for local dev.
# git: bgg_data.gemspec shells out to `git ls-files` to build its file list.
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY . .

# Gemfile.lock was generated on macOS (arm64-darwin) and has no Linux platform entry,
# so a plain `bundle install` here fails with "Your bundle only supports platforms
# [...]". Add this image's platform(s) to the lock before installing, so it resolves
# Linux-compatible (often precompiled) gem variants instead.
RUN gem install bundler -v "$(tail -1 Gemfile.lock | tr -d '[:space:]')" \
  && bundle lock --add-platform x86_64-linux --add-platform aarch64-linux \
  && bundle install

EXPOSE 8080

CMD ["bin/http_server"]
