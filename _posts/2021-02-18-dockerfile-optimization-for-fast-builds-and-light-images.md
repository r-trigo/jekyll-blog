---
layout: post
title: Dockerfile Optimization for Fast Builds and Light Images
date: 2021-02-18 18:51 +0000
---
:pencil: :whale: :zap:

>Originally published at [Jscrambler Blog](https://blog.jscrambler.com/dockerfile-optimization-for-fast-builds-and-light-images/)

## Prologue
> Docker builds images automatically by reading the instructions from a Dockerfile -- a text file that contains all commands, in order, needed to build a given image.

The explanation above was extracted from Docker’s [official docs][1] and summarizes what a Dockerfile is for. Dockerfiles are important to work with because they are our blueprint, our record of layers added to a Docker base image.

We will learn how to take advantage of [BuildKit][2] features, a set of enhancements introduced on Docker v18.09. Integrating BuildKit will give us better performance, storage management, and security.

## Objectives
- decrease build time;
- reduce image size;
- gain maintainability;
- gain reproducibility;
- understand multi-stage Dockerfiles;
- understand BuildKit features.

## Pre-requisites
- knowledge of Docker concepts
- Docker installed (currently using v19.03)
- a Java app (for this post I used a [sample Jenkins Maven app][3])

Let's get to it!

## Simple Dockerfile example
Below is an example of an unoptimized Dockerfile containing a Java app. This example was taken from [this DockerCon conference talk][4]. We will walk through several optimizations as we go.

```Dockerfile
FROM debian
COPY . /app
RUN apt-get update
RUN apt-get -y install openjdk-11-jdk ssh emacs
CMD [“java”, “-jar”, “/app/target/my-app-1.0-SNAPSHOT.jar”]
```

Here, we may ask ourselves: **how long does it take to build** at this stage? To answer it, let's create this Dockerfile on our local development computer and tell Docker to build the image.

```bash
# enter your Java app folder
cd simple-java-maven-app-master
# create a Dockerfile
vim Dockerfile
# write content, save and exit
docker pull debian:latest # pull the source image
time docker build --no-cache -t docker-class . # overwrite previous layers
# notice the build time
```
`0,21s user 0,23s system 0% cpu 1:55,17 total`

Here’s our answer: our build takes **1m55s** at this point.

But what if we just enable BuildKit with no additional changes? Does it make a difference?

### Enabling BuildKit

BuildKit can be enabled with two methods:

1. Setting the DOCKER_BUILDKIT=1 environment variable when invoking the Docker build command, such as:

```bash
time DOCKER_BUILDKIT=1 docker build --no-cache -t docker-class .
```

2. Enabling Docker BuildKit by default, setting the daemon configuration in the `/etc/docker/daemon.json` feature to true, and restarting the daemon:

```json
{ "features": { "buildkit": true } }
```

#### BuildKit Initial Impact

```bash
DOCKER_BUILDKIT=1 docker build --no-cache -t docker-class .
```
`0,54s user 0,93s system 1% cpu 1:43,00 total`

On the same hardware, the build took ~12 seconds less than before. This means the build got ~10,43% faster with almost no effort.

But now let’s look at some extra steps we can take to improve our results even further.

### Order from least to most frequently changing

Because order matters for caching, we'll move the `COPY` command closer to the end of the Dockerfile.

```Dockerfile
FROM debian
RUN apt-get update
RUN apt-get -y install openjdk-11-jdk ssh emacs
RUN COPY . /app
CMD [“java”, “-jar”, “/app/target/my-app-1.0-SNAPSHOT.jar”]
```

### Avoid "COPY ."
Opt for more specific COPY arguments to limit cache busts. Only copy what’s needed.

```Dockerfile
FROM debian
RUN apt-get update
RUN apt-get -y install openjdk-11-jdk ssh vim
COPY target/my-app-1.0-SNAPSHOT.jar /app
CMD [“java”, “-jar”, “/app/my-app-1.0-SNAPSHOT.jar”]
```

### Couple apt-get update & install
This prevents using an outdated package cache. Cache them together or do not cache them at all.

```Dockerfile
FROM debian
RUN apt-get update && \
    apt-get -y install openjdk-11-jdk ssh vim
COPY target/my-app-1.0-SNAPSHOT.jar /app
CMD [“java”, “-jar”, “/app/my-app-1.0-SNAPSHOT.jar”]
```

### Remove unnecessary dependencies
Don’t install debugging and editing tools—you can install them later when you feel you need them.

```Dockerfile
FROM debian
RUN apt-get update && \
    apt-get -y install --no-install-recommends \
    openjdk-11-jdk
COPY target/my-app-1.0-SNAPSHOT.jar /app
CMD [“java”, “-jar”, “/app/my-app-1.0-SNAPSHOT.jar”]
```

### Remove package manager cache

Your image does not need this cache data. Take the chance to free some space.
```Dockerfile
FROM debian
RUN apt-get update && \
    apt-get -y install --no-install-recommends \
    openjdk-11-jdk && \
    rm -rf /var/lib/apt/lists/*
COPY target/my-app-1.0-SNAPSHOT.jar /app
CMD [“java”, “-jar”, “/app/my-app-1.0-SNAPSHOT.jar”]
```

### Use official images where possible
There are some good reasons to use official images, such as reducing the time spent on maintenance and reducing the size, as well as having an image that is pre-configured for container use.

```Dockerfile
FROM openjdk
COPY target/my-app-1.0-SNAPSHOT.jar /app
CMD [“java”, “-jar”, “/app/my-app-1.0-SNAPSHOT.jar”]
```

### Use specific tags
Don’t use `latest` as it’s a rolling tag. That’s asking for unpredictable problems.

```Dockerfile
FROM openjdk:8
COPY target/my-app-1.0-SNAPSHOT.jar /app
CMD [“java”, “-jar”, “/app/my-app-1.0-SNAPSHOT.jar”]
```

### Look for minimal flavors
You can reduce the base image size. Pick the lightest one that suits your purpose. Below is a short `openjdk` images list.

| Repository | Tag | Size
|-|-|-
| openjdk | 8 | 634MB
| openjdk | 8-jre | 443MB
| openjdk | 8-jre-slim | 204MB
| openjdk | 8-jre-alpine | 83MB

### Build from a source in a consistent environment
Maybe you do not need the whole JDK. If you intended to use JDK for Maven, you can use a Maven Docker image as a base for your build.

```Dockerfile
FROM maven:3.6-jdk-8-alpine
WORKDIR /app
COPY pom.xml .
COPY src ./src
RUN mvn -e -B package
CMD [“java”, “-jar”, “/app/my-app-1.0-SNAPSHOT.jar”]
```

### Fetch dependencies in a separate step
A Dockerfile command to fetch dependencies can be cached. Caching this step will speed up our builds.

```Dockerfile
FROM maven:3.6-jdk-8-alpine
WORKDIR /app
COPY pom.xml .
RUN mvn -e -B dependency:resolve
COPY src ./src
RUN mvn -e -B package
CMD [“java”, “-jar”, “/app/my-app-1.0-SNAPSHOT.jar”]
```

### Multi-stage builds: remove build dependencies

Why use multi-stage builds?
- separate the build from the runtime environment
- DRY
- different details on dev, test, lint specific environments
- delinearizing dependencies (concurrency)
- having platform-specific stages

```Dockerfile
FROM maven:3.6-jdk-8-alpine AS builder
WORKDIR /app
COPY pom.xml .
RUN mvn -e -B dependency:resolve
COPY src ./src
RUN mvn -e -B package

FROM openjdk:8-jre-alpine
COPY --from=builder /app/target/my-app-1.0-SNAPSHOT.jar /
CMD [“java”, “-jar”, “/my-app-1.0-SNAPSHOT.jar”]
```

#### Checkpoint
If you build our application at this point,
```bash
time DOCKER_BUILDKIT=1 docker build --no-cache -t docker-class .
```

`0,41s user 0,54s system 2% cpu 35,656 total`

you'll notice our application takes **~35.66 seconds** to build. It's a pleasant improvement. From now on we will focus on the features for more possible scenarios.

### Multi-stage builds: different image flavors
The Dockerfile below shows a different stage for a Debian and an Alpine based image.

```Dockerfile
FROM maven:3.6-jdk-8-alpine AS builder
…
FROM openjdk:8-jre-jessie AS release-jessie
COPY --from=builder /app/target/my-app-1.0-SNAPSHOT.jar /
CMD [“java”, “-jar”, “/my-app-1.0-SNAPSHOT.jar”]

FROM openjdk:8-jre-alpine AS release-alpine
COPY --from=builder /app/target/my-app-1.0-SNAPSHOT.jar /
CMD [“java”, “-jar”, “/my-app-1.0-SNAPSHOT.jar”]
```

To build a specific image on a stage, we can use the `--target` argument:
```bash
time docker build --no-cache --target release-jessie .
```

### Different image flavors (DRY / global ARG)

```Dockerfile
ARG flavor=alpine
FROM maven:3.6-jdk-8-alpine AS builder
…
FROM openjdk:8-jre-$flavor AS release
COPY --from=builder /app/target/my-app-1.0-SNAPSHOT.jar /
CMD [“java”, “-jar”, “/my-app-1.0-SNAPSHOT.jar”]
```

The `ARG` command can control the image to be built. In the example above, we wrote `alpine` as default flavor, but we can pass `--build-arg flavor=<flavor>` on the `docker build` command.

```bash
time docker build --no-cache --target release --build-arg flavor=jessie .
```

### Concurrency
Concurrency is important when building Docker images as it takes the most advantage of available CPU threads. In a linear Dockerfile, all stages are executed in sequence. With multi-stage builds, we can have smaller dependency stages be ready for the main stage to use them.

BuildKit even brings another performance bonus. If stages are not used later in the build, they are directly skipped instead of processed and discarded when they finish. This means that in the stage graph representation, unneeded stages are not even considered.

Below is an example Dockerfile where a website's assets are built in an `assets` stage:

```Dockerfile
FROM maven:3.6-jdk-8-alpine AS builder
…
FROM tiborvass/whalesay AS assets
RUN whalesay “Hello DockerCon!” > out/assets.html

FROM openjdk:8-jre-alpine AS release
COPY --from=builder /app/my-app-1.0-SNAPSHOT.jar /
COPY --from=assets /out /assets
CMD [“java”, “-jar”, “/my-app-1.0-SNAPSHOT.jar”]
```

And here is another Dockerfile where C and C++ libraries are separately compiled and take part in the `builder` stage later on.

```Dockerfile
FROM maven:3.6-jdk-8-alpine AS builder-base
…

FROM gcc:8-alpine AS builder-someClib
…
RUN git clone … ./configure --prefix=/out && make && make install

FROM g++:8-alpine AS builder-some CPPlib
…
RUN git clone … && cmake …

FROM builder-base AS builder
COPY --from=builder-someClib /out /
COPY --from=builder-someCpplib /out /
```

### BuildKit Application Cache
BuildKit has a special feature regarding package managers cache. Here are some examples of cache folders typical locations:

| Package manager | Path
|-|-
| apt | /var/lib/apt/lists
| go | ~/.cache/go-build
| go-modules | $GOPATH/pkg/mod
| npm | ~/.npm
| pip | ~/.cache/pip

We can compare this Dockerfile with the one presented in the section **Build from the source in a consistent environment**. This earlier Dockerfile didn't have special cache handling. We can do that with a type of mount called cache: `--mount=type=cache`.

```Dockerfile
FROM maven:3.6-jdk-8-alpine AS builder
WORKDIR /app
RUN --mount=target=. --mount=type=cache,target /root/.m2 \
    && mvn package -DoutputDirectory=/

FROM openjdk:8-jre-alpine
COPY --from=builder /app/target/my-app-1.0-SNAPSHOT.jar /
CMD [“java”, “-jar”, “/my-app-1.0-SNAPSHOT.jar”]
```

### BuildKit Secret Volumes
To mix in some security features of BuildKit, let's see how secret type mounts are used and some cases they are meant for. The first scenario shows an example where we need to hide a secrets file, like `~/.aws/credentials`.

```Dockerfile
FROM <baseimage>
RUN …
RUN --mount=type=secret,id=aws,target=/root/.aws/credentials,required \
./fetch-assets-from-s3.sh
RUN ./build-scripts.sh
```
To build this Dockerfile, pass the `--secret` argument like this:
```bash
docker build --secret id=aws,src=~/.aws/credentials
```

The second scenario is a method to avoid commands like `COPY ./keys/private.pem /root .ssh/private.pem`, as we don't want our SSH keys to be stored on the Docker image after they are no longer needed. BuildKit has an `ssh` mount type to cover that:

```Dockerfile
FROM alpine
RUN apk add --no-cache openssh-client
RUN mkdir -p -m 0700 ~/.ssh && ssh-keyscan github.com >> ~/.ssh/known_hosts
ARG REPO_REF=19ba7bcd9976ef8a9bd086187df19ba7bcd997f2
RUN --mount=type=ssh,required git clone git@github.com:org/repo /work && cd /work && git checkout -b $REPO_REF
```
To build this Dockerfile, you need to load your private SSH key into your `ssh-agent` and add `--ssh=default`, with `default` representing the SSH private key location.

```bash
eval $(ssh-agent)
ssh-add ~/.ssh/id_rsa # this is the SSH key default location
docker build --ssh=default .
```

## Conclusion
This concludes our demo on using Docker BuildKit to optimize your Dockerfiles and consequentially speed up your images’ build time.

These speed gains result in much-needed savings in time and computational power, which should not be neglected.

Like Charles Duhigg wrote on The Power of Habit: "*small victories are the consistent application of a small advantage*". You will definitely reap the benefits if you build good practices and habits.

[1]: https://docs.docker.com/engine/reference/builder/
[2]: https://docs.docker.com/engine/reference/builder/#buildkit
[3]: https://github.com/jenkins-docs/simple-java-maven-app
[4]: https://youtu.be/JofsaZ3H1qM

<link rel="canonical" href="https://blog.jscrambler.com/dockerfile-optimization-for-fast-builds-and-light-images/" />
