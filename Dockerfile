FROM ruby:3.4-alpine AS build

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle install --without development test

FROM ruby:3.4-alpine

WORKDIR /app

COPY --from=build /usr/local/bundle /usr/local/bundle
COPY app.rb ./

ENTRYPOINT ["ruby", "app.rb", "--verbose"]
