# https://ddewaele.github.io/running-jekyll-in-docker/

# docker build -t jekyll-blog .
# docker run --rm --name jekyll-blog -p 4000:4000 -v $PWD:/srv/jekyll jekyll-blog

FROM jekyll/jekyll:4.1.0
EXPOSE 4000
CMD [ "jekyll", "serve", "--watch", "--drafts" ]