FROM ruby:3.4.12-alpine3.23@sha256:ea3afe4adfa84f9cd69e09994bf05bc4b90679f53a6482ab8cfd6b67f281bb02 AS base

# Check the interpreter and default gem, independently of the application bundle.
RUN ruby -rzlib -e 'abort "Ruby is too old" if Gem::Version.new(RUBY_VERSION) < Gem::Version.new("3.4.12"); abort "zlib is too old" if Gem::Version.new(Zlib::VERSION) < Gem::Version.new("3.2.3")'

FROM base AS build

WORKDIR /app

RUN apk add --no-cache build-base
COPY Gemfile Gemfile.lock ./
ENV BUNDLE_WITHOUT="development:test" BUNDLE_FROZEN=true
RUN bundle install

FROM base

WORKDIR /app

ENV BUNDLE_WITHOUT="development:test" BUNDLE_FROZEN=true
COPY Gemfile Gemfile.lock ./
COPY --from=build /usr/local/bundle /usr/local/bundle
COPY bin/ ./bin/
COPY lib/ ./lib/

ENTRYPOINT ["bundle", "exec", "ruby", "bin/fizzy-pop"]
