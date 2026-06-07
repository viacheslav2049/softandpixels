# syntax=docker/dockerfile:1.7

FROM ruby:3.3.6-slim AS builder
RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential libyaml-dev \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY Gemfile Gemfile.lock ./
RUN bundle config set --local without 'development test' \
    && bundle install --jobs 4

FROM ruby:3.3.6-slim
RUN apt-get update \
    && apt-get install -y --no-install-recommends libyaml-0-2 \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --system --gid 1000 app \
    && useradd  --system --uid 1000 --gid 1000 --no-create-home app
WORKDIR /app
COPY --from=builder /usr/local/bundle /usr/local/bundle
COPY --chown=app:app . /app
USER app
ENV PORT=4567
EXPOSE 4567
HEALTHCHECK CMD ruby -rsocket -e 'TCPSocket.new("127.0.0.1",ENV["PORT"]).close'
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
