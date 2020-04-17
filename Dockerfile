# docker build -t rt-jekyll-website .
# docker run -d --rm --name jekyll -p 4000:4000 rt-jekyll-website
# or
# docker run -d --rm --name jekyll -v ~/repos/rt-jekyll-website:/app -p 4000:4000 ruby bash
FROM ruby
COPY . /app
WORKDIR /app
RUN bundle install
CMD ["jekyll", "serve", "-H", "0.0.0.0"]
