# docker build -t rt-jekyll-site .
# docker run -d --rm --name jekyll -p 4000:4000 rt-jekyll-site
# or
# docker run -d --rm --name jekyll -v ~/repos/rt-jekyll-site:/app -p 4000:4000 ruby bash
FROM ruby
COPY . /app
WORKDIR /app
RUN bundle install
CMD ["jekyll", "serve", "-H", "0.0.0.0"]
